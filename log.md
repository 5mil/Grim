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

## ✅ ALL MODULES COMPLETE

| Module | Status | Commit |
|---|---|---|
| Grim.Types | ✅ | initial |
| Grim.Math | ✅ | initial |
| Grim.Abilities | ✅ | initial |
| Grim.Vault | ✅ | initial |
| Grim.Pool | ✅ | `3501c9e5` |
| Grim.Knowledge | ✅ | `f6282113` |
| Grim.Governance | ✅ | `f6282113` |
| Grim.Handlers.Local | ✅ | `9879199d` |
| Grim.Store.FileStore | ✅ | `d25b5d0e` |
| Grim.Shim.Stratum | ✅ | `83a64a12` |
| Grim.Handlers.Cloud | ✅ | `10b8d453` |
| Grim.Route (via unison-route-done) | ✅ | standalone lib |

---

## Open Design Questions (unresolved)

1. **Browser cert flow** — thin vanilla JS shell calling Grim HTTP endpoints. No work needed here.
2. **NocoBase frontend** — retain as read layer or replace with Unison-served interface.
3. **ShimQueues spin-poll** — replace with UCM `Channel`/`Scope` when available.

---

## Remaining Work

- [ ] Wire `unison-route-done` into `Grim.Handlers.Local` and `Grim.Handlers.Cloud` dispatch
- [ ] Resolve NocoBase frontend decision
- [ ] Replace `ShimQueues` spin-poll with UCM `Channel`/`Scope`
- [ ] Implement the 20 platform FFI stubs
- [ ] Wire `runLocal` / `runCloud` to a UCM `main` entry point
- [ ] Browser cert UI (thin vanilla JS, calls Grim HTTP endpoints)

---

## Architecture Summary

Grim is the system. One content-addressed Unison codebase. The pure logic — `wikiTrust`, `canPerformAction`, `proofLoop`, `guardedAction` — is identical in both deployments. The deployment profile (`LocalSelfHosted` vs `CloudLancia`) is determined entirely by which handler stack (`runLocal` vs `runCloud`) is provided at runtime. No parallel codebases. No bridge. No translation layer.
