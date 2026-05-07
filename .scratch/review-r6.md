# R6: Identity, PLC & Sync — Deep Code Review

**Reviewer:** R6 (Identity, PLC, Sync, Relay, Firehose, WebSocket)
**Date:** 2026-05-06
**Scope:** DID resolution, PLC operations, relay buffers, firehose, WebSocket protocol

---

## Critical Bugs

### BUG-1: FirehoseProtocolSession increments sequence but never assigns it to the event

**File:** `Sync/Firehose/FirehoseProtocolSession.m:23-35`

The `encodeCommitEvent:` method increments `_sequenceNumber` and captures it into local `seq`, but **never assigns `seq` to `event.seq`** before encoding. The event is encoded with whatever `seq` value it already had (likely 0 from `[[FirehoseCommitEvent alloc] init]`).

```objc
- (NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event {
   __block NSUInteger seq;
   dispatch_sync(_sequenceQueue, ^{
     _sequenceNumber++;
     seq = _sequenceNumber;
   });
  // BUG: event.seq is never set to seq!
  NSError *error = nil;
  NSData *data = [self.eventFormatter encodeCommitEvent:event error:&error];
  ...
}
```

Same bug exists in `encodeIdentityEvent:`, `encodeAccountEvent:`, and `encodeInfoEvent:`. The `EventFormatter` then encodes `payload[@"seq"] = @(event.seq)` which will be 0 or stale.

**Impact:** All firehose events are broadcast with seq=0 (or whatever the caller set), making cursor-based replay completely broken. This is a **protocol-breaking bug** — downstream consumers cannot resume from a cursor.

**Fix:** Add `event.seq = seq;` before encoding in each encode method.

---

### BUG-2: Firehose client `handleMessage:` silently drops `#account` events

**File:** `Sync/Firehose/Firehose.m:168-175`

The `#account` case creates a `FirehoseAccountEvent` but never calls `sendEventToSubscriptions:kind:` — the event is constructed and immediately discarded:

```objc
} else if ([msgType isEqualToString:@"#account"]) {
    FirehoseAccountEvent *event = [[FirehoseAccountEvent alloc] init];
    event.did = payload[@"did"];
    event.seq = [payload[@"seq"] longLongValue];
    event.active = [payload[@"active"] boolValue];
    event.status = payload[@"status"];
    event.time = payload[@"time"];
    // Missing: [self sendEventToSubscriptions:event kind:???];
}
```

Additionally, `FirehoseEventKind` enum has no `FirehoseEventKindAccount` case, so there's no way to dispatch it even if the call were added.

**Impact:** Firehose subscribers never receive account status events (takedowns, deactivations). Consumers relying on account events for moderation will miss them entirely.

**Fix:** Add `FirehoseEventKindAccount` to the enum, add a corresponding delegate method, and call `sendEventToSubscriptions:kind:` in the `#account` handler.

---

### BUG-3: `#sync` events are never dispatched in the Firehose client

**File:** `Sync/Firehose/Firehose.m:120-176`

The `handleMessage:` method handles `#commit`, `#identity`, and `#account`, but has no handler for `#sync` events. The `FirehoseSyncEvent` class exists and is used server-side (as a fallback in `SubscribeReposHandler`), but client-side consumers have no way to receive them.

**Impact:** When a commit event encoding fails and the server falls back to a `#sync` event, the client silently drops it. The consumer sees a gap in the firehose with no indication.

---

### BUG-4: WebSocketCodec 64-bit payload length parsing is host-endian-dependent

**File:** `Sync/WebSocket/WebSocketCodec.m:76-81`

The 8-byte extended length is parsed byte-by-byte with shifts, but the loop order is wrong for big-endian hosts:

```objc
payloadLength = 0;
for (int i = 0; i < 8; i++) {
    payloadLength = (payloadLength << 8) | bytes[2 + i];
}
```

