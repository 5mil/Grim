# Grim Session Log

---

## Session: 2026-06-19 (continued)

### Grim.Handlers.Local — COMPLETE

File: `Grim/Handlers/Local.u`  
Commit: `9879199d5000f8f8ea9768c0b8d9cae15bb1b181`

| Handler | Strategy |
|---|---|
| `handleMining` | Stratum V1 TCP shim via HTTP relay. Shim (Node.js/Go) speaks raw Stratum, normalises Share/Block into JSON, POSTs to Grim's local HTTP listener. All mining logic stays in Grim. FFI stubs: `grimShimReceive*`, `grimShimGetHashrate`, etc. |
| `handleAuth` | Local Ed25519 keypair for cert login. scrypt for password hashing. HS256 JWT for session tokens. User store in local SQLite. FFI stubs: `localAuthLogin`, `localAuthProvisionCert`, `localAuthIssueToken`, etc. |
| `handleKnowledge` | SQLite via FFI. Each entity stored as JSON row `(hash, entity_type, value JSON, facts JSON, previous_hash, timestamp, author)`. Content hash computed from all fields. FFI stubs: `sqliteStoreEntity`, `sqliteGetEntity`, `sqliteEntityHistory`, etc. |
| `handleVault` | AES-256-GCM local encrypted store via FFI. Master key derived via scrypt KDF. Each VaultEntry carries `previousHash` for provenance chain. Path: `$GRIM_VAULT_PATH`. FFI stubs: `localVaultStore`, `localVaultGet`, `localVaultRotate`, etc. |
| `handleReputation` | Local flat-file JSONL score ledger at `$GRIM_DATA_PATH/reputation.jsonl`. `syncRole`/`syncTier` call `reputationToRole`/`tierFromReputation` (pure Math), then update SQLite Auth store. FFI stubs: `localRepGetScore`, `localRepApplyDelta`, etc. |
| `handleGovernance` | Local config-file store at `$GRIM_DATA_PATH/governance.json`. Mode changes written atomically (write-then-rename). FFI stubs: `localGovGetMode`, `localGovSetMode`, `localGovCheckAccess`, `localGovGetHistory`. |
| `handleAudit` | Append-only JSONL chain at `$GRIM_DATA_PATH/audit.jsonl`. Each entry hashes its predecessor for tamper-evidence. `verifyChain` walks the full file. FFI stubs: `localAuditAppend`, `localAuditRecent`, `localAuditVerifyChain`, etc. |
| `handleStream` | WebSocket broadcast server on `$GRIM_STREAM_PORT` (default 3334). MagoFonte stream module model. Events serialised as `{ type, payload, timestamp }` JSON. All subscribers receive all events; filtering is client-side. FFI stub: `wsEmit`. |
| `handleCrypto` | AES-256-GCM + scrypt + Ed25519 via platform FFI. Used by Vault and Auth. Cloud handler substitutes Unison Cloud KMS. FFI stubs: `aesGcmEncrypt`, `aesGcmDecrypt`, `scryptDeriveKey`, `platformRandomBytes`. |

#### `runLocal` — Handler Composition
```
runLocal : '{Mining, Auth, Knowledge, Vault, Reputation, Governance, Audit, Stream, Crypto} r -> r
```
Stacks all nine handlers in a single call. The UCM entry point calls `runLocal do proofLoop` and the self-hosted Grim is fully operational. No ability is left unhandled.

#### Design Notes
- Every handler is a pure Unison function — the FFI boundary is declared via stubs, not inline native code
- The Stratum TCP shim is the **only** process with a TCP socket; Grim never owns a raw socket
- SQLite is shared between `handleKnowledge` and `handleAuth` (same DB file, separate tables)
- `handleReputation.syncRole` calls `localAuthSetRole` directly — the only cross-handler call; this is intentional and documented
- Audit entries are written **after** every effect in Pool, Knowledge, Governance, and Vault — nothing mutates state silently

---

### Current Module Status

| Module | Status |
|---|---|
| Grim.Types | ✅ Complete |
| Grim.Math | ✅ Complete |
| Grim.Abilities | ✅ Complete |
| Grim.Vault | ✅ Complete |
| Grim.Pool | ✅ Complete |
| Grim.Knowledge | ✅ Complete |
| Grim.Governance | ✅ Complete |
| Grim.Handlers.Local | ✅ Complete |
| Grim.Handlers.Cloud | 📋 Next |

---

### Open Design Questions

1. **Stratum TCP shim language** — Node.js (mirrors MagoFonte codebase) vs Go (lighter binary). Decision needed before shim implementation.
2. **Browser cert flow** — confirmed: thin vanilla JS shell calling Grim HTTP endpoints.
3. **NocoBase frontend** — decision pending: retain as read layer or replace.
4. **SQLite FFI library** — which Unison FFI wrapper to use for SQLite (community package vs custom).

---

### Next Steps
- [ ] Write Grim.Handlers.Cloud — Unison Cloud / Lancia handler implementations
- [ ] Decide Stratum TCP shim language (Node.js vs Go)
- [ ] Confirm NocoBase frontend decision
- [ ] Confirm SQLite FFI library choice

---

## Session: 2026-06-19 (Grim.Knowledge + Grim.Governance)

### Grim.Knowledge — COMPLETE
File: `Grim/Knowledge.u` | Commit: `f6282113`
- `knowledgeStore`, `knowledgeUpdate`, `knowledgeGet`, `knowledgeHistory`
- `knowledgeAddFact`, `knowledgeGetFacts`
- `knowledgeListCoins/Blocks/Miners/Articles/GovernanceRecords`
- `verifyEntityChain` — walks and validates full revision chain
- `syncCoinToKnowledge`, `storeBlockEntity`

### Grim.Governance — COMPLETE
File: `Grim/Governance.u` | Commit: `f6282113`
- `guardedAction` — single replacement for all of grimoire Loop 3
- `transitionMode`, `reputationSync`, `governanceHistory`, `canAct`
- `verifyGovernanceAudit`, `GovernanceRecord` type

---

## Session: 2026-06-19 (Grim.Pool)

### Grim.Pool — COMPLETE
File: `Grim/GrimPool.u` | Commit: `3501c9e5`
- `proofLoop`, `blockLoop`, `computePayouts`, `applyPayouts`
- `adjustDifficulty`, `poolSummary`
- `registerCoinGuarded`, `startNodeGuarded`, `stopNodeGuarded`, `nodeMonitorLoop`

---

## Session: 2026-06-19 (initial)

### Core Finding
Grim is the system. MagoFonte, Lancia, and dir are not separate products — they are conceptual layers within a single Unison program. The deployment profile (self-hosted vs. cloud) is determined by which ability handlers are provided at runtime.
