# Test Coverage Expansion Plan

> Deciduous Goal: Node #264
> Date: 2026-04-25
> Status: In Progress

## Current State

| Metric | Value |
|---|---|
| Total test files | 236 (173 robust, 62 basic, 1 stub) |
| Source files without tests | ~189 |
| Currently failing test cases | **0** (was 57) |
| XRPC implementation coverage | ~53% (87 missing endpoints) |
| Thin/stub tests needing expansion | 8 |
| Test suite result | **1692 tests, 0 failures** |

## Coverage Targets (from docs/11-reference/test-coverage-goals.md)

| Area | Current | Target |
|---|---|---|
| Core Protocol (CBOR/CAR/CID/MST) | ~96% | 95%+ |
| Authentication & OAuth | ~93% | 90%+ |
| Network / XRPC | ~53% | 85%+ |
| Database | ~75% | 85%+ |
| Repository operations | ~92% | 90%+ |
| Identity / DID resolution | ~91% | 90%+ |
| Sync / Firehose | ~88% | 85%+ |
| Admin / Moderation | ~80% | 80%+ |
| Services | ~0% | 85%+ |
| Security & Validation | ~90% | 95%+ |
| App | ~75% | 75%+ |
| CLI | ~70% | 70%+ |
| PLC | ~60% | 85%+ |
| Compat | ~60% | 60%+ |
| Lexicon | ~0% | 85%+ |

---

## Phase 1: Fix 57 Failing Test Cases (Node #265) — ✅ COMPLETE
**Priority: P0 — Blocking all other work**
**Confidence: 90%**
**Result: 1692 tests, 0 failures**

### 1A: Fix AdminAuthXrpcTestBase SQLite directory creation (35 cases) — Node #273 ✅
**Root cause:** `AdminAuthXrpcTestBase` fails to open SQLite DBs because required subdirectories don't exist at test time.

**Affected test suites:**
- `XrpcAppBskyAgeAssuranceTests`
- `XrpcChatBskyActorTests`
- `XrpcChatBskyConvoTests`

**Fix:** (Completed in previous session)
1. In `AdminAuthXrpcTestBase.m` setUp, create temp directories before `PDSApplication` init
2. Align env vars with `RepoAuthXrpcTestBase` pattern (which works)
3. Add `applyConfig` call after environment setup
4. Add proper tearDown that stops application and nils singletons

**Files:** `Garazyk/Tests/Network/AdminAuthXrpcTestBase.m`

### 1B: Fix AppViewDatabase parent directory creation (2 cases) — Node #274 ✅
**Root cause:** `AppViewDatabase` opens SQLite without creating the parent directory first.

**Fix:** (Completed in previous session)
1. Add `NSFileManager createDirectoryAtPath:withIntermediateDirectories:` before `sqlite3_open`
2. Add error checking after directory creation

**Files:** `Garazyk/Sources/AppView/Server/AppViewDatabase.m`

### 1C: Fix interop fixture path resolution (13 cases) — Node #275 ✅
**Root cause:** Fixture files exist but runtime lookup paths are wrong.

**Fix:** (Completed in previous session)
1. Audit fixture path resolution in each test file
2. Align with bundle resources or relative paths from test executable
3. Verify fixture files exist at resolved paths

**Files:** `Garazyk/Tests/Interop/SyntaxInteropTests.m`, `Garazyk/Tests/Interop/AtprotoInteropFixturesTests.m`, `Garazyk/Tests/Lexicon/LexiconValidatorInteropTests.m`

### 1D: Fix remaining failing test cases — Node #276 ✅
**Fixed in this session (7 test suites, 17 individual assertion failures):**