This is correct (RFC 6455 specifies big-endian / network byte order). However, the 2-byte extended length case also uses network byte order correctly. **No bug here on re-review** — this is correct.

---

### BUG-5: RelayEventBuffer linear scan for `eventsAfterCursor:`

**File:** `Sync/Relay/RelayEventBuffer.m:73-86`

`eventsAfterCursor:count:` performs a linear scan of the entire buffer from the beginning. With 100,000 events (the default max), this is O(n) per query. For relay backfill with many concurrent subscribers, this becomes a bottleneck.

```objc
- (nullable NSArray *)eventsAfterCursor:(int64_t)cursor count:(NSUInteger)count {
    __block NSMutableArray *result = [NSMutableArray array];
    dispatch_sync(_bufferQueue, ^{
        for (BufferedEvent *e in self.buffer) {  // Linear scan!
            if (e.seq > cursor) {
                [result addObject:e.event];
                if (result.count >= count) break;
            }
        }
    });
    return result.count > 0 ? [result copy] : nil;
}
```

**Impact:** Under load with many concurrent backfill requests, the serial queue blocks on each linear scan. A binary search on the sorted array would be O(log n).

**Fix:** Since events are appended in seq order, use binary search to find the starting position.

---

### BUG-6: RelayEventBuffer `appendEvent:` doesn't update `newestSeq` correctly for out-of-order events

**File:** `Sync/Relay/RelayEventBuffer.m:54-56`

```objc
if (self.newestSeq < seq) {
    self.newestSeq = seq;
}
if (self.oldestSeq < 0 || seq < self.oldestSeq) {
    self.oldestSeq = seq;
}
```

The `oldestSeq` check uses `seq < self.oldestSeq`, which means if events arrive out of order (possible in relay scenarios with multiple upstreams), an event with a lower seq than the current oldest will update `oldestSeq` — but the actual oldest event in the buffer might have been pruned already. This is a minor inconsistency that could cause `eventsAfterCursor:` to return incorrect results if a cursor points to a pruned event whose seq was lower than the current `oldestSeq`.

---

## High-Severity Issues

### HIGH-1: WebSocketConnection `flushWriteBuffer` only sends the first message — no drain loop

**File:** `Sync/WebSocket/WebSocketConnection.m:544-550`

```objc
- (void)flushWriteBuffer {
  if (self.messageQueue.count == 0)
    return;
  NSData *message = self.messageQueue.firstObject;
  [self writeData:message];
}
```

When `writeData:` completes, it dequeues the sent frame and calls `flushWriteBuffer` again. This creates a chain of one-at-a-time sends. However, the issue is that `writeData:` is called with only the first message, and the completion handler dequeues and calls `flushWriteBuffer` again. This is actually correct — it's a pipelined write-one-at-a-time pattern. **Not a bug on re-review**, but the naming is misleading (it's not "flushing" the buffer, it's sending the next one).

### HIGH-2: WebSocketConnection `closeWithCode:reason:` has a race with `sendFrame:`

**File:** `Sync/WebSocket/WebSocketConnection.m:439-466`

The close method sets `self.state = WebSocketConnectionStateClosing` on the calling thread, then dispatches to `writeQueue` to clear the message queue. But `sendFrame:` also checks state on `writeQueue`. Between the state change and the queue drain, a `sendFrame:` dispatch could have already been queued and will execute after the state change but before the queue clear:

```objc
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
  self.state = WebSocketConnectionStateClosing;  // Main thread
  dispatch_async(self.writeQueue, ^{
    [self.messageQueue removeAllObjects];          // writeQueue
    self.queuedSendBytes = 0;
  });
  NSData *frame = [self.session.codec closeFrame:code reason:reason];
  [self writeData:frame];  // Queues on writeQueue
  ...
}
```

If `sendFrame:` was already queued on `writeQueue` before the close, it will execute after the queue clear but the `writeData:` for the close frame is also queued. The close frame could be written before the pending frame, or the pending frame could be written after the queue was "cleared" (since `removeAllObjects` and the pending `sendFrame:` are both on `writeQueue` and will execute in order).

