//! build.zig — Grim engine build script
//! Zig port of the Unison Grim engine.
//! Produces: grimcore (native binary) + libgrim.so (Android shared library)
//!
//! zig build                        — native binary
//! zig build android                — cross-compile .so for Android arm64
//! zig build test                   — run all subsystem tests
//! zig build run -- --profile local — run local deployment profile

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const profile = b.option(
        []const u8, "profile",
        "Deployment profile: local (default) or cloud",
    ) orelse "local";

    const opts = b.addOptions();
    opts.addOption([]const u8, "profile", profile);

    // -------------------------------------------------------------------------
    // Native binary
    // -------------------------------------------------------------------------
    const exe = b.addExecutable(.{
        .name             = "grimcore",
        .root_source_file = b.path("src/main.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    exe.root_module.addOptions("build_options", opts);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run Grim (native)");
    run_step.dependOn(&run_cmd.step);

    // -------------------------------------------------------------------------
    // Android shared library — cross-compiled for aarch64-linux-android
    // Usage: zig build android
    // Output: zig-out/lib/libgrim.so  (copy into your Android APK jni/arm64-v8a/)
    // -------------------------------------------------------------------------
    const android_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag   = .linux,
        .abi      = .android,
    });
    const android_lib = b.addSharedLibrary(.{
        .name             = "grim",
        .root_source_file = b.path("src/jni.zig"),
        .target           = android_target,
        .optimize         = .ReleaseSmall,
    });
    android_lib.root_module.addOptions("build_options", opts);
    const android_step = b.step("android", "Build libgrim.so for Android arm64");
    android_step.dependOn(&b.addInstallArtifact(android_lib, .{}).step);

    // -------------------------------------------------------------------------
    // Test suite
    // -------------------------------------------------------------------------
    const subsystems = [_]struct { name: []const u8, path: []const u8 }{
        .{ .name = "types",   .path = "src/types.zig"          },
        .{ .name = "math",    .path = "src/math.zig"           },
        .{ .name = "wallet",  .path = "src/wallet/lightning.zig" },
        .{ .name = "store",   .path = "src/store/filestore.zig"  },
    };

    const test_all = b.step("test", "Run all Grim subsystem tests");
    inline for (subsystems) |sys| {
        const t = b.addTest(.{
            .name             = sys.name,
            .root_source_file = b.path(sys.path),
            .target           = target,
            .optimize         = optimize,
        });
        t.root_module.addOptions("build_options", opts);
        const run_t = b.addRunArtifact(t);
        test_all.dependOn(&run_t.step);
        const single = b.step(
            b.fmt("test-{s}", .{sys.name}),
            b.fmt("Test src/{s}", .{sys.name}),
        );
        single.dependOn(&run_t.step);
    }
}
