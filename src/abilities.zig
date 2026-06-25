//! abilities.zig — Grim interface vtables
//! Port of Grim/Abilities.u
//! Each ability becomes a comptime-injectable vtable struct.
//! Pass as parameters — never use global state.

const std   = @import("std");
const types = @import("types.zig");

// ---------------------------------------------------------------------------
// FileIO — storage effect surface
// ---------------------------------------------------------------------------

pub const FileIO = struct {
    readFile:   *const fn (path: []const u8, allocator: std.mem.Allocator) anyerror!?[]u8,
    writeFile:  *const fn (path: []const u8, data: []const u8) anyerror!void,
    appendLine: *const fn (path: []const u8, line: []const u8) anyerror!void,
    listDir:    *const fn (path: []const u8, allocator: std.mem.Allocator) anyerror![][]u8,
    fileExists: *const fn (path: []const u8) anyerror!bool,
    deleteFile: *const fn (path: []const u8) anyerror!void,
    now:        *const fn () u64,
    sha3_256:   *const fn (input: []const u8, allocator: std.mem.Allocator) anyerror![]u8,
};

// ---------------------------------------------------------------------------
// Mining
// ---------------------------------------------------------------------------

pub const Mining = struct {
    receiveShare:       *const fn () anyerror!types.Share,
    receiveBlock:       *const fn () anyerror!types.Block,
    getCurrentHashrate: *const fn () u64,
    getSessions:        *const fn (allocator: std.mem.Allocator) anyerror![]types.MinerSession,
    registerCoin:       *const fn (coin: types.CoinDef) anyerror!void,
    nodeStatus:         *const fn (ticker: []const u8) anyerror!types.NodeStatus,
    startNode:          *const fn (ticker: []const u8) anyerror!void,
    stopNode:           *const fn (ticker: []const u8) anyerror!void,
};

// ---------------------------------------------------------------------------
// Reputation
// ---------------------------------------------------------------------------

pub const Reputation = struct {
    getScore:   *const fn (user_id: []const u8) anyerror!u64,
    applyDelta: *const fn (user_id: []const u8, delta: i64) anyerror!void,
    getHistory: *const fn (user_id: []const u8, allocator: std.mem.Allocator) anyerror![]u64,
    syncRole:   *const fn (user_id: []const u8) anyerror!types.Role,
    syncTier:   *const fn (user_id: []const u8) anyerror!types.Tier,
};

// ---------------------------------------------------------------------------
// Governance
// ---------------------------------------------------------------------------

pub const Governance = struct {
    currentMode:    *const fn () anyerror!types.GovernanceMode,
    setMode:        *const fn (mode: types.GovernanceMode) anyerror!void,
    checkAccess:    *const fn (user_id: []const u8, action: types.Action) anyerror!bool,
};

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

pub const Auth = struct {
    currentUser:  *const fn () anyerror!types.User,
    requireRole:  *const fn (role: types.Role) anyerror!void,
    login:        *const fn (username: []const u8, password: []const u8) anyerror!types.User,
    issueToken:   *const fn (user: types.User, allocator: std.mem.Allocator) anyerror![]u8,
    revokeToken:  *const fn (jti: []const u8) anyerror!void,
    listUsers:    *const fn (allocator: std.mem.Allocator) anyerror![]types.User,
    createUser:   *const fn (username: []const u8, password: []const u8, role: types.Role) anyerror!types.User,
    setRole:      *const fn (user_id: []const u8, role: types.Role) anyerror!void,
    deleteUser:   *const fn (user_id: []const u8) anyerror!void,
};

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

pub const Audit = struct {
    record:      *const fn (actor: []const u8, event: []const u8) anyerror!void,
    recent:      *const fn (n: u64, allocator: std.mem.Allocator) anyerror![]types.AuditEntry,
    forActor:    *const fn (actor: []const u8, allocator: std.mem.Allocator) anyerror![]types.AuditEntry,
    verifyChain: *const fn () anyerror!bool,
};

// ---------------------------------------------------------------------------
// Vault
// ---------------------------------------------------------------------------

pub const Vault = struct {
    storeSecret:       *const fn (key: []const u8, data: []const u8) anyerror!void,
    getSecret:         *const fn (key: []const u8, allocator: std.mem.Allocator) anyerror!?[]u8,
    listSecrets:       *const fn (allocator: std.mem.Allocator) anyerror![][]const u8,
    rotateSecret:      *const fn (key: []const u8, data: []const u8) anyerror!void,
    deleteSecret:      *const fn (key: []const u8) anyerror!void,
    storeMiningCreds:  *const fn (ticker: []const u8, user: []const u8, pass: []const u8) anyerror!void,
};

// ---------------------------------------------------------------------------
// Lightning — new ability (wallet + fee-earning node service)
// ---------------------------------------------------------------------------

pub const Lightning = struct {
    /// Create a BOLT11 invoice for the given amount.
    createInvoice:  *const fn (amount_msats: u64, description: []const u8, expiry_secs: u32, allocator: std.mem.Allocator) anyerror!types.Invoice,
    /// Pay a BOLT11 invoice string.
    payInvoice:     *const fn (payment_request: []const u8, allocator: std.mem.Allocator) anyerror!types.Payment,
    /// List all local channels.
    listChannels:   *const fn (allocator: std.mem.Allocator) anyerror![]types.Channel,
    /// Get accumulated fee statistics.
    feeStats:       *const fn () types.FeeStats,
    /// Open a channel to a remote peer (pubkey@host:port).
    openChannel:    *const fn (peer: []const u8, amount_sats: u64) anyerror!void,
    /// Close a channel by channel_id.
    closeChannel:   *const fn (channel_id: []const u8) anyerror!void,
    /// Update the fee policy for all channels.
    setFeePolicy:   *const fn (base_fee_msats: u32, fee_rate_ppm: u32) anyerror!void,
};