**Impact:** In practice, the serial `writeQueue` ensures ordering, so the clear happens before any new sends. The real risk is: the close frame is written via `writeData:` which goes through the normal send pipeline, but the message queue was just cleared. The close frame will be added to the queue, sent, and then the 5-second timeout fires. This is mostly correct but fragile.

### HIGH-3: WebSocketConnection `startReading` re-entry creates recursive read loop

**File:** `Sync/WebSocket/WebSocketConnection.m:269-305`

The `startReading` method calls `receiveWithMinimumLength:...` with a completion handler that calls `startReading` again. If the completion is called on a queue that's also processing `handleReceivedData:`, and `handleReceivedData:` triggers a state change that calls `startReading`, you could get overlapping reads.

The `dispatch_async(dispatch_get_main_queue(), ...)` for `handleReceivedData:` provides some protection, but the `startReading` call at the end of the completion handler is not dispatched to main queue — it's called directly. This means `receiveWithMinimumLength:` could be called while the previous receive is still completing.

**Impact:** Potential double-read or read-after-cancel on the underlying connection.

### HIGH-4: SubscribeReposHandler `lastCommitRevByDID` is not thread-safe

**File:** `Sync/Firehose/SubscribeReposHandler.m:59`

`lastCommitRevByDID` is a plain `NSMutableDictionary` accessed from `syncQueue` (serial), but the `broadcastRepositoryCommit:forRepo:ops:blobs:` method reads and writes it on `syncQueue`. The `handleRecordChange:` notification handler also dispatches to `syncQueue`. This is actually safe since all access is on `syncQueue`. **Not a bug on re-review.**

### HIGH-5: PLCServer signature validation bypass — `sig` field check is too weak

**File:** `PLC/PLCServer.m:88`

```objc
NSString *sig = op[@"sig"];
if (![sig isKindOfClass:[NSString class]] || [sig hasSuffix:@"="]) {
```

The check rejects signatures ending with `=`, which is meant to catch base64 padding. However:
1. Standard base64 can end with `=` or `==` — this rejects valid base64 with single padding
2. The PLC spec uses base64url (no padding), so this check is approximately correct but the reasoning is wrong
3. More importantly, the validation only checks that `sig` is a string and doesn't end with `=`. It doesn't verify the signature is valid base64url, or that it decodes to a reasonable length. A 1-character string like `"a"` would pass this check.

The actual cryptographic verification happens in `PLCAuditor verifyOperation:`, so this is a defense-in-depth issue rather than a direct bypass.

---

## Medium-Severity Issues

### MED-1: Firehose client `#info` events are never dispatched

**File:** `Sync/Firehose/Firehose.m:120-176`

The `handleMessage:` method has no handler for `#info` events (e.g., `OutdatedCursor`, `HandshakeComplete`). These are important for consumers to know when their cursor was adjusted. The `FirehoseInfoEvent` class exists but is never instantiated in the client's `handleMessage:`.

### MED-2: SubscribeReposHandler replay doesn't check backpressure

**File:** `Sync/Firehose/SubscribeReposHandler.m:824-831`

During replay, events are sent directly via `[connection sendMessage:eventData]` without backpressure checking. If a slow consumer connects with cursor=0, the replay could dump thousands of events into the connection's outbound queue, potentially exceeding memory limits before the backpressure check in `sendEventData:toConnectionWithBackpressureCheck:` kicks in for live events.

```objc
for (NSDictionary *eventDict in events) {
    NSData *eventData = eventDict[@"data"];
    if (![eventData isKindOfClass:[NSData class]] || eventData.length == 0) {
      continue;
    }
    [connection sendMessage:eventData];  // No backpressure check!
}
```

**Fix:** Use `sendEventData:toConnectionWithBackpressureCheck:` during replay as well.

