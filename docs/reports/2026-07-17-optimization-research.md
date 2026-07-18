# Optimization Research: Garazyk Data Structures & Algorithms

**Date:** 2026-07-17 (revised 2026-07-18 with code audit findings)
**Scope:** MST, SQLite storage, sync/firehose, CID/CBOR, and related subsystems
**Method:** Codebase audit of Garazyk source (MST.m, PDSSchemaManager.m, PDSDatabase.m, PDSRepositoryService.m, ActorStore.m, MSTPersistence.m) + literature review of AT Protocol specs, Bluesky reference implementation, SQLite documentation, and adjacent authenticated data structure research

---

## Works Cited

1. AT Protocol. "Repository Specification." <https://atproto.com/specs/repository>
2. Bluesky. "@atproto/repo — MST Implementation (`mst.ts`)." In `bluesky-social/atproto` GitHub repository. <https://github.com/bluesky-social/atproto/tree/main/packages/repo/src/mst>
3. Bluesky. "Sync v1.1 Proposal (`0006-sync-iteration`)." In `bluesky-social/proposals` GitHub repository. <https://github.com/bluesky-social/proposals/tree/main/0006-sync-iteration>
4. Bluesky. "Firehose prev-CID PR #3449." <https://github.com/bluesky-social/atproto/pull/3449>
5. Crosby, Scott A. and Wallach, Dan S. "Data Structures for Tamper-Evident Logging — The Locality of Memory Checking." Rice University.
6. Dryja, T. and Gudgeon, A. et al. "DMPT: Distributed Merkle Patricia Trie." Authenticated data structure research.
7. Nervos Network. "Sparse Merkle Tree." <https://github.com/nervosnetwork/sparse-merkle-tree>
8. Pocket Network. "Sparse Merkle Tree." <https://github.com/pokt-network/smt>
9. Cosmos Network. "IAVL Tree Implementation and Optimization Discussions." Cosmos SDK repository. <https://github.com/cosmos/cosmos-sdk>
10. Khuong, Paul-Virak and Morin, Pat. "Array Layouts for Comparison-Based Searching." *Journal of Experimental Algorithmics*, 2017. <https://arxiv.org/abs/1509.05053>
11. Algorithmica. "Static B-trees (S+ trees)." <https://en.algorithmica.org/hpc/data-structures/s-tree/>
12. Groot Koerkamp, Ragnar. "Static search trees: 40x faster than binary search." *CuriousCoding*, 2024-12-17. <https://curiouscoding.nl/posts/static-search-tree/>
13. SQLite. "Without ROWID Optimization." <https://www.sqlite.org/withoutrowid.html>
14. SQLite. "Write-Ahead Logging." <https://www.sqlite.org/wal.html>
15. SQLite. "PRAGMA Statements." <https://www.sqlite.org/pragma.html>
16. SQLite. "The SQLite Query Planner." <https://www.sqlite.org/queryplanner.html>
17. SQLite. "ON CONFLICT Clause." <https://www.sqlite.org/lang_conflict.html>
18. AT Protocol. "Sync Specification." <https://atproto.com/specs/sync>
19. AT Protocol. "Data Model: DAG-CBOR." <https://atproto.com/specs/data-models>
20. AT Protocol. "Identity: DIDs and Handles." <https://atproto.com/specs/identity>
21. AT Protocol. "OAuth 2.1 Profile." <https://atproto.com/specs/oauth>
22. Reuvens, Ruben. "Merkle Search Trees: Efficient State-Based CRDTs in Open Networks." Original MST paper.
23. Bluesky. "@atproto/pds — Config (`config.ts`)." In `bluesky-social/atproto` GitHub repository. <https://github.com/bluesky-social/atproto/blob/main/packages/pds/src/config/config.ts>
24. MarshalX. "python-libipld Release Notes." <https://github.com/MarshalX/python-libipld>
25. IPLD. "Content Addressing." <https://ipld.io/docs/data-model/content-addressing/>

---

## 1. Current Codebase State (Audited)

