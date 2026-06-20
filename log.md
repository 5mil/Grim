# Grim Session Log

---

## Session: 2026-06-19 (continued)

### unison-filestore — EXTRACTED AS STANDALONE LIBRARY

Repo: [github.com/5mil/unison-filestore](https://github.com/5mil/unison-filestore)  
Version: `0.1.0`  
License: MIT

The `FileIO` ability and all entity/user store functions from `Grim/Store/FileStore.u` have been extracted into a standalone Unison library. The internal `Grim/Store/FileStore.u` remains as the Grim-specific integration layer; the library is the reusable, application-agnostic core.

#### Additions over `Grim/Store/FileStore.u`

| Area | Internal (`Grim/Store/FileStore.u`) | Standalone (`unison-filestore`) |
|---|---|---|
| `EntityType` | 5 fixed variants | 5 fixed + `CustomEntity Text` escape hatch for any application |
| `textToEntityType` | 5 cases | 6 cases: handles `custom:<name>` prefix round-trip |
| `Entity` / `Fact` / `Hash` | Imported from `Grim.Types` | Self-contained type definitions in the library itself |
| `Role` / `Tier` / `User` | Imported from `Grim.Types` | Self-contained type definitions (library has no Grim dependency) |
| `fsUpdateEntity` | Takes unused `_deserialise` param | Signature cleaned: `Text -> (a -> Text) -> Hash -> a -> Text -> '{FileIO} Entity a` |
| Path helpers | Inline strings | Named: `entityFilePath`, `typeIndexPath`, `factsFilePath`, `usersFilePath`, `sessionsFilePath`, `revokedFilePath`, `pwhashFilePath` |
| Tests | 7 tests | 11 tests: adds `testCustomEntityType`, `testMockFileExists`, `testMockDelete`, `testMockHashDeterministic` |
| Docs | None | `README.md`, `USAGE.md`, `WHITEPAPER.md` |
| `handleAuthFS` | Present (Grim-specific, uses `Grim.Abilities.Auth`) | Not included — Auth is application-specific; library provides the user store primitives only (`fsReadUsers`, `fsWriteUser`, `fsGetUser`, `fsRevokeToken`, etc.) |
| `handleKnowledgeFS` | Present (Grim-specific, uses `Grim.Abilities.Knowledge`) | Not included — Knowledge ability is Grim-specific; library provides store operations only |

**Net:** the library is `FileIO` ability + entity store + user store + JSON serialisation + 11 tests, with zero dependency on Grim types or abilities. It can be dropped into any Unison application that needs a content-addressed file store without an external DB engine.

#### Why no `handleAuthFS` / `handleKnowledgeFS` in the library

Those two handlers depend on `Grim.Abilities.Auth` and `Grim.Abilities.Knowledge` — both of which are Grim-specific algebraic effects. Extracting them would pull the entire Grim ability surface into the library. The correct boundary is: the library owns the *storage primitives* (`fsStoreEntity`, `fsReadUsers`, etc.); Grim owns the *ability handlers* that call those primitives. This separation means the library has no Grim dependency and can be versioned independently.

---

### Grim.Store.FileStore — COMPLETE
### SQLite dependency — ELIMINATED

File: `Grim/Store/FileStore.u`  
Commit: `d25b5d0ed895640c3f02baba6dd01bf7e4ba0ccb`

The entire Knowledge and Auth persistence layer is Unison-native. No SQLite. No ORM. No external DB engine.

#### Storage Layout
```
$GRIM_DATA_PATH/
  entities/
    <hash>.json              ← one file per entity revision (content-addressed)
    by-type/<type>.idx       ← append-only hash index per EntityType
  users/
    users.jsonl              ← user ledger (last-write-wins per userId)
    sessions.jsonl           ← issued session tokens
    revoked.jsonl            ← revoked JTIs
    <userId>.pwhash          ← base64 scrypt hash per user
  facts/
    <hash>.facts.jsonl       ← facts per entity hash
```

#### Complete FFI surface — entire self-hosted deployment

| FFI stub | Purpose |
|---|---|
| `platformReadFile` / `platformWriteFile` / `platformAppendLine` / `platformListDir` / `platformFileExists` / `platformDeleteFile` | File I/O |
| `platformNow` | Wall-clock timestamp |
| `platformSHA3` | SHA3-256 hash |
| `platformVerifyEd25519` | Cert signature verification |
| `aesGcmEncrypt` / `aesGcmDecrypt` / `scryptDeriveKey` / `platformRandomBytes` | Vault + Auth crypto |
| `tcpAccept` / `tcpReadLine` / `tcpWriteLine` / `tcpClose` | Stratum TCP socket |
| `platformUUID` | Session ID generation |
| `rpcGetBlockHeight` / `rpcGetBlockHash` | Coin node RPC polling |
| `platformSleepMs` | Shim monitor loop |
| `wsEmit` | WebSocket broadcast |

No DB engine anywhere in this list.

---

### Grim.Shim.Stratum — COMPLETE

File: `Grim/Shim/Stratum.u`  
Commit: `83a64a1232ee0ec0a5db442c96623ede78965c09`

Full Stratum V1 TCP shim in Unison. Pure parser + dispatcher, `StratumSocket` ability (swappable for tests), `ShimQueues` ability bridging TCP to `handleMining`, `shimNodeMonitor` block detector, `runShim` composition.

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
| Grim.Store.FileStore | ✅ Complete |
| Grim.Shim.Stratum | ✅ Complete |
| Grim.Handlers.Cloud | 📋 Next |

### Open Design Questions
1. **Browser cert flow** — confirmed: thin vanilla JS shell calling Grim HTTP endpoints.
2. **NocoBase frontend** — decision pending: retain as read layer or replace.
3. **ShimQueues spin-poll** — replace with UCM Channel/Scope when available (handler swap only).

---

### Next Steps
- [ ] Write `Grim.Handlers.Cloud`
- [ ] Confirm NocoBase frontend decision
- [ ] Replace ShimQueues spin-poll with UCM Channel/Scope primitives

---

## Previous Sessions (summary)

| Module | Commit |
|---|---|
| Grim.Shim.Stratum | `83a64a12` |
| Grim.Store.FileStore | `d25b5d0e` |
| Grim.Handlers.Local | `9879199d` |
| Grim.Knowledge + Grim.Governance | `f6282113` |
| Grim.Pool | `3501c9e5` |

### Core Finding
Grim is the system. One codebase. One language. The deployment profile is determined by which ability handlers are provided at runtime.