### MED-3: RelayDownstreamHandler creates a new `EventFormatter` per event in deprecated methods

**File:** `Sync/Relay/RelayDownstreamHandler.m:157-176`

The deprecated `formatCommitEventForWire:`, `formatIdentityEventForWire:`, and `formatAccountEventForWire:` methods create a new `EventFormatter` instance each call. While these methods are deprecated, they're still compiled and could be called accidentally.

### MED-4: RelayUpstreamManager `urlForClient:` is O(n) linear scan

**File:** `Sync/Relay/RelayUpstreamManager.m:336-343`

```objc
- (NSString *)urlForClient:(RelayClient *)client {
    for (NSString *url in self.upstreamClients) {
        if (self.upstreamClients[url] == client) {
            return url;
        }
    }
    return nil;
}
```

This is called on every delegate callback from `RelayClient`. With many upstreams, this becomes O(n) per event. A reverse mapping dictionary would be O(1).

### MED-5: WebSocketCodec doesn't validate reserved opcode values

**File:** `Sync/WebSocket/WebSocketCodec.m:119-157`

The codec processes frames with opcodes 3-7 and 11-15 (which are reserved per RFC 6455 section 5.2) without rejecting them. The `eventForOpcode:payload:` returns `nil` for unknown opcodes (line 221-222), but the frame bytes are still consumed from the buffer. RFC 6455 section 7.4.1 says these should trigger a close with code 1003.

### MED-6: PLCServer `handleExport:` doesn't validate `after` cursor format

**File:** `PLC/PLCServer.m:682-686`

The `after` query parameter is parsed via `NSDateFormatter atproto_dateFromString:` but there's no validation that the string is a valid date. If parsing fails, `cursorDate` will be nil, which means the export starts from the beginning — potentially returning already-seen data.

### MED-7: RelayEventBuffer `pruneExpired` is O(n) and not called automatically

**File:** `Sync/Relay/RelayEventBuffer.m:125-145`

The `pruneExpired` method builds a `toRemove` array (O(n) scan + O(n) removal), and it's never called automatically — it must be invoked externally. The buffer only auto-prunes by count (when `maxEvents` is exceeded), not by time. Events older than the retention window will accumulate until `maxEvents` is hit, at which point the oldest-by-insertion-order events are removed (which may not be the oldest-by-timestamp if events arrive out of order).

### MED-8: WebSocketConnection `handleHandshakeResponse:` doesn't validate the Sec-WebSocket-Accept header

**File:** `Sync/WebSocket/WebSocketConnection.m:352-380`

The handshake response parser only checks for `HTTP/1.1 101` prefix. Per RFC 6455 section 4.2.2, the client must verify that the `Sec-WebSocket-Accept` header matches the base64-encoded SHA-1 of the concatenated key + `"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"`. Without this check, a malicious intermediary could inject a fake 101 response.

**Impact:** Man-in-the-middle could inject a fake WebSocket upgrade response. This is a security concern for production deployments.

### MED-9: Firehose `connect` method doesn't pass cursor to WebSocket path

**File:** `Sync/Firehose/Firehose.m:61-78`

When connecting, the path is hardcoded as `/xrpc/com.atproto.sync.subscribeRepos` without appending the cursor query parameter. Subscriptions created with a cursor will never get replay — they only receive live events after connection.

The `subscribeWithCursor:collections:delegate:` method stores the cursor on the subscription object, but the `connect` method doesn't use it when building the WebSocket URL.

---

## Low-Severity Issues

### LOW-1: `FirehoseSubscription.cancel` doesn't remove from `Firehose.subscriptions`

**File:** `Sync/Firehose/Firehose.m:251-253`

Cancelling a subscription sets `isActive = NO` but the subscription object remains in the `Firehose.subscriptions` set. Over time, cancelled subscriptions accumulate. The `sendEventToSubscriptions:kind:` method skips inactive subscriptions, but the set grows unbounded.