### 1.1 MST (Merkle Search Tree)

**Files:** `Garazyk/Sources/Repository/MST.{h,m}`, `MSTWalker.{h,m}`, `MSTPersistence.m`, `RepoCommit.m`

**Node structure:**
- `MSTNode` / `MSTNodeEntry` use prefix-compressed keys and subtree CIDs.
- `MSTNodeEntry` stores `prefixLen`, `keySuffix`, `value`, `tree` (CID, not child object).
- `MSTNode` has internal fields: `internalTree`, `treeCID`, `leftCID`, `originalCID`, `originalCBOR`, `internalEntries` (`NSMutableArray`).
- Key placement is driven by SHA-256-derived depth (`keyDepthFromBytes` counts leading zero bits).

**CID computation (audited):**
- CID computation is **already deferred** — not eager during mutations.
- `-getCID:` (`MST.m:227-241`) first checks a per-call `NSMapTable` cache, then checks `originalCID`, then falls back to `serializeToCBOR:` + SHA-256.
- `-serializeToCBOR:` (`MST.m:244-311`) fast-paths on `originalCBOR` — if the node was deserialized and not modified, it returns the original bytes.
- `setNodeHash:` (`MST.m:376-380`) is a **no-op** — the comment says hashes are computed on-demand via `getCID:`.
- **No dirty-flag / `outdatedPointer` pattern exists**, but one is not needed: mutations create new node objects, so original nodes retain their `originalCID`/`originalCBOR` naturally.

**Mutation pattern (audited):**
- Mutations are **mostly copy-on-write**: `split:`, `addRecursive:`, `deleteRecursive:`, `merge:` all create new `MSTNode` objects and use `mutableCopy` of entry arrays.
- A few in-place writes exist for cache hydration (deserialization sets `node.internalLeft`, `collectProofNodes:` caches loaded subtrees into existing nodes, `merge:` has one `left.internalLeft = ...` assignment).
- `MSTNode` does not conform to `NSCopying` — not strictly immutable, but mutation operations produce new nodes.

**Persistence loading (audited):**
- `MSTPersistence.loadNodeWithCID:` (`MSTPersistence.m:243-345`) is **fully recursive and eager** — it materializes all subtrees immediately.
- Uses `nodeCache` (CID string -> MSTNode) and `levelCache` (CID string -> NSNumber) to prevent duplicate loading.
- The generic MST API supports lazy resolution via `blockProvider` in `deserializeFromCBOR:blockProvider:` and `collectProofNodes:forKey:into:blockProvider:`, but the persistence path does not use this.

**Serialization:**
- `MSTWalker` supports ordered traversal and diffing.
- Sync 1.1 streamable CAR ordering is implemented by a flag-gated pre-order traversal (`enumerateStreamableNode...`).
- `RepoCommit.m` computes its own CID separately from the MST root CID. Commit flow: compute MST root CID on demand → serialize MST root block → create/sign commit with MST root CID → compute commit CID.

### 1.2 SQLite / Storage Layer (Audited)

**Files:** `PDSDatabase.{h,m}`, `PDSDatabase+Transactions.m`, `PDSSchemaManager.{h,m}`, `ATProtoDatabaseUtilities.m`, `PDSMigrationManager.m`, `ActorStore.m`, `ServiceDatabases.m`, `Schema.m`, `PDSSpaceStore.m`

**PRAGMA settings (current):**
- `journal_mode=WAL`, `synchronous=NORMAL`, `temp_store=MEMORY` — good baseline.
- `page_size=65536` — larger than default (4096), good for larger databases.
- `cache_size=64` (debug) / `65536` (release) — release is well-tuned.
- `mmap_size=4194304` (debug, ~4MB) / `268435456` (release, ~256MB) — reasonable for read-heavy paths.
- `foreign_keys=ON` — enabled in `ATProtoDatabaseUtilities.m`.
- `wal_autocheckpoint` and `journal_size_limit` are configurable but not audited for optimal values.
- `ServiceDatabases.m` uses `cache_size=-32000` (~32MB) — different from actor store settings.

