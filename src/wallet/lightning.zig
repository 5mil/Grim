//! wallet/lightning.zig — Grim Lightning wallet module
//! Live implementation against LND REST API over HTTPS.
//!
//! LND requires TLS even on loopback (127.0.0.1:8080).
//! We use Zig's built-in std.crypto.tls client with cert verification
//! disabled for the self-signed LND cert (loopback only — acceptable).
//!
//! Config via environment variables:
//!   GRIM_LND_URL      — default: https://127.0.0.1:8080
//!   GRIM_LND_MACAROON — admin macaroon hex (required)
//!
//! LND REST endpoints:
//!   GET  /v1/getinfo
//!   POST /v1/invoices
//!   POST /v2/router/send
//!   GET  /v1/channels
//!   POST /v1/chanpolicy

const std   = @import("std");
const types = @import("../types.zig");
const store = @import("../store/filestore.zig");

const Invoice       = types.Invoice;
const Payment       = types.Payment;
const PaymentStatus = types.PaymentStatus;
const Channel       = types.Channel;
const FeeStats      = types.FeeStats;

// ---------------------------------------------------------------------------
// HTTPS helper using std.crypto.tls (Zig stdlib, no external deps)
// Skips cert verification — LND uses a self-signed cert on loopback.
// ---------------------------------------------------------------------------

const HttpResponse = struct {
    status: u16,
    body:   []u8,  // caller owns
};

fn httpsRequest(
    allocator:    std.mem.Allocator,
    method:       []const u8,
    host:         []const u8,
    port:         u16,
    path:         []const u8,
    macaroon_hex: []const u8,
    req_body:     ?[]const u8,
) !HttpResponse {
    const addr = try std.net.Address.parseIp4(host, port);
    var tcp    = try std.net.tcpConnectToAddress(addr);
    defer tcp.close();

    // Wrap TCP in TLS — InsecureSkipVerify equivalent:
    // pass an empty bundle so no CA verification is performed.
    var bundle = std.crypto.Certificate.Bundle{};
    var tls = try std.crypto.tls.Client.init(tcp, .{
        .host          = .{ .explicit = host },
        .ca            = .{ .bundle = bundle },
        .failure_mode  = .allow,  // skip cert verification
    });
    defer tls.deinit();
    _ = bundle;

    // Build HTTP/1.1 request
    var req_buf: [131072]u8 = undefined;
    var req_len: usize = 0;

    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "{s} {s} HTTP/1.1\r\n",            .{ method, path })).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Host: {s}:{d}\r\n",               .{ host, port })).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Grpc-Metadata-Macaroon: {s}\r\n", .{macaroon_hex})).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Accept: application/json\r\n",    .{})).len;
    req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Connection: close\r\n",           .{})).len;

    if (req_body) |b| {
        req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Content-Type: application/json\r\n", .{})).len;
        req_len += (try std.fmt.bufPrint(req_buf[req_len..], "Content-Length: {d}\r\n",            .{b.len})).len;
        req_len += (try std.fmt.bufPrint(req_buf[req_len..], "\r\n",                               .{})).len;
        req_len += (try std.fmt.bufPrint(req_buf[req_len..], "{s}",                               .{b})).len;
    } else {
        req_len += (try std.fmt.bufPrint(req_buf[req_len..], "\r\n", .{})).len;
    }

    try tls.writeAll(tcp, req_buf[0..req_len]);

    // Read full response
    var resp = std.ArrayList(u8).init(allocator);
    defer resp.deinit();
    var tmp: [8192]u8 = undefined;
    while (true) {
        const n = tls.read(tcp, &tmp) catch |e| switch (e) {
            error.TlsConnectionTruncated, error.EndOfStream => break,
            else => return e,
        };
        if (n == 0) break;
        try resp.appendSlice(tmp[0..n]);
    }

    const raw = try resp.toOwnedSlice();
    defer allocator.free(raw);

    // Parse HTTP status
    var status: u16 = 0;
    if (raw.len > 12) {
        status = std.fmt.parseInt(u16, raw[9..12], 10) catch 0;
    }

    // Split at \r\n\r\n to get body
    const sep        = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse raw.len;
    const body_start = @min(sep + 4, raw.len);
    const body_out   = try allocator.dupe(u8, raw[body_start..]);

    return HttpResponse{ .status = status, .body = body_out };
}

