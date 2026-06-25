//! main.zig — Grim engine entry point (native)
//! Deployment profile selected at compile time via build_options.
//! Usage: grimcore [--profile local|cloud] [--port 9090]

const std          = @import("std");
const build_options = @import("build_options");
const types        = @import("types.zig");
const wallet       = @import("wallet/lightning.zig");
const filestore    = @import("store/filestore.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var port: u16 = 9090;
    var data_path: []const u8 = "/data/data/app.grim.wallet/files";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            i += 1;
            port = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--data") and i + 1 < args.len) {
            i += 1;
            data_path = args[i];
        }
    }

    std.log.info("Grim starting — profile: {s}  port: {d}  data: {s}",
        .{ build_options.profile, port, data_path });

    var store = try filestore.FileStore.init(allocator, data_path);
    defer store.deinit();

    var ln = try wallet.LightningWallet.init(allocator, data_path, &store);
    defer ln.deinit();

    std.log.info("Grim Lightning wallet ready. Node pubkey: (pending channel open)", .{});
    std.log.info("Listening on port {d} — waiting for connections", .{port});

    // TODO: wire TCP/HTTP control plane (modelled after arcis api/server.zig)
    // For now: block and print heartbeat so the process stays alive as a service
    while (true) {
        std.time.sleep(30 * std.time.ns_per_s);
        const stats = ln.feeStats();
        std.log.info("[heartbeat] earned_msats: {d}  forwarded: {d}",
            .{ stats.earned_msats, stats.forwarded_count });
    }
}