**WITHOUT ROWID (audited):**
- **Zero tables use `WITHOUT ROWID`** anywhere in the codebase.
- 14+ tables with composite primary keys are candidates (see §3.1).

**Transaction batching (audited):**
- `PDSDatabase+Transactions.m` wraps work in `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK`.
- Uses `SAVEPOINT`s for nested transactions.
- `ActorStore.m` forwards its transactional API to `PDSDatabase`.
- `putBlocks:` and `putRecords:` batch multiple writes inside one transaction.
- `PDSRepositoryService.m` and `PDSRecordService.m` both persist multiple blocks in a single transaction.
- **Batch transactions are already implemented.**

**Block deduplication (audited):**
- `ActorStore.m` uses `INSERT OR REPLACE INTO ipld_blocks (...)`.
- Upstream code also dedupes in memory with CID sets before persisting.
- **`INSERT OR REPLACE` is wrong for immutable blocks** — it deletes and re-inserts the row, firing triggers and wasting I/O. Should be `INSERT OR IGNORE` (see §5.1).

### 1.3 Other Subsystems

- **SearchIndexService** (`Garazyk/Sources/AppView/Services/SearchIndexService.m`): FTS5-based search with BM25 ranking.
- **Mikrus** (`Garazyk/Sources/Mikrus/MikrusDatabase.m`): Link extraction + indexed queries, pooled SQLite, composite indexes.
- **Beskid** (`Garazyk/Sources/Beskid/BeskidDatabase.m`): TTL-based edge/identity cache, pooled SQLite.
- **FirehoseCARBuilder** (`Garazyk/Sources/Sync/Firehose/FirehoseCARBuilder.m`): CID dedup, revision block lists, MST fallback traversal.

### 1.4 Benchmarking

- `ATProtoDatabaseUtilities` defines tuned SQLite configs for actor stores, service DBs, and bulk reads.
- Scenario benchmarks: repo format fetch performance (scenario 28), burst-load resilience (scenario 10).
- The old `test_performance.sh` delegates to scenario 10.

---

## 2. MST-Specific Optimizations

### 2.1 Dirty-Flag CID Invalidation

**Status: ALREADY DONE (no action needed)**

**Source:** Bluesky `@atproto/repo` MST implementation (`outdatedPointer` pattern) [2].

**Original concern:** Mutations might recompute CIDs (SHA-256 hash of canonical CBOR) on every step along the path, wasting work on intermediate nodes.

**Audit finding:** The MST implementation already defers CID computation. The `getCID:` method (`MST.m:227-241`) checks a per-call cache, then `originalCID`, then falls back to serialization + hashing. Mutations (`addRecursive:`, `deleteRecursive:`, `split:`, `merge:`) create new `MSTNode` objects and never call `getCID:` or `computeHash:` during the recursion. The `setNodeHash:` setter is a no-op.

The Bluesky reference uses an explicit `outdatedPointer` dirty flag because it mutates nodes in place. Garazyk doesn't need this because mutations produce new node objects — the original nodes retain their `originalCID`/`originalCBOR` naturally.

**Reference:** <https://github.com/bluesky-social/atproto/tree/main/packages/repo/src/mst>

### 2.2 Lazy Subtree Hydration in Persistence (High Value)

**Source:** Bluesky `@atproto/repo` lazy loading pattern (`MST.load()` creates placeholder with `entries: null`) [2]; sparse Merkle tree lazy nodes [7, 8].

**Problem:** `MSTPersistence.loadNodeWithCID:` (`MSTPersistence.m:243-345`) is **fully recursive and eager** — it materializes all subtrees immediately when loading a repo. For large repos (thousands of records), this loads every node into memory even if most are never accessed.

The generic MST API already supports lazy resolution via `blockProvider` in `deserializeFromCBOR:blockProvider:` and `collectProofNodes:forKey:into:blockProvider:` — but the persistence path doesn't use it.

