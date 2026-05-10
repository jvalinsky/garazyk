# Concurrency & Scalability Research for Bluesky-Scale ATProto Services

**Date**: 2026-05-10
**Scope**: Architecture analysis, bottleneck identification, data structure research, and phased implementation plan for scaling Garazyk to production Bluesky throughput (2000+ events/sec firehose, 1000+ writes/sec PDS).

---

## 1. Current Architecture

### 1.1 PDS (kaszlak) — HTTP Server

- **Concurrency model**: GCD-based. `dispatch_semaphore_t` caps concurrent requests at **64** (`kMaxConcurrentRequests`). Each request dispatched to a global concurrent queue; handler runs on a GCD thread pool thread.
- **Per-connection state**: Each TCP connection gets its own serial `transportQueue` and a `HttpConnectionIOCoordinator` (sans-I/O architecture). Response queue with 10MB high-water mark (backpressure on output).
- **Buffer pooling**: `HttpBufferPool` — slab allocator with size classes (256, 1024, 4096, 16384 bytes). Recycles `HttpRequest`/`HttpResponse` objects. Thread-safe via serial queue. Max 64 objects per pool.
- **Route lookup**: `HttpRouteTrie` — trie-based O(k) path matching. Not a bottleneck.

### 1.2 PDS — Write Path

- **Write serialization**: Single serial `writeQueue` for ALL writes across ALL DIDs. This is a **critical bottleneck** — every `createRecord`, `applyWrites`, `deleteRecord` goes through one queue. The queue was made explicit (previously implicit via `transactWithDid:`) with `dispatch_sync` + diagnostic timing logs.
- **MST cache**: `mstCacheByDid` dictionary protected by serial `mstCacheQueue`. Per-DID MST loaded/cached on first write.
- **MST operations**: The MST itself is **not thread-safe** — it's a single-threaded tree with `put`/`delete`/`get` operations. Each write: load MST → apply mutation → recompute hashes → persist blocks → update repo root.
- **Database**: `PDSConnectionPool` — SQLite connection pool (default min 2, max 10). WAL mode, NORMAL sync. `busyTimeout` 5000ms.

### 1.3 Relay (zuk)

- Subscribes to PDS firehose WebSocket. Re-broadcasts to subscribers.
- Per-PDS connection with configurable concurrency.

### 1.4 AppView (syrena) — Ingest Pipeline

- **Ingest engine**: Serial `eventQueue` processes all firehose events. Per-relay `AppViewRelayConnection` objects.
- **Backpressure**: `maxLagForBackpressure = 50000` (seq gap). When lag exceeds this, the engine should apply backpressure — but the current implementation is a threshold without a concrete flow-control mechanism.
- **Checkpointing**: Every 5 seconds, cursor persisted to DB on serial `checkpointQueue`.
- **Idempotency**: Events deduplicated by `did+rev+cid` before dispatching to indexers.
- **Per-op dispatch**: The `didReceiveCommit:` delegate iterates over individual ops within each event, dispatching to indexers, firing hooks, and expanding partial mode per-op.
- **Hook registry**: `AppViewIndexHookRegistry` wired in `AppViewRuntime.m`. `SearchIndexService` registered as internal hook for real-time FTS5 updates.
- **Write proxy**: `AppViewWriteProxy` wired in `AppViewRuntime.m` with DID resolution via `DIDPLCResolver`. Docker env `PDS_WRITE_PROXY_OVERRIDE` and `APPVIEW_PDS_URL` for bridge networking.
- **Backfill**: `AppViewBackfillWorker` checks `APPVIEW_PDS_URL` env override. Passes `rkey` to indexers.

### 1.5 Rate Limiter

- SQLite-backed sliding window. Per-DID (5000/hr), per-IP (100/min), per-blob (50/hr). Thread-safe via SQLite serialization.

---

## 2. Identified Bottlenecks at Scale

### 2.1 Single Global Write Queue (CRITICAL)

**Current**: One serial `dispatch_queue_t` serializes ALL repo writes across all DIDs. Made explicit in `PDSRecordService.m` with `dispatch_sync(self.writeQueue, ...)` wrapping `putRecord`, `deleteRecord`, and `applyWrites`. Diagnostic timing logs show queue wait times.

**Problem**: At 200 writes/sec from 100 different accounts, all 200 writes queue on a single queue. The queue becomes the bottleneck, not the database or MST.

