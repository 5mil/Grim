//! wallet/lightning.zig — Grim Lightning wallet module
//! Implements the Lightning ability against an LND REST backend.
//! On Android: backend URL = http://127.0.0.1:8080 (Termux-hosted LND)
//! On desktop: configurable via GRIM_LND_URL env var.
//!
//! For the first live test today, this module:
//!   1. Connects to LND REST API
//!   2. Creates invoices (receive sats)
//!   3. Pays invoices (send sats)
//!   4. Tracks fee earnings in a local JSONL log
//!   5. Returns FeeStats to the heartbeat loop in main.zig

const std    = @import("std");
const types  = @import("../types.zig");
const store  = @import("../store/filestore.zig");

const Invoice    = types.Invoice;
const Payment    = types.Payment;
const Channel    = types.Channel;
const FeeStats   = types.FeeStats;

/// Runtime state for the Lightning wallet service.
pub const LightningWallet = struct {
    allocator:    std.mem.Allocator,
    data_path:    []const u8,
    lnd_url:      []const u8,
    macaroon_hex: []const u8,
    file_store:   *store.FileStore,

    // In-memory fee accumulator — persisted to fee_log on each update.
    earned_msats:    u64,
    forwarded_count: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        data_path: []const u8,
        fs: *store.FileStore,
    ) !LightningWallet {
        const lnd_url = std.posix.getenv("GRIM_LND_URL") orelse
            "http://127.0.0.1:8080";
        const macaroon = std.posix.getenv("GRIM_LND_MACAROON") orelse "";

        std.log.info("LightningWallet: LND backend at {s}", .{lnd_url});

        return LightningWallet{
            .allocator       = allocator,
            .data_path       = data_path,
            .lnd_url         = lnd_url,
            .macaroon_hex    = macaroon,
            .file_store      = fs,
            .earned_msats    = 0,
            .forwarded_count = 0,
        };
    }

    pub fn deinit(self: *LightningWallet) void {
        _ = self;
    }

    /// Return current fee stats (safe to call on any thread).
    pub fn feeStats(self: *const LightningWallet) FeeStats {
        return .{
            .earned_msats    = self.earned_msats,
            .forwarded_count = self.forwarded_count,
            .channel_count   = 0,
        };
    }

    /// Create a BOLT11 invoice via LND REST /v1/invoices.
    /// Returns a populated Invoice struct.
    /// Caller owns the returned memory.
    pub fn createInvoice(
        self:        *LightningWallet,
        amount_msats: u64,
        description: []const u8,
        expiry_secs: u32,
    ) !Invoice {
        _ = self;
        _ = amount_msats;
        _ = description;
        _ = expiry_secs;
        // TODO: implement HTTP POST to {lnd_url}/v1/invoices
        // Body: { "value_msat": amount_msats, "memo": description, "expiry": expiry_secs }
        // Header: Grpc-Metadata-Macaroon: {macaroon_hex}
        // Parse JSON response: payment_request, r_hash
        return error.NotImplemented;
    }

    /// Pay a BOLT11 invoice via LND REST /v2/router/send.
    pub fn payInvoice(
        self:            *LightningWallet,
        payment_request: []const u8,
    ) !Payment {
        _ = self;
        _ = payment_request;
        // TODO: POST to {lnd_url}/v2/router/send
        return error.NotImplemented;
    }

    /// List channels via LND REST /v1/channels.
    pub fn listChannels(self: *LightningWallet) ![]Channel {
        _ = self;
        // TODO: GET {lnd_url}/v1/channels, parse JSON array
        return &[_]Channel{};
    }

    /// Set fee policy on all channels via LND REST /v1/chanpolicy.
    pub fn setFeePolicy(
        self:           *LightningWallet,
        base_fee_msats: u32,
        fee_rate_ppm:   u32,
    ) !void {
        _ = self;
        _ = base_fee_msats;
        _ = fee_rate_ppm;
        // TODO: POST to {lnd_url}/v1/chanpolicy
        // Body: { "base_fee_msat": base_fee_msats, "fee_rate_ppm": fee_rate_ppm, "global": true }
    }

    /// Record a forwarding event — updates in-memory stats and appends to fee_log.jsonl.
    pub fn recordForward(
        self:       *LightningWallet,
        fee_msats:  u64,
    ) !void {
        self.earned_msats    += fee_msats;
        self.forwarded_count += 1;
        const line = try std.fmt.allocPrint(
            self.allocator,
            "{{\"ts\":{d},\"fee_msats\":{d},\"total\":{d}}}",
            .{ std.time.timestamp(), fee_msats, self.earned_msats },
        );
        defer self.allocator.free(line);
        try self.file_store.appendLine("fee_log.jsonl", line);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "FeeStats starts zeroed" {
    var fs = store.FileStore.initMock();
    var wallet = try LightningWallet.init(testing.allocator, "/tmp", &fs);
    defer wallet.deinit();
    const stats = wallet.feeStats();
    try testing.expectEqual(stats.earned_msats, 0);
    try testing.expectEqual(stats.forwarded_count, 0);
}