**Technique:** Replace the eager recursive `loadNodeWithCID:` with a lazy loader that:
1. Materializes the root node only.
2. Stores child CIDs as unresolved references (`treeCID`, `leftCID`).
3. Hydrates child nodes on demand when accessed (via `blockProvider` callback to the DB).
4. Uses a bounded LRU cache keyed by CID to prevent re-loading.

**Implementation path:**
- `MSTPersistence` already has `nodeCache` and `levelCache` — extend these to support lazy hydration.
- The `blockProvider` callback pattern already exists in the MST API — wire it to the DB block fetch.
- Prefetch children of the current node during traversal to hide latency.

**Trade-offs:** First access to a cold subtree is slower (cache miss). Mitigated by prefetching during traversal. Memory usage drops significantly for large repos since most nodes are never touched.

**Reference:** <https://github.com/bluesky-social/atproto/tree/main/packages/repo/src/mst> — `MST.load()` pattern

### 2.3 Copy-on-Write Node Immutability

**Status: MOSTLY DONE (minor cleanup possible)**

**Source:** Bluesky `@atproto/repo` immutable update pattern [2]; Cosmos IAVL version-aware caching [9].

**Audit finding:** Mutations are already mostly COW — `split:`, `addRecursive:`, `deleteRecursive:`, `merge:` all create new `MSTNode` objects. A few in-place writes exist:
- `deserializeNodeFromCBOR:blockProvider:` sets `node.internalLeft` and `entry.internalTree` (cache hydration).
- `collectProofNodes:` lazily caches loaded subtrees into existing nodes.
- `merge:` has one branch that assigns `left.internalLeft = ...`.

These in-place writes are for cache hydration, not for mutation operations. The mutation path is clean COW. The main benefit of full immutability would be snapshot isolation for concurrent read-during-write (firehose/CAR generation during a commit), but the current serial dispatch queue in `PDSDatabase` likely prevents this scenario.

**Action:** Low priority. If concurrent read-during-write becomes needed, make the cache hydration fields use a separate mutable wrapper or atomic swap.

**Reference:** <https://github.com/bluesky-social/atproto/tree/main/packages/repo/src/mst>

### 2.4 Extension Nodes for Single-Child Chains (Low Value)

**Source:** Merkle Patricia Trie (Ethereum); sparse Merkle tree extension nodes [7, 8].

**Problem:** Deep trees with sparse key distributions waste levels on single-child nodes.

**Technique:** When a subtree has only one child, compress the path into an extension node that stores the key prefix and skips intermediate levels.

**Trade-offs:** Adds complexity to insert/delete/split logic. Changes the CBOR encoding format (must remain spec-compatible with AT Protocol). The SHA-256 depth assignment already bounds fanout, so this may be unnecessary.

**Action:** Only if profiling shows pathological tree shapes. Profile first.

**Reference:** <https://github.com/nervosnetwork/sparse-merkle-tree>

### 2.5 Batch / Multi-Leaf Proofs (Low Value, Future)

**Source:** Sparse Merkle tree batch proofs [7, 8].

**Technique:** Prove multiple leaves in a single proof to amortize sibling hash costs.

**Trade-offs:** Not needed unless serving proofs to external verifiers. AT Protocol sync uses CAR files, not explicit proofs.

**Action:** Future. Only if a proof-serving API is built.

**Reference:** <https://github.com/pokt-network/smt>

### 2.6 Preorder CAR Streaming (In Progress)

**Source:** Sync v1.1 proposal [3]; AT Protocol sync specification [18].

**Status:** Already in progress. `MSTPreorderTests.m` and the flag-gated `enumerateStreamableNode...` method are underway.

**Spec requirement:** Emit commit first, then MST nodes in preorder, then records. This lets consumers process repo CARs incrementally with low memory overhead.

**Implementation note:** Ensure the preorder traversal is **iterative** (not recursive) to avoid stack overflow on deep trees. Use an explicit stack data structure.

**Reference:** <https://github.com/bluesky-social/proposals/tree/main/0006-sync-iteration>

---

## 3. SQLite / Storage Optimizations