**Bluesky reference**: Indigo's relay uses 40 concurrent workers per upstream host. The PDS write path needs similar parallelism.

### 2.2 MST Is Not Thread-Safe (CRITICAL)

**Current**: MST `put`/`delete` mutate the tree in-place. No concurrent access protection beyond the write queue.

**Problem**: If we parallelize writes per-DID, we need per-DID MST instances or a concurrent MST. The MST is a persistent data structure (immutable previous versions) — this is actually a good fit for copy-on-write.

### 2.3 SQLite Single-Writer Constraint (MEDIUM)

**Current**: WAL mode allows concurrent reads but only one writer at a time.

**Problem**: At 1000+ writes/sec, the single-writer bottleneck manifests as `SQLITE_BUSY` waits. Connection pool helps with reads but not writes.

**Mitigation**: Batch writes into larger transactions (amortize fsync), tune WAL checkpointing, increase `busy_timeout`.

### 2.4 No Backpressure on AppView Ingest (MEDIUM)

**Current**: `maxLagForBackpressure = 50000` is defined but there's no concrete flow-control mechanism. The relay pushes events as fast as it can; the AppView ingests on a serial queue.

**Problem**: If the AppView falls behind (e.g., slow DB writes), the relay keeps pushing. Memory grows unbounded as events queue up.

### 2.5 HTTP Concurrency Semaphore Caps at 64 (LOW-MEDIUM)

**Current**: `kMaxConcurrentRequests = 64`. Reasonable default but may need tuning for production.

**Problem**: At 3000 events/sec with mixed read/write, 64 concurrent handlers may not be enough. But too many causes thread contention.

### 2.6 Rate Limiter Uses SQLite (LOW)

**Current**: Every rate limit check hits SQLite. At high throughput, this adds latency.

**Problem**: SQLite serialization for rate limit checks competes with data writes for the same WAL lock.

---

## 3. Research Findings

### 3.1 Per-DID Write Queues (Actor Model Pattern)

**Key insight**: ATProto repo writes are naturally partitioned by DID. Two different accounts never share mutable state. This is the **actor model** — each DID is an actor with its own mailbox.

**Implementation approach**:
1. Replace the single global `writeQueue` with a **per-DID serial queue** (or dispatch_queue per DID)
2. Use a `NSMutableDictionary<NSString *, dispatch_queue_t>` protected by a concurrent read/serial write pattern
3. Each queue processes writes for exactly one DID — no cross-DID contention
4. Global concurrency limit via a counting semaphore (e.g., max 32 concurrent DID-writers)

**Reference**: This is exactly how Akka actors work — each actor has a mailbox, processes messages sequentially, but many actors run concurrently. The Indigo relay uses 40 goroutines per upstream host, which is a similar partitioning strategy.

**ObjC sketch**:
```objc
@interface PDSPerDidWriteDispatcher : NSObject
- (void)dispatchWriteForDid:(NSString *)did
                    block:(void(^)(void))writeBlock;
@end

// Internally:
// - concurrent queue reads from didQueueMap
// - if no queue for DID, create one on serial creation queue
// - dispatch_async to per-DID queue
// - counting semaphore limits total concurrent writers
```

**Risk**: Queue proliferation (thousands of DIDs = thousands of queues). Mitigation: evict idle queues after timeout, or use a work-stealing thread pool.

### 3.2 MPSC Queue for Firehose Ingest

**Research finding**: Lock-free MPSC (Multi-Producer Single-Consumer) queues are the standard pattern for high-throughput event ingestion where multiple producers (relay connections) feed a single consumer (ingest engine).

**Key designs from research**:

#### RingMPSC (boonzy00/ringmpsc, Zig)
- Per-producer SPSC ring buffers, consumer polls all rings
- Zero cross-producer contention
- Achieves ~180 billion messages/sec (u32) on commodity hardware
- Key techniques: cache-line alignment (128B), batch consumption, adaptive backoff (spin → yield → park)
- NUMA-aware allocation: per-ring memory with producer-local binding
- Zero-copy design via reserve/commit pattern
- Linux-only (futex, eventfd, epoll) — not directly portable to macOS

#### SCQ (Nikolaev, DISC 2019)
- Scalable Circular Queue using fetch-and-add (FAA) instead of CAS
- ABA-safe, standalone, memory-efficient
- Only needs single-width CAS — very portable
- C implementation available at rusnikola/lfqueue
- MPMC design (can be specialized to MPSC)

