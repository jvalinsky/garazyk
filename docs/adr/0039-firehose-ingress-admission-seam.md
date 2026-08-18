<!-- SPDX-FileCopyrightText: 2025-2026 Jack Valinsky -->
<!-- SPDX-License-Identifier: Unlicense OR CC0-1.0 -->

# ADR 0039: Firehose Ingress Admission Seam

**Status:** Accepted  
**Date:** 2026-08-17

## Context

[Workstream 17](../plans/workstreams/17-zuk-relay-resource-bounds.md) locked
finding 4 states that backpressure must reach the socket, and that a bounded
downstream queue which moves overflow to an unbounded upstream GCD queue is not
a fix. [Phase 38](../plans/prompts/phase-38-zuk-bounded-ingress.md) requires
removing every unbounded asynchronous handoff between upstream WebSocket
receipt and accepted relay processing.

`ATProtoFirehose.sendEventToSubscriptions:` currently performs an unconditional
`dispatch_async(dispatch_get_main_queue(), ...)` per event, per subscription.
This is the unbounded hop the phase names. It sits upstream of every relay
component, so a bound applied in `RelayUpstreamManager` or
`ATProtoRelayIngressPipeline` cannot constrain it.

The complication is ownership. `ATProtoFirehose` is shared: the relay
(`zuk`) consumes it through `ATProtoRelayClient`, and the AppView ingest path
consumes it independently. The relay needs synchronous, gated delivery so that
a full backlog stalls the socket read. The AppView has no admission controller
and today relies on asynchronous main-queue delivery. Changing the threading
contract unconditionally would alter AppView ingest behavior as a side effect
of a relay resource fix.

Phase 38 already established the precedent for a per-consumer opt-in with
`ATProtoRelayClient.reconnectUsesProcessedCursor`, which the header documents
as "AppView leaves this off; Zuk bounded ingress turns it on."

## Decision

Add an opt-in delivery gate to `ATProtoFirehose`: a block, nil by default,
consulted **synchronously** inside `handleMessage:` after decode and before any
dispatch. When the block is nil, delivery behaves exactly as it does today.
When installed, its return value decides whether the frame is delivered, and
the calling thread is the socket read thread, so refusal or delay applies
backpressure directly at the transport.

`zuk` installs the gate, backed by `ATProtoRelayIngressAdmission` via
`ATProtoRelayIngressPipeline`, and the pipeline keeps ownership of the
resulting token throughout. AppView installs nothing and is unaffected.

The four points below were open questions in the draft. Each is settled
against the actual call graph — `RelayIngressPipeline.submitEvent:...`,
`RelayIngressAdmission.admitEncodedBytes:...`, and `RelayClient`'s existing
`reconnectUsesProcessedCursor`/`scheduleReconnect` machinery — not restated in
the abstract.

### 1. Gate shape: decision-only, no token hand-back

`ATProtoFirehose` gains:

```objc
typedef BOOL (^ATProtoFirehoseIngressGate)(id event, FirehoseEventKind kind);
@property (nonatomic, copy, nullable) ATProtoFirehoseIngressGate ingressGate;
```

Consulted in `handleMessage:` immediately before each
`sendEventToSubscriptions:kind:` call, once the event object is fully
populated (`wireFrameLength`, `seq`, `repo`/`did` already set), for the kinds
`RelayIngressPipeline.encodedByteLengthForEvent:` actually accounts for —
Commit, Identity, Account, Sync, and the raw pass-through frame. `#info` and
error frames carry no `wireFrameLength` and no backlog cost; they are exempt
and delivered exactly as today.

