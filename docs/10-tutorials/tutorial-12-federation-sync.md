---
title: "Tutorial 12: Federation & Sync"
---

# Tutorial 12: Federation & Sync

## Overview

Garazyk does not exist in a vacuum. It is part of a federated network where data flows between Personal Data Servers (PDS), Relays, and AppViews. This tutorial explains how your PDS synchronizes its state with the rest of the network and how it consumes data from upstream Relays.

**Learning Objectives:**
- Understand the roles of PDS, Relay, and AppView in the federation model.
- Trace the lifecycle of an upstream connection in `RelayClient.m`.
- Analyze the reconnection and cursor management logic in `RelayUpstreamManager.m`.
- Verify federation health and event flow.

**Estimated Time:** 40-50 minutes

## Prerequisites

- Complete [Tutorial 5: Firehose](./tutorial-5-firehose).
- Familiarity with WebSocket basics and JSON lines.
- `deciduous` CLI tool installed.

---

## Step 1: Track the Goal with Deciduous

Record your intent to study the federation layer:

```bash
deciduous add goal "Audit Federation and Sync Logic" -c 95
# Track your analysis
deciduous add action "Traced RelayClient cursor persistence" -c 90
```

---

## Step 2: The Federation Topology

In the AT Protocol, your PDS is the authority for your data. To make that data discoverable, the PDS "pushes" events to a **Relay** via a firehose. Conversely, your PDS may "pull" data from a Relay to stay updated on other users.

- **PDS**: Your personal server, where you create and store records.
- **Relay**: A high-volume aggregator that consumes firehoses from many PDSs and re-broadcasts them.
- **AppView**: A consumer that processes firehose data into high-level features like global search or global feeds.

---

## Step 3: Subscribing to Upstream Relays

Garazyk uses the `RelayClient` to connect to upstream Relays. Look at `establishConnection` in `Garazyk/Sources/Sync/Relay/RelayClient.m`:

1.  **WebSocket Handshake**: It initiates a connection to `/xrpc/com.atproto.sync.subscribeRepos`.
2.  **Cursor Management**: If a `currentSeq` is known, it passes it as a `cursor` query parameter. This allows the PDS to resume exactly where it left off, avoiding data gaps.
3.  **Event Handling**: It implements the `FirehoseSubscriptionDelegate` to process `Commit`, `Identity`, and `Handle` events.

---

## Step 4: Managing Multiple Upstreams

The `RelayUpstreamManager` acts as an orchestrator for one or more `RelayClient` instances.

### Resilience and Reconnection
Look at `scheduleReconnectForUpstream:` in `Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m`:
- **Exponential Backoff**: If a connection fails, the manager schedules a retry with increasing delays.
- **Auto-Reconnect**: By default, the manager will indefinitely attempt to restore connections to your configured upstreams.
- **Health Monitoring**: The manager tracks the status of each host (`Active`, `Disconnected`, `Error`) and exposes this via metrics.

---

## Step 5: Persistence and State

The PDS must remember its position in each upstream's firehose. `RelayClient` maintains a `cursorStorage` map (backed by the PDS database) to save the latest `seq` (sequence number) received from each repo.

**Technical Detail:**
When the PDS restarts, it reads these cursors from the database and uses them to re-establish its "place in line" with the Relays.

---

## Step 6: Verification and Debugging

### Check Active Upstreams
You can see which Relays your PDS is currently connected to:

```bash
# Assuming an admin tool or API exposure
curl -sS http://127.0.0.1:2583/api/pds/upstreams | jq .
```

### Monitor Event Flow
The `RelayMetrics` class tracks the number of events received and the latest sequence numbers:

```bash
curl -sS http://127.0.0.1:2583/_metrics | grep relay_
```

### Trace WebSocket Traffic
If you have access to the PDS logs, look for `RelayClient` entries to see the handshake and cursor usage:

```bash
tail -f pds.log | grep RelayClient
```

---

## Failure Modes to Watch For

| Failure Mode | Symptom | Mitigation |
| --- | --- | --- |
| **Cursor Gap** | Missing events after a PDS restart. | Check if the cursor was correctly persisted to the database before shutdown. |
| **Reconnection Storm** | High CPU/Network due to rapid retries. | Ensure the `RelayUpstreamManager` is using a sane `baseReconnectInterval` and `maxReconnectAttempts`. |
| **Authentication Failed** | Status 401 on connect. | The upstream Relay requires a valid `accessToken` which is missing or expired in your configuration. |
| **Backpressure** | `RelayEventBuffer` full or dropped events. | The PDS is consuming events slower than the Relay is sending them. Optimize the `RelayDownstreamHandler`. |

---

## Summary

Federation is what turns a standalone PDS into a participant in a global network. By mastering `RelayClient` and `RelayUpstreamManager`, you can ensure that your PDS stays in sync with the network and provides a seamless experience for your users.

Always use `deciduous` to document changes to federation settings or sync logic.

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)