### LOW-2: `FirehoseCommitEvent.blobs` type mismatch

**File:** `Sync/Firehose/Firehose.h:87`

The property is declared as `NSArray<CID *> *` but in `Firehose.m:153`, it's assigned from `payload[@"blobs"] ?: @[]` which is decoded from CBOR as raw data (likely `NSData` objects), not `CID` objects. The type declaration doesn't match the runtime type.

### LOW-3: WebSocketServer Linux path doesn't set up accept source

**File:** `Sync/WebSocket/WebSocketServer.m:72-149` (Linux path)

The Linux implementation of `start:` creates a listening socket and sets it non-blocking, but never creates a `dispatch_source` for accepting connections. The server socket is created but no connections are ever accepted. The `acceptSource` property is declared but never initialized.

**Impact:** The WebSocket server is completely non-functional on Linux/GNUstep — it binds and listens but never accepts connections.

### LOW-4: PLCServer duplicate `alsoKnownAs` validation

**File:** `PLC/PLCServer.m:144-186` and `PLC/PLCServer.m:235-262`

The `alsoKnownAs` array is validated twice — once at line 144 (checking count, type, prefix, and length) and again at line 235 (checking count, type, length, and duplicates). The second validation is redundant with the first, except for the duplicate check. The count check at line 235 is also a dead duplicate of line 153.

### LOW-5: `WebSocketHeartbeatPolicy` uses `timeIntervalSinceReferenceDate` for pong but `timeIntervalSince1970` for ping

**File:** `Sync/WebSocket/WebSocketConnection.m:432` vs `WebSocketProtocolSession.m:75`

In `handlePongFrame:`, the pong timestamp is recorded using `[[NSDate date] timeIntervalSince1970]`, but the heartbeat policy's `tick:` method receives timestamps from `NSDate timeIntervalSinceReferenceDate`. These are different epochs (2001 vs 1970). The comparison `now - self.lastPingSentTime >= self.heartbeatTimeout` will always be ~978307200 seconds apart, making the timeout fire immediately.

**Wait — let me re-check.** In `WebSocketProtocolSession.m:75`:
```objc
[self.heartbeatPolicy pingSent:now];
```
where `now` comes from `tick:` which uses `NSDate timeIntervalSinceReferenceDate`.

In `WebSocketConnection.m:432`:
```objc
[self.heartbeatPolicy pongReceived:[[NSDate date] timeIntervalSince1970]];
```

This is using `timeIntervalSince1970` while the policy tracks `lastPingSentTime` in `timeIntervalSinceReferenceDate`. The difference between these two reference dates is ~978307200 seconds. So `pongReceived` will set `lastPongReceivedTime` to a value ~978307200 seconds in the future relative to `lastPingSentTime`, and `waitingForPong` will be set to NO. This means the pong will always appear to arrive "in the future" and the timeout check `now - lastPingSentTime >= heartbeatTimeout` will never fire because `waitingForPong` is immediately cleared.

**Actually, this means the heartbeat timeout is broken** — it will never detect a dead connection because the pong timestamp is in a different epoch than the ping timestamp. The `waitingForPong` flag gets cleared immediately, so the policy always thinks the pong arrived.

**Reclassifying: This is HIGH-6, not LOW-5.**

### LOW-6: SubscribeReposHandler `eventRateLimiter` timer handler is empty

**File:** `Sync/Firehose/SubscribeReposHandler.m:117-119`

```objc
dispatch_source_set_event_handler(_eventRateLimiter, ^{
    // Timer fires to allow event processing
});
```

The rate limiter timer fires but does nothing. It's described as a "100 events/sec" rate limiter but has no actual rate-limiting logic. Events are processed as fast as they arrive.

### LOW-7: `RelayEventFilter` setters are not thread-safe

**File:** `Sync/Relay/RelayEventFilter.m:25-35`