#### wCQ (Nikolaev, SPAA 2022)
- Wait-free version of SCQ with bounded memory
- Best for backpressure-sensitive scenarios
- Double-width CAS variant (x86-64 specific)

#### Application to Garazyk
The AppView ingest engine currently uses a serial GCD queue. Replacing with a per-relay MPSC ring buffer would:
1. Eliminate cross-relay contention (each relay writes to its own ring)
2. Enable batch consumption (process N events per dequeue, amortize DB write overhead)
3. Provide natural backpressure: ring full → producer blocks or drops

**ObjC implementation**: C-compatible MPSC queue (e.g., based on Dmitry Vyukov's design or SCQ) wrapped in an ObjC interface. The `__atomic` builtins in Clang provide the necessary CAS/FAA primitives.

### 3.3 Concurrent MST with Copy-on-Write

**Research finding**: The original MST paper (Auvolat et al., SRDS 2019) emphasizes that MSTs are **persistent data structures** — previous versions remain valid after mutation. This is a natural fit for copy-on-write.

**The Solana Concurrent Merkle Tree** approach:
- Fine-grained per-node locking (or optimistic concurrency)
- Incremental hash recomputation (only changed subtree)
- Batching: group multiple updates, amortize tree traversal and hashing
- Version control: maintain multiple root versions for concurrent reads

**Application to Garazyk**:
1. **Copy-on-write MST**: When a write mutates the tree, create new nodes only for the changed path. Old nodes remain immutable and can be read concurrently.
2. **Per-DID MST with atomic swap**: Each DID's MST is an `atomic<MST*>` — writers create a new version, readers always see a consistent snapshot.
3. **Batch MST updates**: Instead of one `put` per record, batch N records into a single MST update. This amortizes hash recomputation and is especially effective for `applyWrites`.

**ObjC sketch**:
```objc
@interface MSTSnapshot : NSObject
@property (nonatomic, strong, readonly) MSTNode *root;
@property (nonatomic, strong, readonly) CID *rootCID;
@end

@interface MSTAtomicReference : NSObject
- (MSTSnapshot *)currentSnapshot;  // lock-free read
- (MSTSnapshot *)applyMutations:(NSArray<MSTMutation *> *)mutations;  // CAS swap
@end
```

### 3.4 SQLite Write Batching & WAL Tuning

**Research findings**:

#### WAL Mode Performance (Gaffney et al., VLDB 2022)
- WAL mode is 10x faster than DELETE mode for write-heavy workloads
- SQLite-WAL reaches 10,000 TPS on cloud hardware
- WAL mode allows concurrent readers with a single writer

#### WAL Size & Checkpointing (Jeong et al., APSys 2017)
- Larger WAL → fewer checkpoints → higher throughput
- 5x performance difference between WAL sizes of 64KB and 1MB
- Default autocheckpoint at 1000 pages; increasing to 5000+ pages reduces checkpoint frequency
- No benefit beyond 1MB WAL size (checkpoint triggered every 1000 pages regardless)
- `synchronous=NORMAL` is 6x faster than FULL with acceptable safety

#### ALEX (2026) — Adaptive Log-Embedded Extent Layer
- Coalesces scattered 4KB page updates into sequential, page-aligned extents
- Reduces fsync count significantly (constant small number per run vs. tens of thousands)
- Improves p95-p99 write latency
- Zero-copy design, preserves full SQLite compatibility
- VFS-level extension — no SQLite internal modifications needed

#### Application to Garazyk
1. **Write batching**: Accumulate per-DID writes in a buffer, flush as a single transaction every N ms or M records. This is the single biggest throughput win.
2. **WAL tuning**: Increase `PRAGMA wal_autocheckpoint` from 1000 to 5000-10000 pages. Set `PRAGMA journal_size_limit` to at least 16MB.
3. **Connection pool sizing**: Increase max connections from 10 to match concurrent DID writers (e.g., 32).
4. **Prepared statements**: Cache prepared statements per connection to avoid recompilation.
5. **Separate rate-limiter DB**: Move rate limit tracking to a separate SQLite file (or in-memory) to avoid WAL contention with data writes.

### 3.5 Backpressure Architecture

#### Reactive Streams Specification
- Receiver explicitly requests N items (pull-based). Sender may only send up to the requested amount.
- Backpressure is integral: the recipient is only sent as much data as it can process or buffer.
- Non-blocking communication across asynchronous boundaries.

#### ATOM — AT Protocol Over MOQ Transport (IETF draft-nandakumar-atproto-atom-00)
- Proposes QUIC-based transport for ATProto firehose
- MOQT publish/subscribe model maps naturally to ATProto event streams
- Group-based caching: late-joining subscribers receive most recent group immediately
- Group boundaries serve as natural replay points (cursor semantics → Group ID + Object ID)
- Hierarchical relay topologies reduce origin load via regional caching
- Addresses current WebSocket scaling limitations (linear connection scaling, custom replay logic)

#### Indigo Tap — Firehose Sync Tool
- Ack-based delivery with backpressure on pending IDs channel
- Resync buffer with exponential backoff (1 minute → 1 hour max)
- Configurable parallelism: 10 firehose processors, 5 resync workers, 1 outbox worker
- Live events are synchronization barriers: all prior events must complete before live event delivery
- Historical events can be sent concurrently with each other
- Automatic reconnect with exponential backoff; cursor saved every 1 second

#### Application to Garazyk
1. **AppView ingest backpressure**: When `lag > maxLagForBackpressure`, signal the relay client to pause reading (WebSocket flow control). Resume when lag drops below threshold.
2. **PDS write backpressure**: When write queue depth exceeds high-water mark, return 503 Service Unavailable or 429 Too Many Requests. Client should retry with exponential backoff.
3. **Relay subscriber backpressure**: Per-subscriber output buffer with high-water mark. If subscriber can't keep up, drop and force reconnect from cursor.
4. **Cascading backpressure**: PDS → Relay → AppView. Each layer signals upstream when overloaded.

### 3.6 Object Pooling & Memory Management

**Current**: `HttpBufferPool` already implements slab allocation for HTTP objects. Good foundation.

**Needed additions**:
1. **MST node pool**: MST nodes are short-lived during writes. Pool them to reduce allocation pressure.
2. **CBOR encode/decode buffers**: Firehose events require CBOR serialization. Pre-allocate encoding buffers.
3. **Firehose event pool**: Reuse `FirehoseCommitEvent` objects instead of allocating per-event.
4. **Autorelease pool discipline**: Every handler block should wrap work in `@autoreleasepool` to prevent temporary object accumulation.

### 3.7 Event Sourcing & CQRS for AppView

**Research finding**: The ATProto architecture is inherently event-sourced:
- **Event log**: The firehose IS the event log. Every state change is a signed commit event.
- **CQRS**: The PDS is the write model (repo operations). The AppView is the read model (materialized views). They're already separated — this is CQRS by design.

**What's missing**: The AppView doesn't currently leverage the CQRS separation properly:
1. **Write path optimization**: AppView ingest should batch DB writes (accumulate N events, flush in one transaction).
2. **Read path optimization**: AppView queries should hit materialized index tables, not recompute from events.
3. **Snapshot + event replay**: For catch-up after disconnection, load a snapshot then replay from cursor (instead of reprocessing everything).

---

## 4. Phased Implementation Plan

### Phase 1: Per-DID Write Queues (highest impact)

**Files to modify**:
- `Garazyk/Sources/Services/PDS/PDSRecordService.m` — replace single `writeQueue` with per-DID dispatcher
- New file: `Garazyk/Sources/Core/PDSPerDidWriteDispatcher.h/.m`

**Design**:
- `PDSPerDidWriteDispatcher` manages per-DID serial queues
- Global counting semaphore limits total concurrent writers (e.g., 32)
- Idle queue eviction after 60s timeout
- Each DID's writes are still serialized (ATProto requirement: repo operations must be sequential per-repo)

### Phase 2: MST Copy-on-Write + Atomic Snapshots

**Files to modify**:
- `Garazyk/Sources/Repository/MST.h/.m` — add snapshot/atomic-swap support
- `Garazyk/Sources/Core/MSTCacheManager.h/.m` — use atomic references
- `Garazyk/Sources/Services/PDS/PDSRecordService.m` — use new MST API

**Design**:
- `MSTSnapshot` holds immutable root + CID
- `MSTAtomicReference` provides lock-free reads + CAS-based writes
- Writers: create new snapshot from current, apply mutations, CAS swap
- Readers: always get a consistent snapshot via `currentSnapshot`
- Batch MST mutations: `applyMutations:` takes an array, applies all, recomputes hashes once

### Phase 3: SQLite Write Batching

**Files to modify**:
- `Garazyk/Sources/Database/Pool/PDSConnectionPool.h/.m` — increase pool size, add WAL tuning
- `Garazyk/Sources/Services/PDS/PDSRecordService.m` — batch writes per transaction
- `Garazyk/Sources/Network/RateLimiter.m` — move to separate DB or in-memory

**Design**:
- Per-DID write buffer: accumulate writes for 50ms or 10 records, flush as one transaction
- WAL autocheckpoint: increase to 5000 pages
- Journal size limit: 16MB
- Connection pool: max 32 connections
- Rate limiter: separate SQLite file or in-memory dictionary

### Phase 4: AppView Ingest Backpressure

**Files to modify**:
- `Garazyk/Sources/AppView/Server/Ingest/AppViewIngestEngine.m` — add concrete backpressure mechanism
- `Garazyk/Sources/Sync/Relay/RelayClient.h/.m` — add pause/resume methods

**Design**:
- When `lag > maxLagForBackpressure`, call `[relayClient pauseReading]`
- When `lag < maxLagForBackpressure * 0.5`, call `[relayClient resumeReading]`
- WebSocket flow control: stop reading from socket (TCP backpressure propagates to relay)
- Batch DB writes: accumulate N events, flush in one transaction

### Phase 5: MPSC Queue for Firehose

**Files to modify**:
- New file: `Garazyk/Sources/Core/PDSMPSCQueue.h/.m` — C-based lock-free MPSC queue
- `Garazyk/Sources/AppView/Server/Ingest/AppViewIngestEngine.m` — use MPSC queue

**Design**:
- Based on Dmitry Vyukov's MPSC intrusive queue (used in Go's runtime scheduler)
- Per-relay producer: each `AppViewRelayConnection` enqueues to its own slot
- Single consumer: ingest engine drains all slots in batch
- Cache-line aligned (128B) to prevent false sharing
- Bounded capacity with backpressure: ring full → producer blocks

