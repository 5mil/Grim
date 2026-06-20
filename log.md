# Grim Session Log

---

## Session: 2026-06-19 (continued)

### Grim.Knowledge — COMPLETE

File: `Grim/Knowledge.u`
Commit: `f6282113b4d8cc983a9fcc728d2233791aacf974`

| Function | Description |
|---|---|
| `knowledgeStore` | Guarded write — Forge tier minimum, stores value as content-addressed entity, audit-logged |
| `knowledgeUpdate` | Guarded revision — creates new entity linked to previous hash, audit-logged |
| `knowledgeGet` | Open read — retrieves entity by content hash, access audit-logged |
| `knowledgeHistory` | Full revision chain for an entity hash, oldest to newest |
| `knowledgeAddFact` | Forge tier — attaches a credibility-scored Fact claim to an entity |
| `knowledgeGetFacts` | Open read — returns all facts on an entity |
| `knowledgeListCoins` | All CoinEntity entities — canonical coin config source |
| `knowledgeListBlocks` | All BlockRecord entities |
| `knowledgeListMiners` | All MinerProfile entities |
| `knowledgeListArticles` | All KnowledgeArticle entities |
| `knowledgeListGovernanceRecords` | All GovernanceRecord entities |
| `verifyEntityChain` | Walks full revision chain and verifies every `previous` hash link |
| `syncCoinToKnowledge` | Called by Pool on coin register/update — upserts CoinDef as Knowledge entity |
| `storeBlockEntity` | Called by Pool.blockLoop — stores Block as provenance-chained entity |
| `entityTypeToText` | Utility — EntityType → Text for audit metadata |

---

### Grim.Governance — COMPLETE

File: `Grim/Governance.u`
Commit: `f6282113b4d8cc983a9fcc728d2233791aacf974`

| Function | Description |
|---|---|
| `guardedAction` | Primary access gate — wraps `canPerformAction` (pure) with Auth/Audit, aborts on deny |
| `transitionMode` | Auth-gated mode switch — validates with `canTransitionMode`, persists to Knowledge, broadcasts, audits |
| `reputationSync` | Collapses grimoire Loop 3 — recalculates role/tier from score, broadcasts rep change |
| `governanceHistory` | Returns all GovernanceRecord entities from Knowledge store |
| `canAct` | Soft access check — returns Bool, used by dashboard/UI layers |
| `verifyGovernanceAudit` | Admin-gated — verifies full audit chain integrity |
| `GovernanceRecord` type | Stored on every mode transition — replaces dir plugin-dir-governance records |
| `modeToText`, `actionToText`, `roleToText`, `tierToText` | Text utilities for audit metadata and streaming |

#### Design Notes
- `canPerformAction` and `canTransitionMode` remain in `Grim.Math` — pure, zero effects
- `guardedAction` is the single replacement for all of grimoire’s Loop 3 governance bridge logic
- `GovernanceRecord` entities form a provenance-chained ledger inside the Knowledge store
- `reputationSync` is called after every reputation delta — no polling, no grimoire sidecar

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
| Grim.Handlers.Local | 📋 Next |
| Grim.Handlers.Cloud | 📋 Planned |

---

### Open Design Questions

1. **Stratum TCP shim** — thin native shim speaking Stratum V1 TCP, calling into Grim via HTTP. Design not yet written.
2. **Browser cert flow** — confirmed: thin vanilla JS shell calling Grim HTTP endpoints.
3. **NocoBase frontend** — decision pending: retain as read layer or replace.

---

### Next Steps
- [ ] Write Grim.Handlers.Local — UCM self-hosted handler implementations
- [ ] Write Grim.Handlers.Cloud — Unison Cloud / Lancia handler implementations
- [ ] Design Stratum TCP shim
- [ ] Confirm NocoBase frontend decision

---

## Session: 2026-06-19 (Grim.Pool)

### Grim.Pool — COMPLETE

File: `Grim/GrimPool.u`  
Commit: `3501c9e5077288aad82ec00fffe3b794db43cd6e`

| Function | Description |
|---|---|
| `proofLoop` | Hot path — receives shares, applies `miningDelta`, records to Audit, broadcasts to Stream |
| `blockLoop` | Concurrent — receives found blocks, applies `blockDelta`, stores block as Knowledge entity, triggers payout |
| `computePayouts` | Pure PPLNS — splits block reward proportionally using `Math.pplns` |
| `applyPayouts` | Audit-logs every payment issued |
| `adjustDifficulty` | Per-miner VarDiff using `Math.vardiff` and `targetShareInterval = 15s` |
| `poolSummary` | Live snapshot of active sessions, total hashrate, active coins |
| `registerCoinGuarded` | Register a new coin — Operator role required, audit-logged |
| `startNodeGuarded` / `stopNodeGuarded` | Node control — Admin role required, audit-logged |
| `nodeMonitorLoop` | Per-coin continuous loop — detects NodeStatus changes, streams and audits |

---

## Session: 2026-06-19 (initial)

### Core Finding
Grim is the system. MagoFonte, Lancia, and dir are not separate products — they are conceptual layers within a single Unison program. The deployment profile (self-hosted vs. cloud) is determined by which ability handlers are provided at runtime.
