# Grim Session Log

---

## Session: 2026-06-19 (continued)

### Grim.Store.FileStore — COMPLETE
### SQLite dependency — ELIMINATED

File: `Grim/Store/FileStore.u`  
Commit: `d25b5d0ed895640c3f02baba6dd01bf7e4ba0ccb`

**Decision:** SQLite FFI library question closed. No external DB. No FFI beyond file I/O and two crypto primitives. Zero-dependency self-hosted deployment.

#### What Was Replaced

| Was (Local.u SQLite stubs) | Now (FileStore.u Unison) |
|---|---|
| `sqliteStoreEntity` | `fsStoreEntity` — writes `<hash>.json` file |
| `sqliteGetEntity` | `fsGetEntity` — reads `<hash>.json` file |
| `sqliteEntityHistory` | `fsEntityHistory` — follows `previous` hash chain |
| `sqliteListByType` | `fsListByType` — scans `by-type/<type>.idx` append-only index |
| `sqliteUpdateEntity` | `fsUpdateEntity` — creates new hash-linked revision file |
| `sqliteGetFacts` | `fsGetFacts` — reads `<hash>.facts.jsonl` |
| `sqliteAddFact` | `fsAddFact` — appends to `<hash>.facts.jsonl` |
| `localAuthGetCurrentUser` | `Ref`-based current-user context in `handleAuthFS` |
| `localAuthLogin` | `fsGetUserByUsername` + scrypt hash compare |
| `localAuthListUsers` | `fsReadUsers` — scans `users.jsonl`, last-write-wins per id |
| `localAuthCreateUser` | `fsWriteUser` + `fsStorePasswordHash` |
| `localAuthSetRole` | `fsWriteUser` with updated role (append to ledger) |
| `localAuthDeleteUser` | Soft-delete: append Banned tombstone to ledger |

#### Storage Layout
```
$GRIM_DATA_PATH/
  entities/
    <hash>.json              ← one file per entity revision
    by-type/<type>.idx       ← append-only hash index per EntityType
  users/
    users.jsonl              ← append-only user ledger (last-write-wins)
    sessions.jsonl           ← active session tokens
    revoked.jsonl            ← revoked JTIs
    <userId>.pwhash          ← base64-encoded scrypt hash per user
  facts/
    <hash>.facts.jsonl       ← facts appended per entity hash
```

#### `FileIO` Ability — the key architectural move

All file I/O is declared as a single swappable ability:

| Operation | Description |
|---|---|
| `readFile` | Returns `Optional Text` (None if absent) |
| `writeFile` | Atomic write (write-then-rename in production) |
| `appendLine` | Append a JSONL line (creates file if absent) |
| `listDir` | List filenames in a directory |
| `fileExists` | Bool existence check |
| `deleteFile` | No-op if absent |
| `fileNow` | Wall-clock timestamp (Nat, seconds since epoch) |
| `hashText` | SHA3-256 of a Text, returns hex string |

Two handlers:
- **`handleFileIO`** — production, 8 platform FFI stubs (file I/O only)
- **`handleFileIOMock`** — tests, `Ref (Map Text Text)`, no disk access

With `handleFileIOMock`, `handleKnowledgeFS` and `handleAuthFS` are **fully testable without a disk, a database, or a running process.**

#### Remaining FFI surface (entire self-hosted deployment)

| Stub | Purpose |
|---|---|
| `platformReadFile` / `platformWriteFile` / `platformAppendLine` / `platformListDir` / `platformFileExists` / `platformDeleteFile` | Basic file I/O |
| `platformNow` | Wall-clock timestamp |
| `platformSHA3` | SHA3-256 hash |
| `platformVerifyEd25519` | Cert signature verification |
| `aesGcmEncrypt` / `aesGcmDecrypt` / `scryptDeriveKey` / `platformRandomBytes` | Vault + Auth crypto |
| `tcpAccept` / `tcpReadLine` / `tcpWriteLine` / `tcpClose` | Stratum TCP socket |
| `platformUUID` | Session ID generation |
| `rpcGetBlockHeight` / `rpcGetBlockHash` | Coin node RPC polling |
| `platformSleepMs` | Shim node monitor loop |
| `wsEmit` | WebSocket broadcast |

This is the **complete FFI boundary** for the entire self-hosted Grim deployment. No DB engine. No ORM. No external process except the WebSocket server and coin nodes.

#### Tests (7)
- `testEntityTypeRoundtrip` — all 5 entity types serialise and parse back correctly
- `testFactToJson` — fact JSON serialisation
- `testFsRoleRank` / `testFsTierRank` — rank ordering
- `testMockStoreAndRead` — write then read a file using mock handler
- `testMockAppendLine` — two appends produce correct JSONL
- `testUserJsonRoundtrip` — user serialises to JSON with correct fields

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
- [ ] Write Grim.Handlers.Cloud
- [ ] Confirm NocoBase frontend decision
- [ ] Replace ShimQueues spin-poll with UCM Channel/Scope primitives

---

## Previous Sessions (summary)

| Module | Commit |
|---|---|
| Grim.Shim.Stratum | `83a64a12` |
| Grim.Handlers.Local | `9879199d` |
| Grim.Knowledge + Grim.Governance | `f6282113` |
| Grim.Pool | `3501c9e5` |

### Core Finding
Grim is the system. One codebase. One language. The deployment profile is determined by which ability handlers are provided at runtime.
