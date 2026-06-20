# Grim Session Log

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

In `Local.u`, key material (AES keys, Ed25519 private keys) is derived locally via `scryptDeriveKey` / platform FFI and lives briefly in process memory. In `Cloud.u` all key operations route through the cloud KMS (`cloudKmsEncrypt`, `cloudKmsSignJWT`, `cloudKmsProvisionCert`). The Grim process never holds raw key material. This is the Lancia security model applied uniformly across all nine abilities.

#### Governance side effect

`handleGovernanceCloud.setMode` has one addition over `handleGovernanceLocal`: after persisting the new mode it calls `cloudEventEmit "governance"` to propagate the change to all nodes via the event bus. The local handler writes to a config file and relies on the single process reading it. The cloud handler broadcasts immediately, keeping distributed nodes consistent without polling.

---

### unison-filestore — EXTRACTED AS STANDALONE LIBRARY

Repo: [github.com/5mil/unison-filestore](https://github.com/5mil/unison-filestore)  
Version: `0.1.0`  
License: MIT

The `FileIO` ability and all entity/user store functions extracted as a standalone Unison library. Zero dependency on Grim types or abilities. Can be dropped into any Unison application needing a content-addressed file store without an external DB engine.

#### Additions over `Grim/Store/FileStore.u`

| Area | Delta |
|---|---|
| `EntityType` | `CustomEntity Text` variant added |
| `textToEntityType` | `custom:<name>` prefix round-trip handled |
| `Entity` / `User` / `Role` / `Tier` | Self-contained — zero Grim dependency |
| `fsUpdateEntity` | Unused `_deserialise` param removed |
| Path helpers | All promoted to named functions |
| Tests | 7 → 11 (adds `testCustomEntityType`, `testMockFileExists`, `testMockDelete`, `testMockHashDeterministic`) |
| Docs | `README.md`, `USAGE.md`, `WHITEPAPER.md` |
| `handleAuthFS` / `handleKnowledgeFS` | Excluded — depend on Grim-specific abilities; library owns storage primitives only |

---

### Grim.Store.FileStore — COMPLETE

File: `Grim/Store/FileStore.u` | Commit: `d25b5d0e`  
Entire Knowledge + Auth persistence layer. Unison-native. Zero SQLite. Zero ORM.

---

### Grim.Shim.Stratum — COMPLETE

File: `Grim/Shim/Stratum.u` | Commit: `83a64a12`  
Full Stratum V1 TCP shim in Unison. Pure parser + dispatcher, `StratumSocket` ability (swappable for tests), `ShimQueues` bridge, `shimNodeMonitor`, `runShim` composition.

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

---

## Open Design Questions (unresolved)

1. **Browser cert flow** — confirmed: thin vanilla JS shell calling Grim HTTP endpoints. No work needed in this codebase.
2. **NocoBase frontend** — decision pending: retain as read layer or replace with Unison-served interface.
3. **ShimQueues spin-poll** — replace with UCM `Channel`/`Scope` when available. Handler swap only; no logic change.

---

## Remaining Work

- [ ] Resolve NocoBase frontend decision
- [ ] Replace `ShimQueues` spin-poll with UCM `Channel`/`Scope`
- [ ] Implement the 20 platform FFI stubs (native shim layer, outside Unison)
- [ ] Wire `runLocal` / `runCloud` to a UCM `main` entry point
- [ ] Browser cert UI (thin vanilla JS, calls Grim HTTP endpoints)

---

## Architecture Summary

Grim is the system. One content-addressed Unison codebase. The pure logic — `wikiTrust`, `canPerformAction`, `proofLoop`, `guardedAction` — is identical in both deployments. The deployment profile (`LocalSelfHosted` vs `CloudLancia`) is determined entirely by which handler stack (`runLocal` vs `runCloud`) is provided at runtime. No parallel codebases. No bridge. No translation layer.