### 3.1 `WITHOUT ROWID` for Natural-Key Tables (High Value)

**Source:** SQLite "Without ROWID Optimization" [13].

**Problem:** Zero tables in the codebase use `WITHOUT ROWID`. Tables with composite primary keys maintain a redundant rowid B-tree plus a secondary index, wasting ~20-30% storage and doubling B-tree lookups for PK queries.

**Audit finding — candidate tables:**

| Table | File | Primary Key | Notes |
|------|------|-------------|-------|
| `moderation_set_members` | `PDSSchemaManager.m` | `(set_id, did)` | |
| `moderation_subjects` | `PDSSchemaManager.m` | `(subject_did, subject_type)` | |
| `record_tombstones` | `PDSSchemaManager.m` | `(uri, rev)` | |
| `conversation_members` | `Schema.m` | `(convo_id, member_did)` | |
| `message_reactions` | `Schema.m` | `(message_id, actor_did, emoji)` | |
| `group_members` | `Schema.m` | `(group_uri, member_did)` | |
| `group_message_reactions` | `Schema.m` | `(message_id, actor_did, emoji)` | |
| `collection_membership` | `Schema.m` | `(did, collection)` | |
| `space_member` | `PDSSpaceStore.m` | `(space, did)` | |
| `space_repo` | `PDSSpaceStore.m` | `(space, author_did)` | |
| `space_record` | `PDSSpaceStore.m` | `(space, author_did, collection, rkey)` | 4-column PK |
| `space_record_oplog` | `PDSSpaceStore.m` | `(space, author_did, rev, idx)` | 4-column PK |
| `space_writer` | `PDSSpaceStore.m` | `(space, did)` | |
| `space_credential_recipient` | `PDSSpaceStore.m` | `(space, service_did)` | |
| `space_blob` | `PDSSpaceStore.m` | `(space, author_did, cid)` | |

**Benefits per SQLite docs [13]:**
- ~50% space savings for small rows with non-integer PKs.
- Close to 2x faster for PK lookups (single B-tree instead of two).
- Sequential scans in PK order (useful for `listRecords` by collection, `collection_membership` by did).

**Caveats per SQLite docs [13]:**
- No `AUTOINCREMENT`.
- No `sqlite3_last_insert_rowid()`.
- No incremental BLOB I/O.
- No `sqlite3_update_hook()` callbacks.
- Requires explicit `PRIMARY KEY` in the table definition.

**Trade-offs:** Can't use rowid-based optimizations. Fine for these use cases — they're keyed by natural composite keys, not surrogate integers.

**Action:** Add a migration to convert these tables to `WITHOUT ROWID`. Test with existing scenario suites. Prioritize `collection_membership` (recently modified per git status) and `space_record` (4-column PK, most wasteful with rowid).

**Reference:** <https://www.sqlite.org/withoutrowid.html>

### 3.2 Covering Indexes for Hot Read Paths (Medium Value)

**Source:** SQLite Query Planner documentation [16].

**Problem:** `listRecords` queries by `(collection, rkey)` but may also need `uri` or `value`. Without a covering index, SQLite must look up the base table row after finding the index entry.

**Technique:** Create composite indexes that include all columns needed by the query, so SQLite can satisfy the query from the index alone (index-only scan).

**Design rules per SQLite docs [16]:**
- Put `=` / `IN` / `IS` predicates first.
- Put range predicates later.
- Add `ORDER BY` columns to avoid a sort.
- Keep indexes narrow — write-heavy systems pay for every extra index.

**Trade-offs:** Additional index storage and write amplification. Only add for queries that are both frequent and benefit from the covering.

**Action:** Profile the top 10 queries by frequency using `EXPLAIN QUERY PLAN`. Add covering indexes for the ones that do point lookups + small projections. Prioritize `listRecords` and `getRecord` paths.

**Reference:** <https://www.sqlite.org/queryplanner.html>

### 3.3 Batch Transaction Discipline

**Status: ALREADY DONE (no action needed)**

**Source:** SQLite WAL documentation [14].

