# Garazyk — Domain & Architecture Glossary

The names for the good seams in this codebase. Architecture vocabulary (module, interface,
depth, deep, shallow, seam, adapter, leverage, locality) follows the `codebase-design` skill;
this file names the **domain** concepts those terms attach to. Keep entries short and
authoritative — an entry exists so reviews and refactors use one name for one concept.

> Seeded 2026-07-11 during the QueryRunner deepening pilot
> (`queryrunner_deepening_pilot_plan.md`). Extend lazily as concepts are named or sharpened.

## Data-access seams (`Database/`)

### ConnectionManager
`id<ATProtoConnectionManager>` (`Database/Connection/`). Supplies a SQLite connection and
runs work against it via `execute:` / `transact:` blocks. **Adapters:**
`ATProtoConnectionManagerSerial` (owns a serial `dispatch_queue`; serializes all access) and
`ATProtoConnectionManagerPooled`. A real seam — two adapters, and it lets a store delegate
its thread-safety rather than hand-rolling a `dispatch_queue`. **Do not flatten.**

### QueryRunner
`ATProtoDatabaseQueryRunner` (`Database/Utils/`). The **deep module** that owns SQLite
statement mechanics — prepare / bind / step / finalize, typed column extraction, pragmas,
error-domain construction — behind a small interface over a `ConnectionManager`. Callers pass
SQL + params and get rows or a success flag; they never touch a `sqlite3 *`. Reads
(`executeQuery:`) and single writes (`executeUpdate:`) manage their own connection;
multi-statement writes go through `performWriteTransaction:`, which yields a **Transactor**.

### Transactor
The seam handed to a `performWriteTransaction:` block: `id<ATProtoDatabaseTransactor>`,
exposing `executeQuery:` / `executeUpdate:` scoped to the in-flight transaction. It hides the
raw `sqlite3 *` handle that the transaction block would otherwise expose, so the write path is
as clean as the read path. Named to match the existing `PDSActorStoreTransactor` (see
ActorStore) — one word, one concept, across both stores.

### ActorStore
`ActorStore` (`Database/ActorStore/`). A single user's (DID's) SQLite database, presented
through two role interfaces: `PDSActorStoreReader` (queries) and `PDSActorStoreTransactor`
(mutations inside `transactWithBlock:`). The `Reader` / `Transactor` split is the naming
precedent the QueryRunner **Transactor** follows.

## XRPC registration (`Network/`)

### NSID
An AT Protocol Namespaced Identifier — the dotted method id of an XRPC endpoint (e.g.
`com.atproto.server.createAccount`, `app.bsky.feed.getLikes`). Registration and dispatch key
on the NSID string; incoming requests carry arbitrary NSID strings, so the dispatcher
(`XrpcHandler`) is `NSString`-keyed on the read side by necessity.

### GZXrpcNSID
The generated source of truth for method NSIDs: `Network/Generated/GZXrpcNSID.{h,m}`, ~331
`NSString * const GZNSID…` constants emitted by the gruszka generator from the same lexicons
that produce the TS client. Route packs register with these constants
(`registerMethod:GZNSID… handler:`) instead of raw `@"…"` literals or the (removed) 117
`XrpcHandler` convenience methods; a `narzedzia` lint forbids raw `registerMethod:@"literal"`.
Constants are plain strings, not a typed wrapper — see
`docs/adr/0003-xrpc-registration-uses-plain-nsid-constants.md` and
`xrpc_nsid_registration_plan.md`.

## Layering

### Compat shim
`Compat/` reimplements Apple framework API surfaces (Security, CommonCrypto, CoreFoundation,
os/log, XCTest, …) so the rest of the stack runs unchanged on GNUstep/Linux. It is the
**lowest** layer — everything depends on it, and it must not depend on higher layers such as
`Database/`. See `docs/adr/0001-compat-shims-must-not-depend-on-database.md`.

## Services (Polish vehicle codenames → role)

| Codename | Role |
|---|---|
| Garazyk (main app) | PDS — repositories, blobs, accounts, XRPC |
| `syrena` | AppView — indexing, profile/feed/notification queries |
| `zuk` | Relay (BGS) — firehose aggregation, crawl dispatch |
| `campagnola` | PLC server — DID directory, rotation keys, op logs |
| `mikrus` | Link index service |
| `beskid` | Edge record + identity cache service |
| `germ` | E2EE mailbox service |
| `jelcz` | Video processing service |
| `kaszlak` | PDS command-line interface |
| `garazyk-ui` | Admin UI |
| `syrena-chat` | Chat service |