`ATProtoRelayClient` gains a mirroring `ingressGate` property of the same
type. `configuredFirehoseForWebSocketURL:` assigns it onto each newly created
`ATProtoFirehose` instance, the same way `reconnectUsesProcessedCursor` is a
`RelayClient`-level opt-in that survives reconnects rather than a
per-connection one-off (`RelayClient.h:116-120`,
`RelayClient.m:80-84`). `ATProtoRelayUpstreamManager
.configureBoundedIngressWithConfiguration:...` installs the block per client
alongside the existing `client.reconnectUsesProcessedCursor = YES;`
(`RelayUpstreamManager.m:349-351`). The block computes `encodedBytes`
(`event.wireFrameLength`), `orderingKey` (the event's DID), and calls
`ingressPipeline submitEvent:encodedBytes:orderingKey:fromUpstream:sequence:
error:` synchronously, returning its `BOOL`.

A token hand-back was the alternative (open question 1). It is unnecessary:
`RelayIngressPipeline` already owns the token end-to-end —
`submitEvent:...:error:` admits it (`RelayIngressPipeline.m:218-222`) and
`dispatchWorkItem:toShard:` releases it from the shard queue once the
process-block completion fires (`RelayIngressPipeline.m:146-197`). Handing a
token back through `ATProtoFirehose` would only add API surface for a
hand-off nothing downstream needs — the firehose has no reason to ever see a
`ATProtoRelayIngressAdmissionToken`. Decision-only is both correct and
cheaper.

AppView's `GZAppViewRelayConnection` (`AppViewIngestEngine.m:107-140`) never
sets `ingressGate`; it stays nil and `handleMessage:` behaves exactly as
today. `BeskidFirehoseInvalidator` (`BeskidFirehoseInvalidator.m:87`)
constructs `ATProtoFirehose` directly and is nil by construction — the gate is
opt-in per instance, not a global switch, so every other consumer of the
class is unaffected without needing to know this ADR exists.

### 2. Bound on the read thread: documented contract, not a runtime timeout

The gate's real call chain is:

```text
gate block
  -> RelayIngressPipeline.submitEvent:...           dispatch_sync(_controlQueue)
    -> RelayIngressAdmission.admitEncodedBytes:...  dispatch_sync(_admissionQueue)
```

Both queues do in-process bookkeeping only — counters and dictionaries.
Watermark handlers fire asynchronously on a separate `_watermarkQueue`
(`RelayIngressAdmission.m:103,110`) rather than inline, so a high/low
transition can never block the admission fast path on a delegate callback.
There is no I/O and no unbounded loop on this path today.

No runtime timeout is enforced from inside `handleMessage:`. GCD gives no
safe way to preempt a synchronous block already running on the read thread;
canceling it would leave `ATProtoFirehose` and `ATProtoRelayIngressAdmission`
state undefined mid-mutation. Nothing in this codebase does that today —
`ATProtoWebSocketConnection.heartbeatInterval`/`heartbeatTimeout` detects an
*idle socket* via its own `dispatch_source` timer, independent of the read
thread, which is a different failure mode than a gate call that hangs while
the socket keeps producing bytes.

Instead: an unenforced, documented contract, matching the stub's original
language — gate implementations must not perform I/O, must not acquire a
lock that could be held by another queue blocked on the read thread, and must
not call back into `ATProtoFirehose` (no re-entrancy). The two production
implementations (`RelayIngressPipeline.submitEvent:`,
`RelayIngressAdmission.admitEncodedBytes:`) satisfy this by construction. Any
future gate implementation — including a Phase 40 one, see point 4 — must
keep that property. A debug-mode duration log around the gate call (flagging
calls that exceed a small threshold, e.g. via `GZLogger`) is a reasonable R4
implementation nicety for catching regressions in code review and CI, but it
is observability, not enforcement, and is not required for this ADR to hold.

### 3. Refused frame: close the connection, reconnect from the last processed cursor

Silent drop was ruled out by tracing what actually observes a refused frame.
The gate runs before `sendEventToSubscriptions:kind:`, so a refused frame
never reaches `ATProtoRelayClient`'s `firehoseSubscription:didReceive...Event:`
delegate methods. `noteIncomingSequence:` therefore never runs for it, and
`lastReceivedSequence`/`currentSeq` never advance past it
(`RelayClient.m:170-182`). If the connection stays open, the next *admitted*
frame's `noteIncomingSequence:` call still succeeds — its sequence is greater
than the last one that was actually delivered — so the refused sequence is
skipped forever with no error surfaced anywhere. That is a permanent gap in a
component whose entire contract is gapless forwarding, which is worse than
the bug this ADR exists to fix.

The decision: on refusal, `ATProtoFirehose` closes the connection
(`ATProtoWebSocketConnection.closeWithCode:reason:`) instead of delivering
the frame or continuing to read. This reuses the close-then-reconnect path
that already exists for every other WS closure —
`webSocketConnection:didCloseWithCode:reason:` ->
`ATProtoRelayClient.firehoseSubscription:didCloseWithError:` ->
`scheduleReconnect`, with its existing exponential backoff capped at 60s and
bounded by `maxReconnectAttempts` (`RelayClient.m:199-353`). No new reconnect
machinery is needed.

Because `ATProtoRelayUpstreamManager` already sets
`client.reconnectUsesProcessedCursor = YES` whenever `ingressPipeline` exists
(`RelayUpstreamManager.m:349-351`), the reconnect cursor (`currentSeq`) only
advances via `acknowledgeProcessedSequence:`, called from the
`RelayIngressProcessCompletion` block once an event is actually *processed*,
not merely admitted (`RelayUpstreamManager.m:339-346`). Reconnecting after a
refusal therefore resumes from the last processed sequence: every event that
was admitted-but-unprocessed at the moment of refusal, plus the refused event
itself, is redelivered on the new connection. No gap; at most the ordinary
at-least-once reprocessing the pipeline already tolerates.

This is what R5 was blocked on. Rejection stops being an inline "log and
discard" and becomes the trigger for the reconnect/backoff machinery that
already exists. R5's high-watermark-vs-hard-cap split can now treat the hard
cap purely as "the trigger that forces a reconnect," while the high
watermark remains the mechanism that tries to avoid ever reaching it (via
`onHighWatermark` -> `ingressPipelineDidRequestPause:` ->
`RelayClient.pauseReading`).

Close reason/code: reuse the backpressure vocabulary the codebase already
recognizes — `FirehoseErrorIsBackpressureClose` treats close codes 1008/1009
or a reason containing "ConsumerTooSlow"/"Outbound queue" as backpressure
(`Firehose.m:17-31`), and `RelayClient` already logs `backpressure=YES/NO` on
every close (`RelayClient.m:334-340`). An ingress-refusal close should use
that same vocabulary rather than a differently-shaped signal for what is
operationally the same event from the relay's point of view: this connection
could not keep up.

### 4. Phase 40 validation cost: the shard executor, not this seam

Phase 40 ([phase-40-zuk-validation-efficiency.md](../plans/prompts/phase-40-zuk-validation-efficiency.md))
Slice 4 explicitly removes semaphore waits "from the relay processing shard"
and requires DID resolution to be asynchronous, coalesced, and itself subject
to "Phase 38 pressure." It is designed to live downstream, inside
`RelayEventValidator`/the shard `processBlock`, not upstream of admission.

That placement is required, not just convenient: point 2 above establishes
the gate's entire justification as doing no I/O and returning in bounded,
sub-millisecond bookkeeping time. DID resolution is a real network round
trip even when cached and coalesced — a cold path blocks on the network.
Running validation synchronously on the socket read thread would recreate the
exact defect this ADR exists to close, just moved from a GCD queue to a
blocking network call instead of a dispatch hop.

Recommendation: Phase 40's cost bound belongs on the shard executor
(`RelayIngressPipeline`'s per-shard queues / `RelayEventValidator`),
expressed through the backpressure vocabulary already wired there
(`RelayIngressBackpressureDelegate`, `onHighWatermark`/`onLowWatermark`, or a
validation-specific in-flight cap that signals back the same way). This is
necessarily a shorter, more speculative answer since Phase 40 is future work
— the exact shape of that bound is Phase 40's to design — but its layer is
settled here: it does not belong in `ATProtoFirehose.ingressGate`.

## Consequences

- The admission bound becomes the real bound; no unbounded queue precedes it.
- `ATProtoRelayClient.callbackQueue` is retained for connection lifecycle
  callbacks (connect, disconnect, error) and removed from the per-event path.
- The explicit pause/resume watermark machinery becomes a secondary control
  rather than the primary defense, since the read thread is already gated.
- `ATProtoFirehose` acquires a documented threading contract: gate blocks run
  on the read thread, must not block indefinitely, must do no I/O, and must
  not re-enter the firehose.
- `ATProtoFirehose` gains `ingressGate` (nil by default); `ATProtoRelayClient`
  gains a mirroring `ingressGate` property threaded the same way as
  `reconnectUsesProcessedCursor`. AppView and Beskid are unaffected by
  construction, not by convention — the gate does nothing unless an owner
  explicitly assigns one.
- Refusal now drives a WebSocket close plus the existing reconnect/backoff
  path, not a log-and-discard. R5 can be scoped as "stop discarding, start
  closing," with the hard cap as the close trigger and the high watermark as
  the thing that tries to prevent reaching it.
- Phase 40's validation-cost bound is out of scope for this seam by
  construction: it must land on `RelayIngressPipeline`'s shard queues /
  `RelayEventValidator`, not in `ATProtoFirehose.ingressGate`.

## Alternatives considered

**Bound the existing main-queue delivery.** Keeps the firehose contract intact
but requires a second bounded structure in front of admission, which is the
"bounded queue beside an old unbounded path" the phase prompt explicitly
forbids.

**Give the relay its own firehose subclass or fork.** Avoids touching the
shared type, at the cost of duplicating frame decoding and diverging two copies
of the parser — the opposite of the consolidation ADR 0031 gates.

**Change delivery threading unconditionally for all consumers.** Simplest
diff, but silently changes AppView ingest concurrency as a side effect of a
relay fix, with no measurement of the AppView consequence.