**Audit finding:** `PDSDatabase+Transactions.m` wraps work in `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK` with `SAVEPOINT`s for nested transactions. `ActorStore.m` forwards its transactional API to `PDSDatabase`. `putBlocks:` and `putRecords:` batch multiple writes inside one transaction. `PDSRepositoryService.m` and `PDSRecordService.m` both persist multiple blocks in a single transaction.

**Reference:** <https://www.sqlite.org/wal.html>

### 3.4 PRAGMA Tuning (Low Value)

**Source:** SQLite PRAGMA documentation [15].

**Audit finding — current settings:**

| PRAGMA | Debug | Release | Notes |
|--------|-------|---------|-------|
| `journal_mode` | WAL | WAL | Good [14] |
| `synchronous` | NORMAL | NORMAL | Good for WAL [14] |
| `page_size` | 65536 | 65536 | Larger than default (4096) |
| `cache_size` | 64 | 65536 | Release is well-tuned (~64MB) |
| `mmap_size` | 4MB | 256MB | Reasonable for read-heavy |
| `temp_store` | MEMORY | MEMORY | Good |
| `foreign_keys` | ON | ON | Good |

**Potential improvements:**
- `wal_autocheckpoint`: verify current value. Per SQLite docs [14], default is 1000 pages. For write-heavy workloads, consider tuning this to avoid checkpoint stalls. Consider moving checkpoints to a background thread.
- `cache_size` in `ServiceDatabases.m` is `-32000` (~32MB) — different from actor store settings. Verify this is intentional.

**Reference:** <https://www.sqlite.org/pragma.html>

---

## 4. Sync / Firehose Optimizations

### 4.1 Decouple Ingest from Indexing (Medium Value)

**Source:** AT Protocol sync specification [18]; general event-driven architecture patterns.

**Problem:** If the firehose ingestion path does synchronous indexing (updating AppView tables, search index, etc.), ingest throughput is limited by the slowest indexing operation.

**Technique:** Treat the firehose as an ingestion boundary, not an indexing boundary:
1. **Ingest** commit/identity/sync events quickly — persist raw event + cursor.
2. **Validate** and normalize asynchronously.
3. **Index** downstream data in a separate worker.
4. Apply backpressure when the queue exceeds a threshold.

**Benefits:**
- Backpressure control — fast producer can't overwhelm slow indexer.
- Replayability — resume from checkpoint after crash.
- Resilience to downstream slowness.
- Idempotent indexing for retries.

**Trade-offs:** Eventual consistency between firehose and indexes. Need idempotent indexing.

**Action:** Check whether `FirehoseCARBuilder` or sync ingestion does synchronous indexing. If yes, introduce a durable queue (SQLite table or WAL-like append-only log) between ingest and indexing.

**Reference:** <https://atproto.com/specs/sync>

### 4.2 Operation Inversion for Stateless Sync Validation (Future, Research)

**Source:** Sync v1.1 proposal [3]; firehose prev-CID PR #3449 [4].

**Problem:** Relays/AppViews need the full repo to validate commits.

**Technique:** Include `prevData` and per-op `prev` CIDs in commit metadata. A consumer can validate a commit by inverting its ops against a partial MST. This enables near-stateless sync validation.

**Spec status:** Draft proposal in `bluesky-social/proposals/0006-sync-iteration`. Not yet finalized.

**Trade-offs:** Extra commit metadata. Needs spec adoption.

**Action:** Monitor spec adoption. Not actionable until Sync 1.1 is finalized.

**References:**
- <https://github.com/bluesky-social/proposals/tree/main/0006-sync-iteration>
- <https://github.com/bluesky-social/atproto/pull/3449>

---

## 5. CID / CBOR Optimizations

### 5.1 Block Deduplication: `INSERT OR IGNORE` instead of `INSERT OR REPLACE` (High Value)

**Source:** SQLite ON CONFLICT documentation [17]; IPLD content addressing [25].