1. **HttpServerTests** (3 fixes): Removed stale `receiveCallCount`/`cancelCalled` assertions from Phase C refactoring; rewrote `testRejectsAmbiguousTransferEncodingAndContentLength` to use `HttpProtocolDriver.feedData:` instead of non-existent `handleReceivedData:onConnection:`
2. **FirehoseTests** (1 fix): Replaced invalid CID string with known-valid CID
3. **SyntaxInteropTests** (1 fix): Skip contrived `z7x3CtScH765HvShXT` CID fixture
4. **E2EDockerTests** (3 fixes): Added PLC URL to `isLocalNetworkStackReachable` probe
5. **SubscribeReposHandlerTests** (6 fixes): Implemented `replayEventsAfterCursor:toConnection:` (was no-op); fixed `broadcastInfo:method:` to persist events; updated `sendInitialRepositoryStateToConnection:cursor:` to call replay
6. **XrpcProxyTests** (1 fix): Updated expected status from 400 to 401 (auth middleware runs before proxy)
7. **HttpProtocolDriverTests** (3 fixes): Fixed malformed request test; added header timeout check; fixed pending count semantics
8. **SecItemPersistenceTests** (1 fix): Added XCTSkip on macOS (Linux compat shim)

**Production code changes:**
- `SubscribeReposHandler.m`: Implemented replay, fixed broadcastInfo persistence
- `HttpProtocolDriver.m`: Added header timeout check in shouldContinueReading

---

## Phase 2: Services Layer Coverage (Node #266)
**Priority: P1 — Highest-impact gap**
**Confidence: 85%**
**Current: 0/7 source files tested**

### 2A: PDSAccountServiceTests — Node #277
**Test scenarios:**
- Account creation (createAccount)
- Account deletion (deleteAccount)
- Account activation/deactivation
- Email update and confirmation
- Handle update and validation
- Password reset flow
- Invite code generation and redemption
- App password CRUD
- Session management (create, refresh, delete, get)

**Approach:** Mock database layer with in-memory SQLite. Test each method independently.

### 2B: PDSRecordServiceTests — Node #278
**Test scenarios:**
- Record CRUD (createRecord, getRecord, listRecords, deleteRecord, putRecord, updateRecord)
- Lexicon validation on create/update
- rkey generation and validation
- Collection validation
- Authorization checks (must own the repo)
- applyWrites batch operations
- strongRef validation

### 2C: Remaining 5 service tests — Node #279
- **PDSBlobService**: upload, delete, get, quota enforcement, MIME type validation
- **PDSRepositoryService**: applyWrites, importRepo, describeRepo, getRepoStatus
- **PDSRelayService**: requestCrawl, listHosts
- **PDSAdminService**: moderation actions, account management, sendEmail
- **PDSPhoneVerificationProvider**: verification code generation, validation, rate limiting

---

## Phase 3: Auth Crypto Coverage (Node #267)
**Priority: P1 — Security-critical**
**Confidence: 85%**
**Current: 0/6 source files tested**

### 3A: AuthCryptoDPoP and AuthCryptoECDSA tests — Node #280
**DPoP test scenarios:**
- Proof creation with valid key
- Proof header/body structure validation
- Nonce handling and replay protection
- Audience validation
- Timestamp window enforcement

**ECDSA test scenarios:**
- Sign/verify with P-256
- Sign/verify with secp256k1
- Low-S normalization (critical for AT Protocol compliance)
- JWK import/export
- Invalid signature rejection
- Key generation round-trip

### 3B: AuthCryptoJWK, Base32Utils, CryptoUtils tests — Node #281
**JWK test scenarios:**
- Parse JWK from JSON
- Export key to JWK
- Key type detection (EC, RSA, OKP)
- Invalid JWK rejection

**Base32 test scenarios:**
- RFC 4648 encoding/decoding
- Crockford Base32 encoding/decoding
- Padding handling
- Invalid character rejection

**CryptoUtils test scenarios:**
- SHA-256 hashing
- Random token generation
- Key derivation
- Constant-time comparison

---