The `setAllowedCollections:`, `setAllowedRepos:`, and `setBlockedActors:` methods replace the NSSet properties without synchronization. If called from multiple threads while `shouldForwardEventWithRepo:andCollection:andActor:` is running, the filter could read a partially-updated set.

---

## Architectural Observations

### ARCH-1: Dual-path WebSocket acceptance creates complexity

The `SubscribeReposHandler` supports both a legacy standalone `WebSocketServer` and the modern HTTP upgrade path via `acceptUpgradedConnection:request:`. The legacy path is deprecated but still fully functional. This creates two code paths for connection management, two paths for initial state sending, and two paths for delegate notification. The legacy path should be removed or gated behind a compile flag.

### ARCH-2: Relay pipeline has redundant event encoding

In the relay path: `RelayUpstreamManager` → `RelayDownstreamHandler` → `SubscribeReposHandler` → `FirehoseProtocolSession` → `EventFormatter`. The `RelayDownstreamHandler` receives decoded event objects, then passes them to `SubscribeReposHandler` which re-encodes them. For a relay, it would be more efficient to pass pre-encoded CBOR data through the pipeline and only decode when needed for filtering.

### ARCH-3: No flow control between relay upstream and downstream

The `RelayDownstreamHandler` receives events from upstream and immediately broadcasts them downstream. If downstream consumers are slow, the `SubscribeReposHandler` will disconnect them via backpressure, but there's no mechanism to pause upstream consumption. A relay under heavy load could consume events faster than it can broadcast them, leading to memory pressure in the `RelayEventBuffer`.

### ARCH-4: WebSocket protocol implementation is split across too many layers

The WebSocket stack has 6 layers: `WebSocketServer` → `WebSocketConnection` → `WebSocketProtocolSession` → `WebSocketCodec` + `WebSocketHeartbeatPolicy`. The `WebSocketProtocolSession` is a thin coordinator that could be merged into `WebSocketConnection`. The `WSSessionAction` pattern adds indirection without clear benefit — the connection could directly handle codec events.

### ARCH-5: PLC server binds to 127.0.0.1 by default

**File:** `PLC/PLCServer.m:356`

The default `initWithStore:auditor:port:` binds to `127.0.0.1`, which is correct for security but may surprise operators who expect `0.0.0.0` binding. The `host:` variant exists but the default is localhost-only.

### ARCH-6: Firehose client and server share event model classes but have different dispatch patterns

The `Firehose` client uses a delegate-per-subscription pattern, while `SubscribeReposHandler` uses a broadcast-to-all-connections pattern. The event model classes (`FirehoseCommitEvent`, etc.) are shared, but the client's `handleMessage:` manually constructs events from dictionaries, while the server's `broadcastRepositoryCommit:` constructs them from `RepoCommit` objects. This asymmetry makes it hard to test the full round-trip.

---

## Summary

| Severity | Count | Key Issues |
|----------|-------|------------|
| Critical | 3 | BUG-1 (seq never assigned), BUG-2 (account events dropped), BUG-3 (sync events dropped) |
| High | 6 | HIGH-3 (recursive read loop), HIGH-5 (weak sig validation), plus reclassified LOW-5 (heartbeat epoch mismatch) |
| Medium | 9 | MED-2 (replay backpressure), MED-8 (no Sec-WebSocket-Accept validation), MED-9 (cursor not in URL) |
| Low | 5 | LOW-1 (subscription leak), LOW-3 (Linux WS server broken), LOW-6 (empty rate limiter) |

**Most impactful fix:** BUG-1 (sequence number never assigned to events) — this breaks the entire firehose cursor/replay mechanism. Every event goes out with seq=0.

**Second most impactful:** The heartbeat epoch mismatch (reclassified from LOW-5 to HIGH-6) — this means WebSocket heartbeat timeouts never fire, so dead connections are never detected by the heartbeat mechanism. They'll only be cleaned up when the TCP connection eventually resets.