**Problem:** `ActorStore.m` currently uses `INSERT OR REPLACE INTO ipld_blocks (...)`. For immutable content-addressed blocks, `REPLACE` is wrong:
- `REPLACE` **deletes** the existing row and **re-inserts** it, even though the content is identical.
- This fires `DELETE` and `INSERT` triggers, rewrites the B-tree page, and appends to the WAL — all wasted work for immutable data.
- The caller already dedupes in memory with CID sets, but the DB-level `REPLACE` still does the delete+insert dance.

**Technique:** Change to `INSERT OR IGNORE INTO ipld_blocks (...)` or `INSERT INTO ipld_blocks (...) ON CONFLICT(cid) DO NOTHING`.

**Why `IGNORE` is correct for blocks:**
- Same CID = same bytes (content addressing [25]). The block is immutable.
- `IGNORE` preserves the existing row — no delete, no trigger, no B-tree rewrite.
- `REPLACE` is for mutable data where you want to overwrite. Blocks are not mutable.

**Benefits:**
- Eliminates unnecessary B-tree page rewrites for duplicate blocks.
- Avoids trigger side effects on immutable data.
- Reduces WAL append volume.
- Per SQLite docs [17], `IGNORE` is cheaper than `REPLACE` because it doesn't delete first.

**Trade-offs:** None. Blocks are immutable by definition.

**Action:** Change `INSERT OR REPLACE` to `INSERT OR IGNORE` in `ActorStore.m` for `ipld_blocks` inserts. Verify no triggers depend on the `REPLACE` behavior.

**References:**
- <https://www.sqlite.org/lang_conflict.html>
- <https://ipld.io/docs/data-model/content-addressing/>

### 5.2 DAG-CBOR Encoding Cache (Low Value)

**Source:** AT Protocol data model specification [19]; python-libipld optimization notes [24].

**Problem:** If the same node is serialized multiple times (e.g., during diffing, proof generation, and CAR building), the CBOR encoding is redundant.

**Audit finding:** The MST already caches CBOR via `originalCBOR` — deserialized nodes return the original bytes without re-encoding. New nodes created by mutations don't have `originalCBOR`, but they also don't get serialized repeatedly in practice (the commit path serializes once).

**Technique:** Cache the CBOR bytes alongside the CID for newly created nodes. Avoids re-encoding if the same new node is read multiple times before persistence.

**Trade-offs:** Memory. The `originalCBOR` pattern already handles the common case. Only beneficial if new nodes are read multiple times before being persisted.

**Action:** Low priority. The existing `originalCBOR`/`originalCID` mechanism already covers the common case. Only add caching for new nodes if profiling shows repeated encoding.

**References:**
- <https://atproto.com/specs/data-models>
- <https://github.com/MarshalX/python-libipld>

---

## 6. Identity / Auth Optimizations

### 6.1 DID / Handle Resolution Caching (Medium Value)

**Source:** AT Protocol identity specification [20]; Bluesky PDS config [23].

**Problem:** DID and handle resolution involves DNS or HTTPS lookups. Without caching, every operation that needs identity verification incurs network latency.

**Bluesky reference values [23]:**
- `cacheStaleTTL` = **1 hour** — serve from cache when fresh, allow stale use temporarily.
- `cacheMaxTTL` = **1 day** — maximum lifetime, bound so stale identity data doesn't linger.
- Stale-while-revalidate pattern: serve from cache, refresh in background, bust on verification failure.

**Audit finding:** `Beskid` (`Garazyk/Sources/Beskid/BeskidDatabase.m`) already provides a TTL-based edge/identity cache with pooled SQLite access. Need to verify:
1. Whether `Beskid` covers all hot identity resolution paths (DID doc lookup, handle→DID resolution).
2. Whether `Beskid`'s TTLs match the Bluesky reference (1h stale, 1d max).
3. Whether identity update events (from the firehose) trigger cache invalidation.

**Implementation notes:**
- Cache lookup results, not trust decisions. A cached DID document is safe; a cached "this user is authorized" is not.
- Treat sync/identity update events as invalidation triggers.
- Keep TTLs short enough to follow identity changes, long enough to reduce load.

