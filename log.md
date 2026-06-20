# Grim Session Log

---

## Session: 2026-06-19 (sidequest)

### unison-route-done — EXTRACTED AS STANDALONE LIBRARY

Repo: [github.com/5mil/unison-route-done](https://github.com/5mil/unison-route-done)  
License: MIT

A focused Unison library solving the "handler keeps executing past a respond" problem. Provides a `Route.Done` algebraic ability and a small set of response helpers and guard combinators. Zero dependency on Grim — designed to be usable in any Unison HTTP service.

#### Core API

| Symbol | Type | Description |
|---|---|---|
| `Route.Done` | `ability` | The short-circuit ability. `structural` keyword avoids hash-mismatch on upgrade. |
| `Route.handle` | `'{Route.Done, e} r ->{e} r` | Runner. Catches early exit, returns committed response. Only place `Route.Done` is consumed. |
| `Route.ok` | `Text ->{Route.Done} r` | 200 response, exits immediately |
| `Route.badRequest` | `Text ->{Route.Done} r` | 400, exits immediately |
| `Route.unauthorized` | `Text ->{Route.Done} r` | 401, exits immediately |
| `Route.forbidden` | `Text ->{Route.Done} r` | 403, exits immediately |
| `Route.notFound` | `Text ->{Route.Done} r` | 404, exits immediately |
| `Route.conflict` | `Text ->{Route.Done} r` | 409, exits immediately |
| `Route.serverError` | `Text ->{Route.Done} r` | 500, exits immediately |
| `Route.okJson` | `Text ->{Route.Done} r` | 200 + `Content-Type: application/json` |
| `Route.respond` | `Nat -> Text ->{Route.Done} r` | Raw status + body, exits immediately |
| `Route.guard.badRequest` | `Boolean -> Text ->{Route.Done} ()` | Exits 400 if true, returns `()` otherwise |
| `Route.guard.unauthorized` | `Boolean -> Text ->{Route.Done} ()` | Exits 401 if true |
| `Route.guard.forbidden` | `Boolean -> Text ->{Route.Done} ()` | Exits 403 if true |
| `Route.guard.notFound` | `Boolean -> Text ->{Route.Done} ()` | Exits 404 if true |
| `Route.guard.conflict` | `Boolean -> Text ->{Route.Done} ()` | Exits 409 if true |
| `Route.guard` | `Boolean -> Nat -> Text ->{Route.Done} ()` | Generic guard, any status |
| `Route.require` | `Optional a -> Text ->{Route.Done} a` | Unwrap or exit 400 |
| `Route.requireFound` | `Optional a -> Text ->{Route.Done} a` | Unwrap or exit 404 |

#### Key design decisions

- `structural` ability keyword — avoids hash-mismatch across library versions
- Continuation `_k` explicitly bound and discarded in `Route.handle` — correct Unison handler syntax
- Guards return `()` not `r` — makes sequential composition typecheck without `when` incompatibility
- `HttpResponse` defined in the library — self-contained, no external dependency
- `when` incompatibility documented throughout — use `Route.guard.*` instead
- Replaces nebulous `Abort` threading: `Abort` loses the response value on exit; `Route.Done` carries it typed

#### Examples included

- `examples/validation.u` — query param validation
- `examples/auth_gate.u` — token + role enforcement
- `examples/multi_step.u` — validate / persist / respond in sequence
- `examples/shared_helpers.u` — reusable helpers that own their own failure responses

#### Integration with Grim

The intended integration point is `Grim.Handlers.Local` and `Grim.Handlers.Cloud`. Each HTTP route handler wraps its body in `Route.handle do ...`. Every helper that may exit early carries `{Route.Done}` in its type row. `Route.handle` eliminates the ability at the dispatch boundary — the outer handler stack (`runLocal` / `runCloud`) does not need to know about it.

---

## Session: 2026-06-19 (continued)

### Grim.Handlers.Cloud — COMPLETE

File: [`Grim/Handlers/Cloud.u`](https://github.com/5mil/Grim/blob/main/Grim/Handlers/Cloud.u)  
Commit: `10b8d453f4d4d9fb2732a75df4e367f4b703c185`

Full Unison Cloud handler file. Every ability in `Grim.Abilities` is satisfied by a cloud handler. `runCloud` composition is structurally identical to `runLocal` — same 9-handler stack, same order, different implementations.

#### Handler Correspondence

| Ability | Local handler | Cloud handler | Key difference |
|---|---|---|---|
| Mining | `grimShim*` FFI (Stratum TCP) | `cloudPool*` HTTP gateway | Cloud gateway normalises Stratum; no local TCP |
| Auth | `localAuth*` + SQLite + local Ed25519 key | `cloudAuth*` + KMS JWT | Key material never leaves cloud HSM |
| Knowledge | `sqlite*` FFI (JSON rows) | `cloudKv*` entity store | Cloud KV owns replication and history |
| Vault | `localVault*` AES-256-GCM file | `cloudKmsVault*` KMS secrets | No local AES key, no local encrypted file |
| Reputation | `localRep*` flat-file JSONL | `cloudRep*` cloud KV | Consistent across nodes; no flat-file sync |
| Governance | `localGov*` config-file | `cloudGov*` cloud KV + event bus | `setMode` emits to all nodes immediately |
| Audit | `localAudit*` JSONL chain | `cloudAudit*` cloud service | `verifyChain` delegates to server-side walk |
| Stream | `wsEmit` WebSocket (single process) | `cloudEventEmit` event bus | Fanout across all cloud nodes |
| Crypto | `aesGcmEncrypt*` platform FFI | `cloudKms*` KMS API | No raw key in process memory |

#### Security upgrade: KMS boundary

In `Local.u`, key material lives briefly in process memory. In `Cloud.u` all key operations route through the cloud KMS. The Grim process never holds raw key material. This is the Lancia security model applied uniformly across all nine abilities.

#### Governance side effect

`handleGovernanceCloud.setMode` calls `cloudEventEmit "governance"` after persisting the new mode, propagating the change to all nodes via the event bus immediately.

---

### unison-filestore — EXTRACTED AS STANDALONE LIBRARY

Repo: [github.com/5mil/unison-filestore](https://github.com/5mil/unison-filestore)  
Version: `0.1.0`  
License: MIT

The `FileIO` ability and all entity/user store functions extracted as a standalone Unison library. Zero dependency on Grim types or abilities.

---

### Grim.Store.FileStore — COMPLETE

File: `Grim/Store/FileStore.u` | Commit: `d25b5d0e`

---

### Grim.Shim.Stratum — COMPLETE

File: `Grim/Shim/Stratum.u` | Commit: `83a64a12`

---

## Session: 2026-06-19 (hardware + routing)

### Per-coin shim routing + hardware mining — COMMIT `1128c0905a8e3f4f761aef0b1e8ae906f48015f2`

Files changed:
- [`Grim/Handlers/Local.u`](https://github.com/5mil/Grim/blob/main/Grim/Handlers/Local.u)
- [`Grim/Shim/Hardware.u`](https://github.com/5mil/Grim/blob/main/Grim/Shim/Hardware.u) _(new)_
- [`Grim/Types.u`](https://github.com/5mil/Grim/blob/main/Grim/Types.u)
- [`Grim/Main.u`](https://github.com/5mil/Grim/blob/main/Grim/Main.u) _(new)_

#### Local.u — Mining handler refactored

`handleMining` no longer calls `grimShim*` stubs directly. Those stubs were tightly coupled to the old single-shim model and blocked per-coin routing.

**Before:**
```
Mining.registerCoin coin -> resume ->
  grimShimRegisterCoin coin  -- opaque FFI call; mode-blind
  resume ()
```

**After:**
```
Mining.registerCoin coin -> resume ->
  platformFork do runShim coin  -- routes by coin.poolMode
  resume ()
```

`grimShimRegisterCoin`, `grimShimStartNode`, `grimShimStopNode` removed from handler. `localNodeStatus`, `localStartNode`, `localStopNode` FFI stubs replace them (daemon lifecycle only; shim lifecycle owned by `runShim`). `grimShimReceiveShare`, `grimShimReceiveBlock`, `grimShimGetHashrate`, `grimShimGetSessions` are retained as ShimQueues-backed re-exports so `handleMining` compiles without `ShimQueues` in its ability row.

#### Grim/Shim/Hardware.u — NEW MODULE

Physical hardware mining support. Three backends, all feed `ShimQueues`:

| Backend | Device | Protocol | PoW location |
|---|---|---|---|
| `FuryUSB` | GawMiner Fury (~1.3 MH/s Scrypt) | libusb HID | `nativeFindNonce` FFI (WorkerNonce ability) |
| `BitaxeHTTP` | Bitaxe ESP32 ASIC (~400-1000+ GH/s SHA256d) | HTTP REST `/api/system`, `/api/swarm` | On-device; Grim polls for completed shares |
| `GPUMiner` | AMD/NVIDIA GPU via CGMiner/BFGMiner | JSON-RPC port 4028 | On-device (OpenCL/CUDA); Grim manages pool config |

Key symbols:

| Symbol | Description |
|---|---|
| `HardwareBackend` | Sum type: `FuryUSB \| BitaxeHTTP \| GPUMiner` |
| `HardwareWorker` | Ability: `getWork`, `submitNonce`, `getHashrate`, `getTemperature`, `resetDevice` |
| `WorkerNonce` | Ability: `findNonce : JobTemplate -> Nat -> Optional Text` |
| `handleWorkerNonceSoftware` | WorkerNonce handler: calls `nativeFindNonce` FFI (C/Rust tight loop) |
| `handleWorkerNonceMock` | WorkerNonce handler: instant mock nonce (tests, Bitaxe, GPU) |
| `handleFuryWorker` | HardwareWorker handler: HID I/O via `furyPollJob`, `furySubmitNonce` |
| `handleBitaxeWorker` | HardwareWorker handler: HTTP polling via `bitaxePollJob`, `bitaxeGetHashrate` |
| `handleGPUWorker` | HardwareWorker handler: CGMiner JSON-RPC via `cgminerGetWork`, `cgminerGetHashrate` |
| `hardwareWorkerLoop` | Main loop: getWork → findNonce → submitNonce → enqueueShare → recurse |
| `runHardwareWorker` | Top-level composition: picks correct handler stack by backend type |
| `hardwareMonitorLoop` | Concurrent monitor: polls hashrate + temp every 30s, emits stream events |
| `cgminerAddPool` | FFI: add pool URL to CGMiner/BFGMiner instance |
| `cgminerRemovePool` | FFI: remove pool by ID |

#### WorkerNonce FFI boundary

`findNonce` in `WorkerNonce` is the PoW computation boundary. It is declared as an ability operation so it can be:
- Implemented as a tight C/Rust native loop in production (`handleWorkerNonceSoftware`)
- Mocked instantly in tests (`handleWorkerNonceMock`)
- Delegated to hardware (Bitaxe, GPU) where the device self-solves and `findNonce` is never the critical path

`stratumWorkerLoop` in `Stratum.u` now calls `findNonce` before `enqueueShare`:
```
Some nonce -> submitShare job.jobId nonce ; enqueueShare share
None       -> -- job stale; wait for next Notify
```

#### Grim/Types.u — GrimConfig updated

`GrimConfig` gains `hardware : [HardwareBackend]` field. Mixed deployments (some coins internal, some external, plus physical devices) are representable in a single config:

```
{ coins    = [dogecoin_internal, litecoin_external]
, hardware = [fury_usb, bitaxe_lan, gpu_local]
}
```

#### Grim/Main.u — NEW FILE

`grimMain` is the UCM entry point:

```
grimMain config =
  List.each config.coins    (coin -> platformFork do runShim coin)
  List.each config.hardware (hw   -> platformFork do runHardwareWorker hw)
  runLocal do
    platformFork do blockLoop
    proofLoop
```

Three example configs provided:
- `defaultConfig` — single DOGE coin, InternalPool, no hardware
- `exampleExternalConfig` — DOGE internal + LTC external
- `exampleHardwareConfig` — DOGE internal + BTC external + Fury + Bitaxe + GPU

`configureGPUPools` helper builds the correct `stratum+tcp://` URL per coin mode and calls `cgminerAddPool` for each GPUMiner device.

---

## ✅ ALL MODULES COMPLETE

| Module | Status | Commit |
|---|---|---|
| Grim.Types | ✅ | `1128c090` |
| Grim.Math | ✅ | initial |
| Grim.Abilities | ✅ | initial |
| Grim.Vault | ✅ | initial |
| Grim.Pool | ✅ | `3501c9e5` |
| Grim.Knowledge | ✅ | `f6282113` |
| Grim.Governance | ✅ | `f6282113` |
| Grim.Handlers.Local | ✅ | `1128c090` |
| Grim.Handlers.Cloud | ✅ | `10b8d453` |
| Grim.Store.FileStore | ✅ | `d25b5d0e` |
| Grim.Shim.Stratum | ✅ | `81661cc3` |
| Grim.Shim.Hardware | ✅ | `1128c090` |
| Grim.Main | ✅ | `1128c090` |
| Grim.Route (via unison-route-done) | ✅ | standalone lib |

---

## Open Design Questions (unresolved)

1. **Browser cert flow** — thin vanilla JS shell calling Grim HTTP endpoints. No work needed here.
2. **NocoBase frontend** — retain as read layer or replace with Unison-served interface.
3. **ShimQueues spin-poll** — replace with UCM `Channel`/`Scope` when available.
4. **nativeFindNonce** — C/Rust FFI implementation for Fury software nonce loop. Currently a stub.
5. **VarDiff** — per-worker difficulty adjustment for long-running GPU/ASIC sessions. Planned.

---

## Remaining Work

- [ ] Implement `nativeFindNonce` FFI (C/Rust tight loop for Fury/software PoW)
- [ ] Implement `furyPollJob` / `furySubmitNonce` HID FFI stubs
- [ ] Implement `bitaxePollJob` / `bitaxeGetHashrate` HTTP FFI stubs
- [ ] Implement `cgminerGetWork` / `cgminerGetHashrate` JSON-RPC FFI stubs
- [ ] Wire `unison-route-done` into `Grim.Handlers.Local` and `Grim.Handlers.Cloud` dispatch
- [ ] VarDiff: per-worker difficulty adjustment
- [ ] `hardwareMonitorLoop` stream event type (dedicated `HardwareStats` vs current Share overload)
- [ ] Resolve NocoBase frontend decision
- [ ] Replace `ShimQueues` spin-poll with UCM `Channel`/`Scope`
- [ ] Browser cert UI (thin vanilla JS, calls Grim HTTP endpoints)

---

## Architecture Summary

Grim is the system. One content-addressed Unison codebase. The pure logic — `wikiTrust`, `canPerformAction`, `proofLoop`, `guardedAction` — is identical in both deployments. The deployment profile (`LocalSelfHosted` vs `CloudLancia`) is determined entirely by which handler stack (`runLocal` vs `runCloud`) is provided at runtime. No parallel codebases. No bridge. No translation layer.

Physical hardware (GawMiner Fury, Bitaxe, GPU via CGMiner/BFGMiner) is supported through the `HardwareWorker` ability. All hardware paths funnel into `ShimQueues`; `proofLoop` and `blockLoop` are hardware-agnostic.
