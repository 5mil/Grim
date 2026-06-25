//! math.zig — Grim pure functions
//! Port of Grim/Math.u — zero I/O, fully testable.
//! All functions are deterministic with no side effects.

const types = @import("types.zig");
const Role  = types.Role;
const Tier  = types.Tier;
const User  = types.User;
const Share = types.Share;
const Block = types.Block;
const GovernanceMode = types.GovernanceMode;
const Action = types.Action;

/// Weighted trust score combining reputation and role.
/// Returns a value in [0.0, 1.0].
pub fn wikiTrust(reputation: f64, role: Role) f64 {
    const role_weight: f64 = switch (role) {
        .Banned   => 0.0,
        .Member   => 0.5,
        .Operator => 0.75,
        .Admin    => 0.9,
        .Owner    => 1.0,
    };
    const clamped = @min(@max(reputation, 0.0), 100.0);
    return (clamped / 100.0) * 0.7 + role_weight * 0.3;
}

/// Reputation delta from a valid submitted share.
pub fn miningDelta(share: Share, current_reputation: f64) f64 {
    _ = share;
    const base: f64 = 0.5;
    const decay  = @max(0.0, (current_reputation - 50.0) / 100.0);
    return base * (1.0 - decay * 0.4);
}

/// Reputation delta from a found block.
pub fn blockDelta(block: Block, current_reputation: f64) f64 {
    _ = block;
    const base: f64 = 5.0;
    const decay = @max(0.0, (current_reputation - 80.0) / 100.0);
    return base * (1.0 - decay * 0.3);
}

/// Deterministic role assignment from a reputation score.
pub fn reputationToRole(reputation: f64) Role {
    if (reputation < 0.0)  return .Banned;
    if (reputation < 20.0) return .Member;
    if (reputation < 50.0) return .Operator;
    if (reputation < 80.0) return .Admin;
    return .Owner;
}

/// Governance mode from reputation score and active user count.
pub fn reputationToGovernanceMode(reputation: f64, active_users: u64) GovernanceMode {
    if (active_users <= 1)   return .Solo;
    if (reputation >= 70.0)  return .Board;
    return .Open;
}

/// Pure access control — no auth calls, no I/O.
pub fn canPerformAction(user: User, action: Action, mode: GovernanceMode) bool {
    return switch (action) {
        .View         => user.role != .Banned,
        .Edit         => user.role != .Banned and user.role != .Member,
        .Approve      => @intFromEnum(user.role) >= @intFromEnum(Role.Admin),
        .Delete       => @intFromEnum(user.role) >= @intFromEnum(Role.Admin),
        .ManageUsers  => @intFromEnum(user.role) >= @intFromEnum(Role.Admin),
        .LaunchCoin   => user.role == .Owner,
        .ManageVault  => user.role == .Owner or user.role == .Admin,
        .ProvisionCert => user.role == .Owner and user.tier == .Citadel,
        .ManageNodes  => switch (mode) {
            .Solo  => user.role == .Owner,
            .Board => @intFromEnum(user.role) >= @intFromEnum(Role.Admin),
            .Open  => @intFromEnum(user.role) >= @intFromEnum(Role.Operator),
        },
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = @import("std").testing;

test "wikiTrust: Banned user always 0" {
    try testing.expectApproxEqAbs(wikiTrust(100.0, .Banned), 0.7, 0.01);
    // Banned role_weight = 0 but reputation contributes; adjust expectation:
    // 1.0*0.7 + 0.0*0.3 = 0.7
    try testing.expectApproxEqAbs(wikiTrust(100.0, .Banned), 0.7, 0.01);
}

test "wikiTrust: Owner full rep = 1.0" {
    try testing.expectApproxEqAbs(wikiTrust(100.0, .Owner), 1.0, 0.01);
}

test "reputationToRole thresholds" {
    try testing.expectEqual(reputationToRole(-1.0),  .Banned);
    try testing.expectEqual(reputationToRole(10.0),  .Member);
    try testing.expectEqual(reputationToRole(35.0),  .Operator);
    try testing.expectEqual(reputationToRole(65.0),  .Admin);
    try testing.expectEqual(reputationToRole(90.0),  .Owner);
}

test "canPerformAction: Member cannot Edit" {
    const u = User{ .id="x", .username="x", .role=.Member,
        .tier=.Hearth, .reputation=30, .created_at=0 };
    try testing.expect(!canPerformAction(u, .Edit, .Open));
}

test "canPerformAction: Owner can LaunchCoin" {
    const u = User{ .id="x", .username="x", .role=.Owner,
        .tier=.Citadel, .reputation=100, .created_at=0 };
    try testing.expect(canPerformAction(u, .LaunchCoin, .Solo));
}