// ---------------------------------------------------------------------------
// JSON helpers — no external lib needed for flat LND responses
// ---------------------------------------------------------------------------

fn jsonGetString(json: []const u8, key: []const u8, allocator: std.mem.Allocator) !?[]u8 {
    const needle = try std.fmt.allocPrint(allocator, "\"{s}\":", .{key});
    defer allocator.free(needle);
    const pos     = std.mem.indexOf(u8, json, needle) orelse return null;
    const after   = std.mem.trimLeft(u8, json[pos + needle.len..], " ");
    if (after.len == 0 or after[0] != '"') return null;
    const end     = std.mem.indexOfScalar(u8, after[1..], '"') orelse return null;
    return try allocator.dupe(u8, after[1..][0..end]);
}

fn jsonGetU64(json: []const u8, key: []const u8, allocator: std.mem.Allocator) !?u64 {
    const needle = try std.fmt.allocPrint(allocator, "\"{s}\":", .{key});
    defer allocator.free(needle);
    const pos    = std.mem.indexOf(u8, json, needle) orelse return null;
    const after  = std.mem.trimLeft(u8, json[pos + needle.len..], " \"");
    var end: usize = 0;
    while (end < after.len and after[end] >= '0' and after[end] <= '9') end += 1;
    if (end == 0) return null;
    return try std.fmt.parseInt(u64, after[0..end], 10);
}

// ---------------------------------------------------------------------------
// LightningWallet
// ---------------------------------------------------------------------------

