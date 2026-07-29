---
title: The Firehose
description: subscribeRepos events, replay cursors, and slow-consumer handling
---

`com.atproto.sync.subscribeRepos` is the PDS repository event stream. Relays
connect over WebSocket, consume ordered events, and persist a cursor so they can
resume after a disconnect.

## Event production

A repository write updates record storage and produces a new signed commit. The
PDS then appends an event with a sequence number to its durable event log. Live
subscribers receive the same serialized event that replay readers load later.

Persisting the event before broadcast matters. A process crash after the
database commit but before a socket write must not create a gap that no cursor
can recover.

## Event schemas

The `subscribeRepos` lexicon defines these normal event bodies:

- `#commit` reports repository operations and includes the commit and referenced
  blocks.
- `#sync` carries a larger repository synchronization payload.
- `#identity` reports an identity update that requires DID document
  re-resolution.
- `#account` reports account status such as active, suspended, or taken down.
- `#info` reports stream conditions such as an outdated cursor.

An XRPC error frame is separate from these normal message schemas. Consumers
should dispatch on the subscription header's operation and type fields before
decoding the body.

## Connection and replay

A relay connects with an optional cursor:

```text
GET /xrpc/com.atproto.sync.subscribeRepos?cursor=12345
```

`SubscribeReposHandler` registers the upgraded connection, replays events after
the cursor in batches, and then transitions the subscriber to live delivery
without changing event order.

Cursor cases require different responses:

- A valid retained cursor replays the following events.
- A future cursor returns `FutureCursor`.
- A cursor older than retained history produces `OutdatedCursor`; the consumer
  must repair its state using repository sync endpoints according to its policy.
- An invalid cursor is rejected before the WebSocket stream starts.

The default replay batch is 100 events, and one connection may replay at most
10,000 events unless configuration overrides the limit.

## Ordering

The handler serializes event-state transitions on its event queue. Sequence
numbers come from the durable log, not from the order in which asynchronous
socket writes happen to finish.

Subscribers must commit their cursor only after they have durably processed the
corresponding event. Acknowledging a cursor first can lose data if the consumer
crashes before storing the event.

## Backpressure

Each connection has independent pending-send limits. The current defaults are:

- 512 queued sends
- 16 MiB of queued payload bytes

If either limit is crossed, the handler sends a `ConsumerTooSlow` error frame
when the socket remains writable and closes the connection with WebSocket policy
code 1008. Other subscribers continue from their own queues.

A slow consumer recovers through cursor replay. Raising the queue limit only
moves the memory and latency boundary; it does not fix a consumer that cannot
keep up with the event rate.

## Consumer validation

Relays and AppViews should treat the stream as untrusted input:

1. Parse the XRPC subscription envelope with size and depth bounds.
2. Confirm event sequence and cursor behavior.
3. Verify the signed repository commit with the DID signing key.
4. Verify each included block against its CID.
5. Apply repository operations atomically.

Transport order alone does not establish authenticity or repository consistency.
