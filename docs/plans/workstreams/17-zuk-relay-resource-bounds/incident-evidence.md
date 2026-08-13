---
title: Zuk Relay Resource Incident Evidence
status: evidence
last_verified: 2026-08-13
---

# Zuk relay resource incident evidence

This file preserves the evidence that opened
[workstream 17](../17-zuk-relay-resource-bounds.md). It is not a second
backlog. Measurements are dated observations; source findings are tied to the
repository state at `171ba127`; estimates and causal inferences are labeled.

## Production observation

Host and unit: `bingus`, systemd unit `zuk`, observed 2026-08-13.

| Signal | Observation |
| --- | --- |
| Host memory | 7.7 GiB RAM total; about 7.5 GiB in use |
| Host swap | About 8.0 GiB of 8.8 GiB in use |
| `zuk` memory | About 6.8 GiB RSS and 8.2 GiB swap; predominantly anonymous memory |
| Unit lifecycle | Active since 2026-08-11; zero recorded systemd restarts |
| Unit I/O | About 53 GiB read and 58 GiB written cumulatively |
| Unit network | About 1.9 GiB received and 91.7 GiB sent cumulatively |
| Downstream symptom | Repeated loopback subscriptions without a cursor, 10,000-event replay, outbound queue pressure, close, reconnect |
| One-minute sample | About 30 connections, 49 output-queue overflows, 8,465 critical backpressure warnings |
| Ten-minute sample | About 11,500 critical backpressure warnings |
| Validation | About 199,000 signature failures for about 199,000 commit events; deployment mode was `log-only` |
| Reported upstreams | Health snapshot reported 666 upstream connections, inconsistent with 27 established TCP sockets on the host |

The final telemetry refresh did not complete because new SSH connections began
timing out under load. The loopback client's PID was not identified without
privileged socket ownership data. Phase 37 must repeat a bounded baseline
capture before deployment and must not assume the unidentified client is safe
to terminate.

## Confirmed source findings

| Finding | Evidence | Classification |
| --- | --- | --- |
| Omitted cursor replays from zero | `SubscribeReposHandler.m` sets `requestedReplayCursor` to `0` when `hasCursor` is false, after logging live-only behavior | Confirmed protocol bug |
| Replay producer ignores connection pressure | Replay iterates retained events and calls `sendMessage:` without a producer-visible admission result or prompt cancellation | Confirmed resource amplifier |
| Relay ingress is unbounded | `RelayClient` and `RelayDownstreamHandler` enqueue full events onto asynchronous GCD queues without count or byte limits | Confirmed unbounded retention path |
| Validation can block the serial drain | `RelayEventValidator` performs synchronous DID resolution; `DIDPLCResolver` may wait up to six seconds on a miss | Confirmed throughput bottleneck |
| Replay payloads are held in memory | `RelayEventBuffer` retains complete encoded events, defaults to 100,000 entries, and removes index zero once full | Confirmed memory and O(n) churn |
| Time retention is ineffective | `pruneExpired` exists but has no production caller | Confirmed configuration/behavior mismatch |
| P-256 repository keys fail | Relay key extraction and `RepoCommit` verification are secp256k1-only; a test explicitly expects P-256 rejection | Confirmed protocol gap |
| Public crawl lacks fleet limits | `requestCrawl` can add a validated upstream, but has no global active-host cap, new-host/day cap, or per-client rate limit | Confirmed admission-control gap |
| Connected-upstream metric is not authoritative | Increment/decrement lifecycle counter diverged from observed sockets and the manager's actual upstream set | Confirmed observability defect; exact callback imbalance still to prove |

Primary local paths:

- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m`
- `Garazyk/Sources/Sync/Relay/RelayClient.m`
- `Garazyk/Sources/Sync/Relay/RelayDownstreamHandler.m`
- `Garazyk/Sources/Sync/Relay/RelayEventBuffer.m`
- `Garazyk/Sources/Sync/Relay/RelayEventValidator.m`
- `Garazyk/Sources/Identity/DIDPLCResolver.m`
- `Garazyk/Sources/Network/RelayXrpcRoutePack.m`
- `nixos/modules/zuk.nix`

## Protocol and reference-relay comparison

The AT Protocol event-stream contract says that omitting `cursor` starts at
the current stream position. A retained-window replay is requested with a
cursor; an outdated cursor produces an informational error and the oldest
available position. Events must be persisted before transmission so sequence
numbers are not reused after restart.

Primary specifications:

- <https://atproto.com/specs/event-stream>
- <https://atproto.com/specs/sync>
- <https://atproto.com/specs/cryptography>

The Indigo reference was inspected from
`bluesky-social/indigo@52c38ce3daca2e85a9f70cf052b475506463018e`
(2026-08-12):

- no `since` value attaches a subscriber to live broadcast without replay;
- each subscriber has a bounded channel and slow consumers are dropped once;
- each event is pre-serialized once and shared;
- replay is stored in segmented files, rotated by event count, with a
  configurable retention window and periodic garbage collection;
- relay configuration includes account limits, new-host/day limits, and a
  switch to disable request-crawl.

Reference paths:

- <https://github.com/bluesky-social/indigo/blob/52c38ce3daca2e85a9f70cf052b475506463018e/cmd/relay/stream/eventmgr/event_manager.go>
- <https://github.com/bluesky-social/indigo/blob/52c38ce3daca2e85a9f70cf052b475506463018e/cmd/relay/stream/persist/diskpersist/diskpersist.go>
- <https://github.com/bluesky-social/indigo/blob/52c38ce3daca2e85a9f70cf052b475506463018e/cmd/relay/main.go>

Indigo is a design reference, not a source of safe defaults for an 8 GiB
host. Workstream 17 adopts bounded queues and disk persistence while deriving
Garazyk's limits from measured payload sizes and canary behavior.

## Causal assessment

### High confidence

The omitted-cursor bug caused the observed replay/reconnect loop. The event
stream specification, Zuk source, Indigo behavior, and matching production
logs all agree.

The current implementation has no upper bound on memory retained by queued
ingress events. Even if it was not the only source of the 6.8 GiB RSS, it is a
resource-exhaustion condition that must be removed.

### Likely but not directly measured

The majority of anonymous memory was probably split between the 100,000-event
replay array and queued decoded events waiting for serial validation. There is
no queue-depth or retained-byte metric from the incident, so the exact split
cannot be claimed.

The large outbound total is likely dominated by repeated catch-up delivery.
At 91.7 GiB over roughly 2.75 days, the observed output rate is about 33 GiB
per day, far above the roughly 0.7 GiB/day average ingress implied by the unit
network counters.

### Open questions for Phase 37

1. Which loopback process reconnects without a cursor, and does it persist a
   cursor after successful processing?
2. What are p50, p95, p99, and maximum encoded and decoded event sizes over a
   representative bounded sample?
3. What is the actual connected/configured upstream count from the manager's
   synchronized set?
4. How many signature failures are P-256, bad DID/key resolution, malformed
   commits, wrong keys, or genuine invalid signatures?
5. Does the current output sequence survive restart without reuse?

## Baseline recapture contract

Before the first production change, capture and retain a dated artifact with:

```text
git revision and binary identity
systemctl show/status for zuk
cgroup memory.current, memory.peak, memory.swap.current, memory.events
process RSS, virtual memory, thread count, and file-descriptor count
actual configured/connected upstream set sizes
ingress/output/replay queue event counts and bytes when available
event payload size histogram
one-minute categorized log counts
unit network and block-I/O counters
health and Relay admin snapshots
```

Do not include credentials, authorization headers, DID private material, raw
repository records, or complete DID documents in the artifact.
