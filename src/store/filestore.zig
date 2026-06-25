//! store/filestore.zig — Grim flat-file storage layer
//! All persistence uses plain files and JSONL — no SQLite, no external DB.
//! Root path: GRIM_DATA_PATH env var (default: ./data on desktop,
//!             /data/data/app.grim.wallet/files on Android)
//!
//! Layout:
//!   {data_path}/
//!     entities/{hash}.json     — content-addressed entity blobs
//!     audit/audit_log.jsonl    — append-only audit chain
//!     wallet/fee_log.jsonl     — Lightning fee accounting
//!     wallet/invoices.jsonl    — invoice records
//!     wallet/payments.jsonl    — payment records
//!     vault/{key}.enc          — AES-256-GCM encrypted vault entries

const std = @import("std");

pub const FileStore = struct {
    allocator: std.mem.Allocator,
    root:      []const u8,
    mock_mode: bool,
    mock_data: std.StringHashMap([]u8),

    /// Init backed by real filesystem.
    pub fn init(allocator: std.mem.Allocator, root: []const u8) !FileStore {
        // Ensure subdirectories exist
        const subdirs = [_][]const u8{
            "entities", "audit", "wallet", "vault",
        };
        inline for (subdirs) |sub| {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, sub });
            defer allocator.free(path);
            std.fs.makeDirAbsolute(path) catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => return e,
            };
        }
        return FileStore{
            .allocator = allocator,
            .root      = root,
            .mock_mode = false,
            .mock_data = std.StringHashMap([]u8).init(allocator),
        };
    }

    /// Init with in-memory mock (for tests — mirrors handleFileIOMock in Unison).
    pub fn initMock() FileStore {
        return FileStore{
            .allocator = std.testing.allocator,
            .root      = "/mock",
            .mock_mode = true,
            .mock_data = std.StringHashMap([]u8).init(std.testing.allocator),
        };
    }

    pub fn deinit(self: *FileStore) void {
        if (self.mock_mode) {
            var it = self.mock_data.iterator();
            while (it.next()) |entry| self.allocator.free(entry.value_ptr.*);
            self.mock_data.deinit();
        }
    }

    /// Write a file (creates or overwrites).
    pub fn writeFile(self: *FileStore, rel_path: []const u8, data: []const u8) !void {
        if (self.mock_mode) {
            const copy = try self.allocator.dupe(u8, data);
            try self.mock_data.put(rel_path, copy);
            return;
        }
        const full = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.root, rel_path });
        defer self.allocator.free(full);
        const f = try std.fs.createFileAbsolute(full, .{ .truncate = true });
        defer f.close();
        try f.writeAll(data);
    }

    /// Read a file — caller owns the returned slice.
    pub fn readFile(self: *FileStore, rel_path: []const u8) !?[]u8 {
        if (self.mock_mode) {
            if (self.mock_data.get(rel_path)) |v| {
                return try self.allocator.dupe(u8, v);
            }
            return null;
        }
        const full = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.root, rel_path });
        defer self.allocator.free(full);
        const f = std.fs.openFileAbsolute(full, .{}) catch |e| switch (e) {
            error.FileNotFound => return null,
            else => return e,
        };
        defer f.close();
        return try f.readToEndAlloc(self.allocator, 8 * 1024 * 1024);
    }

    /// Append a line to a JSONL file.
    pub fn appendLine(self: *FileStore, rel_path: []const u8, line: []const u8) !void {
        if (self.mock_mode) {
            const existing = self.mock_data.get(rel_path) orelse "";
            const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}\n", .{ existing, line });
            try self.mock_data.put(rel_path, combined);
            return;
        }
        const full = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.root, rel_path });
        defer self.allocator.free(full);
        const f = try std.fs.openFileAbsolute(full, .{ .mode = .write_only });
        defer f.close();
        try f.seekFromEnd(0);
        try f.writeAll(line);
        try f.writeAll("\n");
    }

    /// Check if a file exists.
    pub fn fileExists(self: *FileStore, rel_path: []const u8) bool {
        if (self.mock_mode) return self.mock_data.contains(rel_path);
        const full = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.root, rel_path })
            catch return false;
        defer self.allocator.free(full);
        std.fs.accessAbsolute(full, .{}) catch return false;
        return true;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "mock write and read roundtrip" {
    var fs = FileStore.initMock();
    defer fs.deinit();
    try fs.writeFile("wallet/test.json", "{\"hello\":\"world\"}");
    const result = try fs.readFile("wallet/test.json");
    try testing.expect(result != null);
    defer testing.allocator.free(result.?);
    try testing.expectEqualStrings("{\"hello\":\"world\"}", result.?);
}

test "mock fileExists returns false for missing key" {
    var fs = FileStore.initMock();
    defer fs.deinit();
    try testing.expect(!fs.fileExists("wallet/missing.json"));
}
