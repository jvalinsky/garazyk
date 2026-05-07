# S1: Memory & Concurrency Synthesis

## Themes

### 1) Queue confinement is used as a safety model, but it is not consistently enforced
Several subsystems rely on a single serial queue or callback thread to serialize access, but state still leaks across threads and re-entrant callbacks.

- `WebSocketConnection` mutates close/send state across the main thread and `writeQueue`, creating a race between `closeWithCode:reason:` and `sendFrame:` (R6 HIGH-2).
- `startReading` recursively re-enters the receive loop from its completion handler, which is a classic queue re-entrancy pattern rather than a clean state machine (R6 HIGH-3).
- `RelayEventFilter` exposes unsynchronized setters for shared `NSSet` state while the read path may be running concurrently (R6 LOW-7).
- `SubscribeReposHandler` appears safe in some spots only because every access happens to be routed through one queue; that is fragile because the correctness depends on discipline rather than enforcement (R6 HIGH-4 notes this explicitly).

### 2) Bounded-resource assumptions drift between layers, producing memory pressure and hidden caps
The codebase often defines limits in one layer and violates or bypasses them in another.

- Blob validation allows payloads far larger than the disk provider’s memory-backed retrieval cap, so data can be accepted and then fail to load later (R3 finding 1).
- Replay/backfill paths enqueue large amounts of data without consistent backpressure checks, especially in `SubscribeReposHandler` replay handling (R6 MED-2).
- `RelayEventBuffer` retains up to 100k events and only prunes on external invocation; this makes retention depend on outside discipline instead of lifecycle hooks (R6 MED-7).
- Cancelled `FirehoseSubscription` objects remain in the subscriptions set, so the container grows even after logical cancellation (R6 LOW-1).

### 3) Sequence, cursor, and epoch state is inconsistent across producer/consumer boundaries
The system repeatedly treats protocol state as if it were local bookkeeping, but consumers depend on it being exact.

- Firehose event sequences are incremented but never written back to the event before encoding, so downstream replay/cursor semantics collapse (R6 BUG-1).
- The client drops `#account`, `#sync`, and `#info` events, so consumers lose pieces of the stream even when the server emits them (R6 BUG-2, BUG-3, MED-1).
- Heartbeat logic mixes `timeIntervalSinceReferenceDate` and `timeIntervalSince1970`, which breaks liveness detection because ping and pong timestamps are measured on different epochs (R6 reclassified LOW-5 -> HIGH-6).
- The Firehose connection path also omits the cursor query parameter, which makes replay semantics incomplete even when the caller requested them (R6 MED-9).

### 4) Untrusted boundary code still reaches raw pointer or raw-buffer operations without enough ownership checks
Most of the code is higher-level ObjC, but a few low-level paths still trust inputs too early.

- The WASM kernel can dereference an invalid pointer in `isKindOfClass:` / `isMemberOfClass:` when it falls back to `object_getClass((id)obj_deref(...))` for non-object arguments (R1 HIGH).
- The same kernel also has ad hoc JSON formatting and float serialization helpers that suggest manual lifecycle handling rather than safer shared primitives (R1 HIGH/MEDIUM issues).

## Critical Findings

1. **Firehose cursor/state corruption is the highest-impact protocol bug.**
   `FirehoseProtocolSession` increments sequence numbers but never assigns them to events before encoding, so every event can go out with `seq = 0` or stale data (R6 BUG-1). This breaks replay, resume, and consumer correctness across the entire firehose stack.

2. **Backpressure is not enforced where it matters most, so slow consumers can turn into memory blowups.**
   `SubscribeReposHandler` replays events with direct `sendMessage:` calls instead of the backpressure-aware path (R6 MED-2). Combined with the large relay buffer, the unpruned subscription set, and the 100k-event retention window, this creates a realistic path to unbounded memory growth under load (R6 MED-7, LOW-1, ARCH-3).

3. **WebSocket lifecycle state is exposed to re-entrancy and cross-queue races.**
   `closeWithCode:reason:` and `sendFrame:` can interleave on different dispatch contexts, and `startReading` recursively schedules new reads from the receive callback (R6 HIGH-2, HIGH-3). This is the kind of concurrency bug that shows up as rare duplicates, out-of-order closes, or hard-to-reproduce dead connections.

4. **Heartbeat liveness is built on mixed time bases, so the code can believe a dead connection is healthy.**
   `pingSent:` uses one epoch while `pongReceived:` uses another (R6 LOW-5 reclassified to HIGH-6). This is not just a timestamp bug; it defeats the entire liveness mechanism, which in turn masks queue growth and stale connection retention.

5. **The codebase has multiple logical leaks: subscriptions, buffered events, and replay state.**
   Cancelled subscriptions are retained, expired relay events are not automatically pruned, and replay paths can enqueue large bursts without gating (R6 LOW-1, MED-7, MED-2). These are lifecycle problems even when ARC itself is doing its job correctly.

6. **Kernel pointer handling is a separate but serious memory-safety risk.**
   The WASM kernel’s invalid fallback dereference can trap the runtime from user input (R1 HIGH). It is isolated from the relay/WebSocket path, but it belongs in the same synthesis because it shows the codebase still has raw memory assumptions at public boundaries.

## Priority Recommendations

1. **Fix firehose sequence propagation and replay semantics first.**
   Assign `event.seq` before every encode path, restore the missing event kinds on the client, and add regression tests for replay/cursor round-tripping (R6 BUG-1, BUG-2, BUG-3, MED-1, MED-9). This is the most protocol-breaking issue and affects downstream consumers immediately.

2. **Add hard backpressure and automatic pruning to every long-lived queue or buffer.**
   Replay should always use the backpressure-aware send path, relay/event buffers should prune on a timer or on append, and cancelled subscriptions should be removed from the owning collection (R6 MED-2, MED-7, LOW-1, ARCH-3). This directly reduces the chance of memory spikes and slow-consumer outages.

3. **Make queue ownership explicit and remove re-entrant control flow from WebSocket lifecycle code.**
   Keep state transitions on one queue, avoid calling receive again from inside completion handlers, and make close/send ordering explicit with a single state machine (R6 HIGH-2, HIGH-3). This is the best way to eliminate race windows without relying on convention.

4. **Unify time-base handling for heartbeat, replay, and cursor logic.**
   Use one epoch consistently for ping/pong tracking and audit other sequence/cursor APIs for the same class of bug (R6 HIGH-6, MED-9). These bugs are easy to miss in review but have large production impact because they silently defeat liveness and recovery.

5. **Lock down shared mutable containers that cross callback boundaries.**
   Synchronize or confine `RelayEventFilter` setters, and audit any other mutable sets/dictionaries exposed to callback-driven code paths (R6 LOW-7). The pattern here is not an explicit lock-order inversion; it is the absence of a hard ownership rule.

6. **Harden low-level boundary code against invalid object and buffer assumptions.**
   Add object verification before the WASM kernel’s fallback class lookup and replace ad hoc serialization helpers with safer primitives where possible (R1 HIGH). This is lower priority than the firehose/backpressure problems, but it is still a direct crash vector from untrusted input.