### Phase 6: Object Pooling & Memory Optimization

**Files to modify**:
- `Garazyk/Sources/Network/HttpBufferPool.h/.m` — extend to MST nodes, CBOR buffers, firehose events
- `Garazyk/Sources/Repository/MST.m` — use node pool
- `Garazyk/Sources/Sync/Firehose/` — event object pooling

---

## 5. Key References

| # | Reference | Key Takeaway |
|---|-----------|-------------|
| 1 | Auvolat et al., "Merkle Search Trees: Efficient State-Based CRDTs in Open Networks" (SRDS 2019) | MST is a persistent data structure — natural fit for copy-on-write. 66% bandwidth reduction vs vector clocks. |
| 2 | Nikolaev, "A Scalable, Portable, and Memory-Efficient Lock-Free FIFO Queue" (DISC 2019) | FAA-based MPMC queue, ABA-safe, standalone. C implementation at rusnikola/lfqueue. |
| 3 | Nikolaev, "A Fast Wait-Free Queue with Bounded Memory Usage" (SPAA 2022) | Wait-free SCQ variant (wCQ). Best for backpressure-sensitive scenarios. |
| 4 | boonzy00/ringmpsc | Per-producer SPSC rings, ~180B msgs/sec. Cache-line alignment, batch consumption, NUMA-aware. |
| 5 | Gaffney et al., "SQLite: Past, Present, and Future" (VLDB 2022) | WAL mode 10x faster than DELETE. 10k TPS achievable. |
| 6 | Jeong et al., "The Dangers and Complexities of SQLite Benchmarking" (APSys 2017) | Single parameter → 11.8x perf difference. WAL size: 5x between 64KB and 1MB. |
| 7 | "ALEX: Adaptive Log-Embedded Extent Layer" (Applied Sciences, 2026) | Coalesces 4KB page updates into extents. Reduces fsync count. Improves p99 latency. |
| 8 | draft-nandakumar-atproto-atom-00 (IETF) | MOQT transport for ATProto firehose. Group caching, priority delivery, late-join. |
| 9 | bluesky-social/indigo (cmd/relay) | Reference Go relay: 40 workers/host, 5M identity cache, 100M accounts, tens of thousands events/sec. |
| 10 | bluesky-social/indigo (cmd/tap) | Firehose sync tool: ack-based delivery, backpressure on pending IDs, resync with exponential backoff. |
| 11 | Reactive Streams specification | Pull-based backpressure: receiver requests N items, sender may only send up to that amount. |
| 12 | Betts et al., "Exploring CQRS and Event Sourcing" (Microsoft patterns) | Separation of write/read models. Event log as source of truth. |
