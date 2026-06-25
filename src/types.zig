//! types.zig — Grim unified type system
//! Direct port of Grim/Types.u
//! Zero I/O, zero allocations — pure comptime-safe definitions.

// ---------------------------------------------------------------------------
// IDENTITY & ACCESS
// ---------------------------------------------------------------------------

pub const Role = enum {
    Banned,
    Member,
    Operator,
    Admin,
    Owner,
};

pub const Tier = enum {
    Hearth,
    Forge,
    Foundry,
    Citadel,
};

pub const User = struct {
    id:         []const u8,
    username:   []const u8,
    role:       Role,
    tier:       Tier,
    reputation: u64,
    created_at: u64,

    pub fn validate(self: User) bool {
        return self.reputation <= 100
            and self.id.len > 0
            and self.username.len > 0;
    }
};

// ---------------------------------------------------------------------------
// GOVERNANCE
// ---------------------------------------------------------------------------

pub const GovernanceMode = enum { Solo, Board, Open };

pub const Action = enum {
    View,
    Edit,
    Approve,
    Delete,
    ManageUsers,
    LaunchCoin,
    ManageVault,
    ProvisionCert,
    ManageNodes,
};

// ---------------------------------------------------------------------------
// MINING  (MagoFonte core)
// ---------------------------------------------------------------------------

pub const Algorithm = enum { Skein, Scrypt, SHA256d, Qubit, OdoCrypt };

pub const PoolMode = union(enum) {
    InternalPool: void,
    ExternalPool: []const u8,  // "host:port"
};

pub const CoinDef = struct {
    name:         []const u8,
    ticker:       []const u8,
    algorithm:    Algorithm,
    rpc_port:     u16,
    stratum_port: u16,
    diff:         u64,
    reward:       u64,
    pool_mode:    PoolMode,
};

pub const Share = struct {
    miner_id:   []const u8,
    coin:       []const u8,
    difficulty: u64,
    timestamp:  u64,
};

pub const Block = struct {
    height:    u64,
    hash:      []const u8,
    reward:    u64,
    finder:    []const u8,
    coin:      []const u8,
    timestamp: u64,
};

pub const NodeStatus = union(enum) {
    Running:  void,
    Stopped:  void,
    Syncing:  void,
    Error:    []const u8,
};

pub const MinerSession = struct {
    miner_id:  []const u8,
    connected: u64,
    hashrate:  u64,
    shares:    u64,
};

// ---------------------------------------------------------------------------
// KNOWLEDGE  (dir core)
// ---------------------------------------------------------------------------

pub const EntityType = enum {
    KnowledgeArticle,
    CoinEntity,
    BlockRecord,
    MinerProfile,
    GovernanceRecord,
};

pub const Fact = struct {
    claim:       []const u8,
    source:      []const u8,
    credibility: u64,
};

// ---------------------------------------------------------------------------
// VAULT  (Lancia + MagoFonte operator-owned)
// ---------------------------------------------------------------------------

pub const VaultEntry = struct {
    key:             []const u8,
    encrypted_value: []const u8,
    owner:           []const u8,
    timestamp:       u64,
    previous_hash:   ?[]const u8,
};

// ---------------------------------------------------------------------------
// AUTH  (Lancia ward)
// ---------------------------------------------------------------------------

pub const TokenClaims = struct {
    sub:      []const u8,
    username: []const u8,
    role:     Role,
    tier:     Tier,
    exp:      u64,
    jti:      []const u8,
};

pub const AuthError = error {
    NotAuthenticated,
    InsufficientRole,
    InsufficientTier,
    TokenExpired,
    InvalidSignature,
    ScopeNotPermitted,
};

// ---------------------------------------------------------------------------
// AUDIT
// ---------------------------------------------------------------------------

pub const AuditEntry = struct {
    hash:      []const u8,
    previous:  ?[]const u8,
    event:     []const u8,
    actor:     []const u8,
    timestamp: u64,
};

// ---------------------------------------------------------------------------
// DEPLOYMENT
// ---------------------------------------------------------------------------

pub const DeploymentProfile = enum { LocalSelfHosted, LanciaCloud };

pub const GrimConfig = struct {
    profile:         DeploymentProfile,
    instance_id:     []const u8,
    governance_mode: GovernanceMode,
    default_tier:    Tier,
};

// ---------------------------------------------------------------------------
// LIGHTNING WALLET  (new module — Android fee-earning wallet)
// ---------------------------------------------------------------------------

/// A Lightning invoice to be paid by a remote peer.
pub const Invoice = struct {
    payment_hash:    []const u8,  // hex-encoded 32 bytes
    payment_request: []const u8,  // BOLT11 string
    amount_msats:    u64,
    description:     []const u8,
    created_at:      u64,
    expiry_secs:     u32,
    settled:         bool,
};

/// A completed Lightning payment (outbound).
pub const Payment = struct {
    payment_hash:  []const u8,
    amount_msats:  u64,
    fee_msats:     u64,
    destination:   []const u8,
    timestamp:     u64,
    status:        PaymentStatus,
};

pub const PaymentStatus = enum { Pending, Succeeded, Failed };

/// Accumulated fee statistics for the node service.
pub const FeeStats = struct {
    earned_msats:    u64,  // total routing + service fees collected
    forwarded_count: u64,  // number of HTLCs forwarded
    channel_count:   u32,
};

/// A Lightning channel record.
pub const Channel = struct {
    channel_id:       []const u8,
    peer_pubkey:      []const u8,
    capacity_sats:    u64,
    local_msats:      u64,
    remote_msats:     u64,
    is_active:        bool,
    fee_rate_ppm:     u32,  // parts-per-million outbound fee rate
    base_fee_msats:   u32,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "User.validate rejects empty id" {
    const u = User{ .id = "", .username = "alice", .role = .Member,
        .tier = .Hearth, .reputation = 50, .created_at = 0 };
    try testing.expect(!u.validate());
}

test "User.validate rejects reputation > 100" {
    const u = User{ .id = "abc", .username = "alice", .role = .Member,
        .tier = .Hearth, .reputation = 101, .created_at = 0 };
    try testing.expect(!u.validate());
}

test "User.validate passes valid user" {
    const u = User{ .id = "abc", .username = "alice", .role = .Member,
        .tier = .Hearth, .reputation = 80, .created_at = 0 };
    try testing.expect(u.validate());
}