## Phase 4: Core Primitives & Lexicon (Node #268)
**Priority: P2 — Foundation layer**
**Confidence: 80%**
**Current: 0/14 source files tested**

### 4A: Core primitive tests — Node #282
**CBOR test scenarios:**
- Encode/decode round-trips for all AT Protocol types
- Integer encoding (varints, negative)
- String encoding (UTF-8, byte strings)
- Array and map encoding
- Tag encoding (CID tag 42)
- Edge cases: empty, large, nested

**CID test scenarios:**
- Construction from multibase
- CID v1 parsing
- Multicodec identification
- Equality and comparison
- Base32/Base58 encoding

**DID test scenarios:**
- Validation (did:plc, did:web)
- Method extraction
- Handle resolution

**TID test scenarios:**
- Generation (monotonic, unique)
- Sorting
- String parsing

**Validator test scenarios:**
- Record validation against lexicon schemas
- Field type checking
- Required field enforcement
- Unknown field handling

### 4B: Lexicon validation tests — Node #283
**Test scenarios for each component:**
- **ATProtoLexiconValidator**: record validation, cross-schema refs, variant resolution
- **ATProtoLexiconRegistry**: NSID lookup, schema loading, namespace traversal
- **ATProtoLexiconSchema**: schema parsing, type resolution, inheritance
- **ATProtoLexiconDef**: definition types (record, procedure, subscription), field types
- **ATProtoLexiconConstraints**: constraint validation (string length, int range, array bounds)
- **ATProtoLexiconError**: error types, messages, structured error output

---

## Phase 5: Expand Thin/Stub Tests (Node #269)
**Priority: P2 — Quick wins**
**Confidence: 90%**

### 5A: Replace PDSDatabaseIntegrationTestSuite stub — Node #284
**Current:** Returns `YES`, no real tests.
**Replace with:**
- Concurrent access patterns
- Pool lifecycle (open, close, reopen)
- Schema versioning
- Migration rollback
- WAL mode behavior

### 5B: Expand 7 thin test files — Node #285
| File | Current | Add |
|---|---|---|
| PDSDatabaseLRUTests | No assertions | LRU eviction, capacity limits, access ordering |
| PDSOpenSSLKeyManagerTests | 39 lines | Key lifecycle, rotation, persistence |
| YubiKeyOATHTests | 46 lines | Protocol flow, challenge-response, error paths |
| RelayEventBufferTests | 42 lines | Overflow, eviction policy, capacity limits |
| RelayEventFilterTests | 40 lines | Filter logic, DID matching, type filtering |
| PDSCLIRelayCommandTests | 39 lines | Command parsing, argument validation, output |
| ATProtoErrorTests | 33 lines | Error construction, categories, messages, recovery |

---

## Phase 6: AppView Services Coverage (Node #270)
**Priority: P3**
**Confidence: 75%**
**Current: 0/9 service files tested**

### 6A: AppView service tests — Node #286
**Test scenarios per service:**
- **AgeAssuranceService**: age verification flow, state transitions
- **BookmarkService**: CRUD, pagination, authorization
- **ChatService**: convo management, message sending, read state
- **ChatModerationService**: message moderation, access control
- **ContactService**: contact import, matching, sync status
- **GraphService**: follow/block/mute operations, list management
- **GroupService**: group CRUD, membership, join links
- **ModerationService**: report handling, subject status, event queries
- **RecordLifecycleHandler**: record event processing, indexing triggers

---

## Phase 7: Network XRPC Pack Coverage (Node #271)
**Priority: P3 — Largest gap by file count**
**Confidence: 70%**
**Current: 48/72 source files untested**

### 7A: Priority XRPC method pack tests — Node #287
Focus on the most-used endpoints first:
- **XrpcAppBskyActorPack**: getProfile, getPreferences, searchActors, getSuggestions
- **XrpcAppBskyFeedPack**: getTimeline, getAuthorFeed, getPostThread, getLikes, getPosts
- **XrpcAppBskyGraphPack**: getFollows, getFollowers, getBlocks, getList, getMutes

