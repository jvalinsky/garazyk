---
title: "Tutorial 14: Advanced Firehose (Filtering & Backfill)"
---

# Tutorial 14: Advanced Firehose (Filtering & Backfill)

## Overview

The Firehose is the real-time heartbeat of the AT Protocol. While Tutorial 5 covered the basics of connecting, this tutorial dives into the production-grade features of the Garazyk Firehose: how it handles historical data (backfill), manages slow consumers (backpressure), and validates cursors to ensure network consistency.

**Learning Objectives:**
- Understand the backfill logic in `SubscribeReposHandler.m`.
- Analyze cursor validation rules and error frames (`FutureCursor`, `OutdatedCursor`).
- Explore the backpressure mechanisms used to protect the server.
- Verify Firehose resumption using cursors.

**Estimated Time:** 40-50 minutes

## Prerequisites

- Complete [Tutorial 5: Firehose](./tutorial-5-firehose).
- Familiarity with SQLite and basic networking concepts.
- `deciduous` CLI tool installed.

---

## Step 1: Track the Goal with Deciduous

Record your intent to study the streaming resilience layer:

```bash
deciduous add goal "Audit Advanced Firehose Features" -c 95
# Track your analysis
deciduous add action "Traced backfill replay logic" -c 90
```

---

## Step 2: The Backfill Mechanism

When a client connects with a `cursor` query parameter, they aren't just looking for live updates; they want to "catch up" on events they missed.

### `replayEventsAfterCursor:toConnection:`
Look at `SubscribeReposHandler.m`. When a valid cursor is provided:
1.  **Database Query**: The handler queries the `service_events` table for all events with a sequence number greater than the cursor.
2.  **Sequential Replay**: The PDS streams these historical events to the client in order.
3.  **Handoff**: Once the replay is complete, the client automatically transitions to "Live Mode" for new incoming events.

**Technical Detail:**
Garazyk enforces a `maxReplayEventsPerConnection` (default 10,000) to prevent a single client from exhausting server resources during a massive backfill.

---

## Step 3: Cursor Validation and Safety

Not every cursor requested by a client is valid. The PDS performs several checks:

- **FutureCursor**: If the requested cursor is higher than the server's current sequence number, the connection is rejected.
- **InvalidCursor**: If the cursor is not a non-negative integer.
- **OutdatedCursor**: If the requested cursor is so old that the events have been pruned or exceed the replay window, the server sends an `#info` frame with the `OutdatedCursor` code.

---

## Step 4: Protecting the Server (Backpressure)

A high-volume Firehose can easily overwhelm a slow client. If the client's output buffer fills up, it can cause memory issues on the server.

### `ConsumerTooSlow`
Look at `sendEventData:toConnectionWithBackpressureCheck:` in `SubscribeReposHandler.m`:
- **Limit Checks**: The PDS tracks `pendingSendCount` and `pendingSendBytes` for every connection.
- **Dropping**: If a client exceeds these limits (default 512 pending sends or 16MB), the server sends a `ConsumerTooSlow` error frame and **immediately closes the connection**.

---

## Step 5: Verification and Manual Backfill

### Simulate a Backfill Request
You can test backfill by requesting a cursor from the past. First, find a valid sequence number from your server logs or metrics.

```bash
# Connect with a past cursor (e.g., 100)
# Note: You may need a specialized tool like 'wscat' to handle the protocol frames
wscat -c "ws://127.0.0.1:2583/xrpc/com.atproto.sync.subscribeRepos?cursor=100"
```

### Observe Backpressure
To test backpressure, you can use a script that connects and then "sleeps" without reading from the socket.

---

## Failure Modes to Watch For

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **Pruned Events** | `OutdatedCursor` info frame. | The client must perform a full repository sync (checkout) as they can no longer catch up via Firehose. |
| **Slow Consumer** | Connection closed with `ConsumerTooSlow`. | The client should use a faster parser or implement an internal buffer/queue to consume events faster. |
| **Database Latency** | Backfill stalls or slows down PDS writes. | Ensure the `service_events` table has an index on the sequence column and consider moving events to a dedicated store. |

---

## Summary

The advanced features of the Garazyk Firehose ensure that the network remains synchronized even during client outages or high-traffic spikes. By mastering cursors, backfill, and backpressure, you can build consumers that are both resilient and efficient.

Always use `deciduous` to document changes to Firehose logic or performance tuning.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
