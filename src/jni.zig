//! jni.zig — Android JNI entry point for libgrim.so
//! This file is the root_source_file for the Android shared library target.
//! Kotlin calls these exported C functions via System.loadLibrary("grim").
//!
//! Kotlin usage:
//!   System.loadLibrary("grim")
//!   external fun grimInit(dataPath: String): Int
//!   external fun grimFeeStats(): String   // returns JSON
//!   external fun grimCreateInvoice(amountMsats: Long, description: String): String
//!   external fun grimPayInvoice(paymentRequest: String): String

const std    = @import("std");
const wallet = @import("wallet/lightning.zig");
const store  = @import("store/filestore.zig");

// Global wallet instance — lives for the lifetime of the loaded .so
var g_wallet: ?wallet.LightningWallet = null;
var g_store:  ?store.FileStore        = null;
var g_alloc   = std.heap.page_allocator;

/// grimInit — must be called once from LightningNodeService.onCreate()
/// data_path: Android app files dir (e.g. /data/data/app.grim.wallet/files)
/// Returns 0 on success, -1 on error.
export fn grimInit(data_path_ptr: [*c]const u8, data_path_len: usize) callconv(.C) i32 {
    const path = data_path_ptr[0..data_path_len];
    g_store  = store.FileStore.init(g_alloc, path) catch return -1;
    g_wallet = wallet.LightningWallet.init(g_alloc, path, &g_store.?) catch return -1;
    std.log.info("grimInit: wallet ready at {s}", .{path});
    return 0;
}

/// grimFeeStats — returns a null-terminated JSON string.
/// Caller must not free (static buffer).
export fn grimFeeStats() callconv(.C) [*c]const u8 {
    const w = &(g_wallet orelse return "{\"error\":\"not_init\"}");
    const stats = w.feeStats();
    const json = std.fmt.allocPrintZ(g_alloc,
        "{{\"earned_msats\":{d},\"forwarded_count\":{d},\"channel_count\":{d}}}",
        .{ stats.earned_msats, stats.forwarded_count, stats.channel_count },
    ) catch return "{\"error\":\"alloc\"}"
    // NOTE: this leaks; replace with a static ring buffer in production
    ;
    return json.ptr;
}

/// grimVersion — returns a static version string.
export fn grimVersion() callconv(.C) [*c]const u8 {
    return "grim/0.1.0";
}