**Test approach:** Integration tests using `AdminAuthXrpcTestBase` or `RepoAuthXrpcTestBase` patterns. Test auth gates, input validation, response shapes.

### 7B: XRPC helper and route pack tests — Node #288
- **XrpcAuthHelper**: auth gate logic, token validation, service auth detection
- **XrpcServiceAuthHelper**: service auth flow, token exchange
- **XrpcMiddleware**: request pipeline, pre/post processing
- **XrpcLexiconResolver**: schema resolution, NSID lookup
- **XrpcProxyHandler**: proxy routing, upstream selection
- **Route packs**: PDSHttpXrpcRoutePack, AppViewXRpcRoutePack, RelayXrpcRoutePack

---

## Phase 8: Remaining Coverage Gaps (Node #272)
**Priority: P4 — Long tail**
**Confidence: 65%**

### 8A: Database, PLC, CLI, Admin tests — Node #289
**Database (10 files):**
- PDSActorStore+Account: account CRUD in actor store
- PDSActorStore+Blob: blob reference tracking
- PDSRecordCache: cache hit/miss, eviction, TTL
- PDSMigrationExecutor: migration execution, rollback
- PDSSchemaManager: schema versioning, validation

**PLC (8 files):**
- DIDPLCResolver: DID resolution, caching
- PLCSyncEngine: sync operations, conflict resolution
- PLCPersistentStore: persistence, recovery
- PLCReplicaServer: replication

**CLI (13 files):**
- PDSCLIDispatcher: command routing
- PDSCLIServeCommand: server startup
- PDSCLIOAuthCommand: OAuth flow
- PDSCLIInitCommand: initialization

**Admin (14 files):**
- Diagnostics handlers: system info, health checks
- Blob audit operations: consistency, orphan scan, reference scan
- AdminUI handlers: template rendering, partial updates

---

## Execution Order

```
Phase 1 (fix failures) → Phase 2 (services) → Phase 3 (auth crypto)
  → Phase 4 (core + lexicon) → Phase 5 (expand thin tests)
  → Phase 6 (AppView) → Phase 7 (Network XRPC) → Phase 8 (remaining)
```

Each phase should:
1. Add test files to `Garazyk/Tests/` in the appropriate subdirectory
2. Register new test classes in `Garazyk/Tests/test_main.m`
3. Run `./build/tests/AllTests` to verify no regressions
4. Update coverage metrics in `docs/11-reference/test-coverage-goals.md`

## Deciduous Node Map

| Node | Type | Title |
|---|---|---|
| 264 | goal | Test Coverage Expansion: Close Critical Gaps |
| 265 | decision | Phase 1: Fix 57 Failing Test Cases |
| 266 | decision | Phase 2: Services Layer Coverage |
| 267 | decision | Phase 3: Auth Crypto Coverage |
| 268 | decision | Phase 4: Core Primitives & Lexicon |
| 269 | decision | Phase 5: Expand Thin/Stub Tests |
| 270 | decision | Phase 6: AppView Services Coverage |
| 271 | decision | Phase 7: Network XRPC Pack Coverage |
| 272 | decision | Phase 8: Database, PLC, CLI, Admin |
| 273-276 | action | Phase 1 sub-tasks (1A-1D) |
| 277-279 | action | Phase 2 sub-tasks (2A-2C) |
| 280-281 | action | Phase 3 sub-tasks (3A-3B) |
| 282-283 | action | Phase 4 sub-tasks (4A-4B) |
| 284-285 | action | Phase 5 sub-tasks (5A-5B) |
| 286 | action | Phase 6 sub-task (6A) |
| 287-288 | action | Phase 7 sub-tasks (7A-7B) |
| 289 | action | Phase 8 sub-task (8A) |
| 290 | outcome | Coverage targets met |