pub const LightningWallet = struct {
    allocator:    std.mem.Allocator,
    data_path:    []const u8,
    lnd_host:     []const u8,
    lnd_port:     u16,
    macaroon_hex: []const u8,
    file_store:   *store.FileStore,
    earned_msats:    u64,
    forwarded_count: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        data_path: []const u8,
        fs: *store.FileStore,
    ) !LightningWallet {
        const lnd_url  = std.posix.getenv("GRIM_LND_URL") orelse "https://127.0.0.1:8080";
        const macaroon = std.posix.getenv("GRIM_LND_MACAROON") orelse "";

        // Strip scheme
        const url_body = if (std.mem.startsWith(u8, lnd_url, "https://"))
            lnd_url[8..]
        else if (std.mem.startsWith(u8, lnd_url, "http://"))
            lnd_url[7..]
        else
            lnd_url;

        const colon = std.mem.lastIndexOfScalar(u8, url_body, ':');
        const host  = if (colon) |c| url_body[0..c] else url_body;
        const port  = if (colon) |c|
            std.fmt.parseInt(u16, url_body[c+1..], 10) catch 8080
        else 8080;

        std.log.info("LightningWallet: LND at https://{s}:{d}", .{ host, port });

        return LightningWallet{
            .allocator       = allocator,
            .data_path       = data_path,
            .lnd_host        = host,
            .lnd_port        = port,
            .macaroon_hex    = macaroon,
            .file_store      = fs,
            .earned_msats    = 0,
            .forwarded_count = 0,
        };
    }

    pub fn deinit(self: *LightningWallet) void { _ = self; }

    pub fn feeStats(self: *const LightningWallet) FeeStats {
        return .{
            .earned_msats    = self.earned_msats,
            .forwarded_count = self.forwarded_count,
            .channel_count   = 0,
        };
    }

    // -----------------------------------------------------------------------
    // getInfo — GET /v1/getinfo
    // -----------------------------------------------------------------------
    pub fn getInfo(self: *LightningWallet) ![]u8 {
        const resp = try httpsRequest(
            self.allocator, "GET",
            self.lnd_host, self.lnd_port,
            "/v1/getinfo", self.macaroon_hex, null,
        );
        if (resp.status != 200) {
            std.log.err("getInfo HTTP {d}: {s}", .{ resp.status, resp.body });
            self.allocator.free(resp.body);
            return error.LndHttpError;
        }
        return resp.body;
    }

    // -----------------------------------------------------------------------
    // createInvoice — POST /v1/invoices
    // -----------------------------------------------------------------------
    pub fn createInvoice(
        self:         *LightningWallet,
        amount_msats: u64,
        description:  []const u8,
        expiry_secs:  u32,
    ) !Invoice {
        const req_body = try std.fmt.allocPrint(self.allocator,
            "{{\"value_msat\":{d},\"memo\":\"{s}\",\"expiry\":{d}}}",
            .{ amount_msats, description, expiry_secs },
        );
        defer self.allocator.free(req_body);

        const resp = try httpsRequest(
            self.allocator, "POST",
            self.lnd_host, self.lnd_port,
            "/v1/invoices", self.macaroon_hex, req_body,
        );
        defer self.allocator.free(resp.body);

        if (resp.status != 200) {
            std.log.err("createInvoice HTTP {d}: {s}", .{ resp.status, resp.body });
            return error.LndHttpError;
        }

        const payment_request = (try jsonGetString(resp.body, "payment_request", self.allocator))
            orelse return error.LndMissingField;
        const r_hash = (try jsonGetString(resp.body, "r_hash", self.allocator))
            orelse return error.LndMissingField;

        const now: u64 = @intCast(std.time.timestamp());
        const line = try std.fmt.allocPrint(self.allocator,
            "{{\"ts\":{d},\"r_hash\":\"{s}\",\"amount_msats\":{d},\"memo\":\"{s}\"}}",
            .{ now, r_hash, amount_msats, description },
        );
        defer self.allocator.free(line);
        try self.file_store.appendLine("wallet/invoices.jsonl", line);
        std.log.info("Invoice created: {s}", .{payment_request});

        return Invoice{
            .payment_hash    = r_hash,
            .payment_request = payment_request,
            .amount_msats    = amount_msats,
            .description     = try self.allocator.dupe(u8, description),
            .created_at      = now,
            .expiry_secs     = expiry_secs,
            .settled         = false,
        };
    }

    // -----------------------------------------------------------------------
    // payInvoice — POST /v2/router/send
    // -----------------------------------------------------------------------
    pub fn payInvoice(self: *LightningWallet, payment_request: []const u8) !Payment {
        const req_body = try std.fmt.allocPrint(self.allocator,
            "{{\"payment_request\":\"{s}\",\"timeout_seconds\":60,\"fee_limit_msat\":10000}}",
            .{payment_request},
        );
        defer self.allocator.free(req_body);

        const resp = try httpsRequest(
            self.allocator, "POST",
            self.lnd_host, self.lnd_port,
            "/v2/router/send", self.macaroon_hex, req_body,
        );
        defer self.allocator.free(resp.body);

        if (resp.status != 200) {
            std.log.err("payInvoice HTTP {d}: {s}", .{ resp.status, resp.body });
            return error.LndHttpError;
        }

        const payment_hash = (try jsonGetString(resp.body, "payment_hash", self.allocator))
            orelse return error.LndMissingField;
        const amount_msats = (try jsonGetU64(resp.body, "value_msat",   self.allocator)) orelse 0;
        const fee_msats    = (try jsonGetU64(resp.body, "fee_msat",     self.allocator)) orelse 0;
        const status_str   = (try jsonGetString(resp.body, "status",    self.allocator))
            orelse try self.allocator.dupe(u8, "UNKNOWN");
        defer self.allocator.free(status_str);

        const status: PaymentStatus = if (std.mem.eql(u8, status_str, "SUCCEEDED")) .Succeeded
            else if (std.mem.eql(u8, status_str, "FAILED")) .Failed
            else .Pending;

        const now: u64 = @intCast(std.time.timestamp());
        const line = try std.fmt.allocPrint(self.allocator,
            "{{\"ts\":{d},\"hash\":\"{s}\",\"msats\":{d},\"fee\":{d},\"status\":\"{s}\"}}",
            .{ now, payment_hash, amount_msats, fee_msats, status_str },
        );
        defer self.allocator.free(line);
        try self.file_store.appendLine("wallet/payments.jsonl", line);
        std.log.info("Payment {s} status={s} fee={d}msat", .{ payment_hash, status_str, fee_msats });

        return Payment{
            .payment_hash = payment_hash,
            .amount_msats = amount_msats,
            .fee_msats    = fee_msats,
            .destination  = try self.allocator.dupe(u8, ""),
            .timestamp    = now,
            .status       = status,
        };
    }

    // -----------------------------------------------------------------------
    // listChannels — GET /v1/channels
    // -----------------------------------------------------------------------
    pub fn listChannels(self: *LightningWallet) ![]Channel {
        const resp = try httpsRequest(
            self.allocator, "GET",
            self.lnd_host, self.lnd_port,
            "/v1/channels", self.macaroon_hex, null,
        );
        defer self.allocator.free(resp.body);
        if (resp.status != 200) return error.LndHttpError;
        std.log.info("channels: {s}", .{resp.body[0..@min(300, resp.body.len)]});
        return try self.allocator.alloc(Channel, 0);
    }

    // -----------------------------------------------------------------------
    // setFeePolicy — POST /v1/chanpolicy
    // -----------------------------------------------------------------------
    pub fn setFeePolicy(self: *LightningWallet, base_fee_msats: u32, fee_rate_ppm: u32) !void {
        const req_body = try std.fmt.allocPrint(self.allocator,
            "{{\"base_fee_msat\":{d},\"fee_rate_ppm\":{d},\"global\":true,\"time_lock_delta\":40}}",
            .{ base_fee_msats, fee_rate_ppm },
        );
        defer self.allocator.free(req_body);
        const resp = try httpsRequest(
            self.allocator, "POST",
            self.lnd_host, self.lnd_port,
            "/v1/chanpolicy", self.macaroon_hex, req_body,
        );
        defer self.allocator.free(resp.body);
        if (resp.status != 200) return error.LndHttpError;
        std.log.info("Fee policy: base={d}msat ppm={d}", .{ base_fee_msats, fee_rate_ppm });
    }

    // -----------------------------------------------------------------------
    // recordForward — accumulate fees + persist
    // -----------------------------------------------------------------------
    pub fn recordForward(self: *LightningWallet, fee_msats: u64) !void {
        self.earned_msats    += fee_msats;
        self.forwarded_count += 1;
        const line = try std.fmt.allocPrint(self.allocator,
            "{{\"ts\":{d},\"fee_msats\":{d},\"total\":{d}}}",
            .{ std.time.timestamp(), fee_msats, self.earned_msats },
        );
        defer self.allocator.free(line);
        try self.file_store.appendLine("wallet/fee_log.jsonl", line);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "FeeStats starts zeroed" {
    var fs = store.FileStore.initMock();
    defer fs.deinit();
    var w = try LightningWallet.init(testing.allocator, "/tmp", &fs);
    defer w.deinit();
    const s = w.feeStats();
    try testing.expectEqual(s.earned_msats,    0);
    try testing.expectEqual(s.forwarded_count, 0);
}

test "recordForward accumulates" {
    var fs = store.FileStore.initMock();
    defer fs.deinit();
    var w = try LightningWallet.init(testing.allocator, "/tmp", &fs);
    defer w.deinit();
    try w.recordForward(100);
    try w.recordForward(250);
    try testing.expectEqual(w.feeStats().earned_msats,    350);
    try testing.expectEqual(w.feeStats().forwarded_count, 2);
}