**Trade-offs:** Stale cache entries can cause transient failures. Mitigated by busting on verification failure.

**Action:** Verify `Beskid` coverage of the hot identity resolution paths. Compare TTLs to Bluesky defaults (1h/1d). Add firehose invalidation if missing.

**References:**
- <https://atproto.com/specs/identity>
- <https://github.com/bluesky-social/atproto/blob/main/packages/pds/src/config/config.ts>

### 6.2 JWT Validation Caching (Low Value)

**Source:** AT Protocol OAuth specification [21].

**Problem:** JWT validation involves signature verification, which is computationally expensive.

**Technique:** Cache derived validation results (e.g., `token -> claims` mapping) with strict invalidation rules. Do not cache the trust decision itself.

**Trade-offs:** OAuth tokens are short-lived (15min access, 7day refresh). Cache window must be narrow. Risk of serving a revoked token.

**Action:** Low priority. Only if profiling shows JWT validation as a bottleneck.

**Reference:** <https://atproto.com/specs/oauth>

---

## 7. Prioritized Summary

Reordered by actual value based on code audit findings. Items marked "DONE" were investigated and found to be already implemented.

| # | Optimization | Value | Effort | Status |
|---|---|---|---|---|
| 3.1 | `WITHOUT ROWID` for 14+ composite-PK tables | **High** | Low | Schema migration needed |
| 5.1 | `INSERT OR IGNORE` for `ipld_blocks` | **High** | Low | One-line change in `ActorStore.m` |
| 2.2 | Lazy subtree hydration in `MSTPersistence` | **High** | Medium | Replace eager recursive load |
| 3.2 | Covering indexes for hot read paths | Medium | Low | Profile with `EXPLAIN QUERY PLAN` |
| 4.1 | Decouple ingest from indexing | Medium | Medium | Architectural |
| 6.1 | DID/handle resolution caching | Medium | Low | Verify `Beskid` coverage + TTLs |
| 2.6 | Preorder CAR streaming | — | — | In progress |
| 3.4 | PRAGMA tuning (wal_autocheckpoint) | Low | Low | Verify current values |
| 2.4 | Extension nodes | Low | High | Profile first |
| 2.5 | Batch/multi-leaf proofs | Low | Medium | Future |
| 4.2 | Operation inversion sync | Low | High | Research stage |
| 5.2 | DAG-CBOR encoding cache | Low | Low | `originalCBOR` already covers common case |
| 6.2 | JWT validation caching | Low | Low | Only if profiling shows bottleneck |
| 2.1 | Dirty-flag CID invalidation | — | — | **DONE** — already deferred via `originalCID` |
| 2.3 | Copy-on-write node immmutability | — | — | **DONE** — mutations already produce new nodes |
| 3.3 | Batch transaction discipline | — | — | **DONE** — `PDSDatabase+Transactions.m` |

### Recommended First Steps

1. **`INSERT OR IGNORE` for `ipld_blocks`** (§5.1) — one-line change, immediate I/O reduction on every commit with duplicate blocks.

2. **`WITHOUT ROWID` migration** (§3.1) — start with `collection_membership` (recently modified per git status) and `space_record` (4-column PK, most wasteful). Add a migration in `PDSMigrationManager.m`, test with scenario suites.

3. **Lazy subtree hydration** (§2.2) — replace the eager recursive `loadNodeWithCID:` in `MSTPersistence.m` with a lazy loader using the existing `blockProvider` pattern. Wire the `blockProvider` callback to the DB block fetch. Extend the existing `nodeCache`/`levelCache` to support lazy hydration with bounded LRU eviction.

4. **Profile hot queries** (§3.2) — run `EXPLAIN QUERY PLAN` on the top 10 queries by frequency. Identify covering index candidates for `listRecords` and `getRecord`.

5. **Verify `Beskid` coverage** (§6.1) — check that all hot identity resolution paths go through `Beskid`. Compare TTLs to Bluesky defaults (1h stale, 1d max). Add firehose invalidation if missing.
