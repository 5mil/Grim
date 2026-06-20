# Grim Session Log

---

## Session: 2026-06-19 (continued)

### Grim.Shim.Stratum — COMPLETE

File: `Grim/Shim/Stratum.u`  
Commit: `83a64a1232ee0ec0a5db442c96623ede78965c09`

**Decision:** Stratum TCP shim written in Unison. No Node.js. No Go. One codebase.

#### Architecture

```
[Miner clients]
    | TCP / Stratum V1 JSON-RPC
    v
shimAcceptLoop          ← Unison TCP server (StratumSocket ability)
    |
stratumParseMessage     ← pure parser, zero I/O, zero effects
    |
stratumDispatch         ← pure router, returns (session, response, Optional Share)
    |              |
shimConnectionLoop   shimNodeMonitor  ← per-coin block detector
    |                   |
ShimQueues.pushShare    ShimQueues.pushBlock
    |                   |
grimShimReceiveShare    grimShimReceiveBlock  ← called by Local.u handleMining
    |
Grim.Pool.proofLoop / blockLoop
```

#### Components

| Component | Type | Description |
|---|---|---|
| `StratumMethod` / `StratumMessage` / `StratumResponse` | Types | Minimal Stratum V1 JSON-RPC representation |
| `ShimSession` | Type | Per-connection state: sessionId, minerId, coin, difficulty, extraNonce1/2, authorised |
| `stratumParseMessage` | Pure | Text → Either StratumError StratumMessage. Zero I/O. |
| `stratumSerialise` | Pure | StratumResponse → JSON Text. Zero I/O. |
| `stratumDispatch` | Pure | Routes message → (ShimSession, Optional response, Optional Share). Zero I/O. |
| `extractShare` | Pure | Extracts Grim Share from mining.submit params |
| `difficultyNotify` | Pure | Produces mining.set_difficulty JSON push |
| `jobNotify` | Pure | Produces mining.notify JSON push from JobTemplate |
| `shimConnectionLoop` | `'{StratumSocket}` | Handles one TCP connection from subscribe to disconnect |
| `shimAcceptLoop` | `'{StratumSocket}` | Top-level accept loop, spawns connection handlers |
| `StratumSocket` ability | Ability | Owns TCP I/O, queue writes, clock, UUID — swappable for tests |
| `handleStratumSocket` | Handler | Production: real TCP via FFI (`tcpAccept`, `tcpReadLine`, etc.) |
| `handleStratumMock` | Handler | Tests: replays canned message sequences, no socket |
| `ShimQueues` ability | Ability | `dequeueShare`, `dequeueBlock`, `pushShare`, `pushBlock` |
| `handleShimQueues` | Handler | In-memory Ref-based queue; spin-poll (UCM: replace with Scope.async) |
| `grimShimReceiveShare` | `'{ShimQueues}` | Called by `handleMining` in Local.u — resolves the FFI stub |
| `grimShimReceiveBlock` | `'{ShimQueues}` | Called by `handleMining` in Local.u |
| `ShimRegistry` ability | Ability | Tracks active ShimSessions for hashrate/session queries |
| `handleShimRegistry` | Handler | Ref-based session registry |
| `grimShimGetHashrate` | `'{ShimRegistry}` | Sums hashrate across all registered sessions |
| `grimShimGetSessions` | `'{ShimRegistry}` | Maps ShimSession → MinerSession for Mining ability |
| `shimNodeMonitor` | `'{ShimQueues, StratumSocket}` | Polls coin node RPC at 500ms, detects new blocks, enqueues Block |
| `runShim` | Composition | `handleShimRegistry(handleShimQueues(handleStratumSocket(shimAcceptLoop)))` |

#### Key Design Points
- **Pure core, ability boundary.** `stratumParseMessage`, `stratumSerialise`, and `stratumDispatch` are pure functions — no effects, fully testable without a socket.
- **`StratumSocket` is swappable.** `handleStratumMock` replays canned sequences. The production path and the test path run identical logic.
- **FFI stubs replaced.** The `grimShim*` stubs in `Local.u` are now resolved by the Unison queue API (`grimShimReceiveShare`, `grimShimReceiveBlock`) and the Unison registry (`grimShimGetHashrate`, `grimShimGetSessions`). The FFI boundary is pushed down to the TCP layer only (`tcpAccept`, `tcpReadLine`, etc.).
- **Block detection is in the shim.** `shimNodeMonitor` polls the coin node RPC at 500ms and pushes `Block` into `ShimQueues` — no separate block-watching process needed.
- **Concurrent entry point:** `main = do { fork do runShim defaultCoin; runLocal do proofLoop }`

#### Tests (8)
- `testStratumParseSubscribe` — parse mining.subscribe
- `testStratumParseAuthorize` — parse mining.authorize, extract username
- `testStratumParseSubmit` — parse mining.submit
- `testStratumSerialise` — serialise response to JSON
- `testExtractShare` — extract Share from submit params
- `testDifficultyNotify` — difficulty push JSON
- `testDispatchSubscribe` — dispatch Subscribe produces a response
- `testDispatchSubmitEnqueuesShare` — dispatch Submit extracts a Share

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
| Grim.Shim.Stratum | ✅ Complete |
| Grim.Handlers.Cloud | 📋 Next |

---

### Open Design Questions
1. **Browser cert flow** — confirmed: thin vanilla JS shell calling Grim HTTP endpoints.
2. **NocoBase frontend** — decision pending: retain as read layer or replace.
3. **SQLite FFI library** — which Unison FFI wrapper to use for SQLite.
4. **UCM concurrent queues** — `handleShimQueues` currently uses spin-poll on `Ref`. Replace with `Scope`/`Channel` in UCM when concurrent primitives are available.

---

### Next Steps
- [ ] Write Grim.Handlers.Cloud — Unison Cloud / Lancia handler implementations
- [ ] Confirm NocoBase frontend decision
- [ ] Confirm SQLite FFI library choice
- [ ] Replace ShimQueues spin-poll with UCM Channel/Scope primitives

---

## Previous Sessions (summary)

| Module | Commit |
|---|---|
| Grim.Knowledge + Grim.Governance | `f6282113` |
| Grim.Pool | `3501c9e5` |
| Grim.Handlers.Local | `9879199d` |

### Core Finding
Grim is the system. MagoFonte, Lancia, and dir are not separate products — they are conceptual layers within a single Unison program. The deployment profile (self-hosted vs. cloud) is determined by which ability handlers are provided at runtime.
