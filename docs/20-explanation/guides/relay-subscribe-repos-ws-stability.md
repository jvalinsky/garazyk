---
title: Relay subscribeRepos WebSocket stability probe
---

# Relay subscribeRepos WebSocket stability probe

This document describes the experiment behind
`scripts/test/relay_ws_stability.ts`: how to measure whether a live Garazyk
relay drops `com.atproto.sync.subscribeRepos` subscribers, what the close
codes mean, and what a 2026-08-12 run against `relay.garazyk.xyz` showed.

Related reading:

- Architecture overview:
  [ATProto PDS architecture](../architecture/atproto_pds_architecture.md)
- Relay firehose tooling list:
  [Tooling and skills](../../11-reference/tooling-and-skills-documentation.md)
- Future-cursor semantics: [ADR 0012](../../adr/0012-relay-future-cursor-treated-as-outdated.md)
- In-tree federation notes (docs site): `Garazyk/docs-site/.../federation/websockets.md`

## Question under test

Operators reported that the production relay at `https://relay.garazyk.xyz`
(a few commits behind `main` at the time of the probe) **disconnects
sporadically**. The experiment asks:

1. Can a long-lived WebSocket to `subscribeRepos` stay open for minutes?
2. When it closes, is the close a **network failure** or a **relay policy**
   (backpressure)?
3. Does starting **at the live tip** (with a recent cursor) behave differently
   from starting **without a cursor** (full catch-up / backlog drain)?

## Probe design

`scripts/test/relay_ws_stability.ts` connects to:

```text
wss://<relay>/xrpc/com.atproto.sync.subscribeRepos[?cursor=N]
```

For a configurable wall-clock duration it:

| Behavior | Detail |
| --- | --- |
| Heartbeats | Periodic line with elapsed time, session count, disconnect count, events, bytes, last seq |
| Idle warn | Warns if the socket is open but no frames arrived for `--idle-warn` seconds |
| Disconnect log | ISO time, session index, age, WebSocket close code/reason, `wasClean`, events/bytes in session, last seq |
| Reconnect | Default on; resumes with the highest sequence seen |
| Optional `--no-parse` | Count frames without DAG-CBOR parse (faster drain during catch-up) |
| JSON summary | `--json-out` / `RELAY_WS_STABILITY_JSON_OUT` |
| Exit code | `2` if any unexpected disconnect occurred during the window |

Unit coverage: `scripts/test/relay_ws_stability_test.ts` (URL upgrade, CLI
defaults, `--no-parse`).

### How to run

```sh
# Default: 10 minutes against relay.garazyk.xyz, reconnect on
deno run -A scripts/test/relay_ws_stability.ts --duration 600

# Catch-up / backlog stress (no cursor) with faster drain
deno run -A scripts/test/relay_ws_stability.ts --duration 120 --no-parse

# Mid-stream / tip stability (use a seq from a prior probe)
deno run -A scripts/test/relay_ws_stability.ts \
  --duration 600 \
  --cursor 100877 \
  --json-out /tmp/relay-ws-near-tip.json

# Single connection, stop on first drop
deno run -A scripts/test/relay_ws_stability.ts --duration 300 --no-reconnect
```

Sibling tools (event pretty-printing, not stability-focused):

- `scripts/monitor_relay_firehose.ts`
- `scripts/relay_stream_report.ts`
- `scripts/dump_relay_firehose.ts`

## Close codes of interest

Garazyk’s firehose path applies **bounded-memory backpressure**. Relevant
closes observed on the wire:

| Code | Reason (typical) | Meaning |
| --- | --- | --- |
| **1008** | `ConsumerTooSlow` | Subscriber fell behind the firehose policy in `SubscribeReposHandler` |
| **1009** | `Outbound queue limit exceeded` | Per-connection outbound WebSocket queue tripped in `WebSocketConnection` |
| **1000** | (probe stop) | Client closed cleanly when the probe duration elapsed |

These are **policy closes**, not silent TCP resets. A consumer that reconnects
without a cursor (or with a very stale cursor) against a busy relay will often
see a burst of 1008/1009 while trying to drain backlog.

Implementation anchors:

- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` — `ConsumerTooSlow`
- `Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m` — outbound queue limit

## Experiment runs (2026-08-12)

Target: `https://relay.garazyk.xyz` (production, slightly behind `main`).
Client: Deno probe on a developer machine; JSON under `/tmp/garazyk-relay-probe/`.

### A — Catch-up smoke (90s, no cursor)

```sh
deno run -A scripts/test/relay_ws_stability.ts \
  --duration 90 --heartbeat 15 --idle-warn 60 \
  --json-out /tmp/garazyk-relay-probe/smoke-90s.json
```

**Result: 6 unexpected disconnects in ~15s of catch-up, then one stable
session once nearer the tip.**

#### Summary

| Metric | Value |
| --- | --- |
| Wall time | 90.0 s |
| Sessions | 7 |
| Reconnects | 6 |
| Unexpected disconnects | 6 |
| Total events | 1428 |
| Total bytes | 13.56 MiB (14 218 542 B) |
| Seq range | 94127 … 100877 |
| Longest session | 73.0 s (session 7, probe stop) |
| Shortest session | 57 ms (session 5) |
| Mean session | 10.7 s |
| Malformed frames | 0 |
| Exit code | 2 (disconnects present) |

#### Per-session timeline

| Session | Closed at (UTC) | Age | Code | Clean | Reason | Events | Bytes | Last seq |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 16:35:14.404 | 61 ms | 1009 | yes | `Outbound queue limit exceeded` | 21 | 202.3 KiB | 94127 |
| 2 | 16:35:16.977 | 364 ms | 1009 | yes | `Outbound queue limit exceeded` | 63 | 2.27 MiB | 94513 |
| 3 | 16:35:19.324 | 167 ms | 1009 | yes | `Outbound queue limit exceeded` | 33 | 983.4 KiB | 94846 |
| 4 | 16:35:21.949 | 452 ms | 1009 | yes | `Outbound queue limit exceeded` | 72 | 2.71 MiB | 97995 |
| 5 | 16:35:24.176 | 57 ms | 1009 | yes | `Outbound queue limit exceeded` | 38 | 257.6 KiB | 99676 |
| 6 | 16:35:28.813 | 903 ms | 1008 | yes | `ConsumerTooSlow` | 526 | 3.24 MiB | 100202 |
| 7 | 16:36:44.162 | 1m13s | 1000 | yes | `probe duration elapsed` | 675 | 3.92 MiB | 100877 |

Session 7 is a probe stop (not counted as an unexpected disconnect). Sessions
1–6 are the policy closes that tripped exit code 2.

#### Close-code tallies (unexpected only)

| Code | Reason | Count |
| --- | --- | --- |
| 1009 | `Outbound queue limit exceeded` | 5 |
| 1008 | `ConsumerTooSlow` | 1 |

Interpretation: connecting at the live tip **without** a cursor forces the
relay to stream a large backlog. A Deno client that parses every DAG-CBOR
frame cannot keep up; the relay correctly closes the socket under outbound
queue / ConsumerTooSlow policy. That looks “sporadic” to operators if clients
reconnect and immediately fall behind again.

### B — Near-tip stability (600s, `cursor=100877`)

Started from the last seq observed in run A:

```sh
deno run -A scripts/test/relay_ws_stability.ts \
  --duration 600 --cursor 100877 \
  --heartbeat 30 --idle-warn 90 --reconnect \
  --json-out /tmp/garazyk-relay-probe/near-tip-600s.json
```

**Result: full 10-minute window completed with no unexpected disconnects.**

#### Summary

| Metric | Value |
| --- | --- |
| Wall time | 10 m 00 s |
| Cursor | 100877 |
| Sessions | 1 |
| Reconnects | 0 |
| Unexpected disconnects | 0 |
| Events received | 863 |
| Bytes | 5.31 MiB |
| Last seq at close | 101740 |
| Session age | ~10 m (closed with code 1000, probe stop) |
| Exit | 0 (no unexpected disconnects) |

#### Heartbeat samples (during the open session)

Heartbeats report cumulative totals only after a session ends, so in-session
lines showed `events=0` until close; the socket stayed up throughout.

| Elapsed | Sessions | Disconnects | Socket |
| --- | --- | --- | --- |
| 30 s … 10 m (every 30 s) | 1 | 0 | open |
| 10 m 00 s | 1 | 0 | closed by probe (`1000`) |

Idle stretches with no frames, then later traffic (863 events by the end),
without any policy close — a successful at-tip stability signal.

Interpretation: once a subscriber is **at or near the tip**, the connection
can stay up for a full 10-minute window without policy closes. Mid-stream /
idle behavior does not match the catch-up failure mode.

### Side note: `getHostStatus`

| Request | Result |
| --- | --- |
| `GET /xrpc/com.atproto.sync.getHostStatus?hostname=relay.garazyk.xyz` | HTTP **404** |
| `GET /` (HTTPS root) | HTTP **302** |

`getHostStatus` is about upstream host status, not subscriber health; it was
not used as a pass/fail for the WebSocket experiment.

## Conclusions

1. **Verified:** the live relay does close `subscribeRepos` WebSockets under
   load — but with **explicit policy codes** (`1008` / `1009`), not unexplained
   network drops.
2. **Primary failure mode for “sporadic disconnect” reports:** catch-up /
   backlog drain when clients reconnect without a recent cursor, or when they
   cannot drain as fast as the relay produces.
3. **Near-tip / idle sessions** can remain open for a full **10-minute** window
   without disconnects (run B: 1 session, 0 policy closes, 863 events).
4. **Operator checklist** when investigating production drops:
   - Log WebSocket close **code** and **reason** on the client.
   - Confirm reconnects pass the **last durable seq** as `cursor`.
   - Compare client drain rate vs relay outbound queue / ConsumerTooSlow
     thresholds on the deployed revision.
   - Separate “cannot catch up” from “drops while already at tip.”

### Follow-up plan

Do **not** loosen backpressure as the fix. Execution plan:
[workstream 02 A8](../../plans/workstreams/02-core-architecture-and-reliability.md)
(consumer/ops hygiene first; optional relay observability polish only with
evidence).

## Consumer inventory (A8.1)

Garazyk-owned `subscribeRepos` clients and checklist status after A8.2:

| Consumer | Durable cursor | Reconnect with cursor | Close code/reason logged | Fast drain / notes |
| --- | --- | --- | --- | --- |
| AppView ingest (`GZAppViewIngestEngine` + `ATProtoRelayClient`) | Yes — DB checkpoint per relay | Yes — `RelayClient` resumes `currentSeq` | Yes — `FirehoseCloseCodeKey` / reason + `backpressure=` in logs (2026-08-12) | Event work on ingest queues; WS path is Firehose decode |
| Beskid firehose invalidator | Yes — `firehose.cursor` file | Yes — `subscribeWithCursor:` on reconnect | Yes — same close-code logging | Invalidation-only; light per-event work |
| Zuk upstream (`RelayUpstreamManager` + `RelayClient`) | Yes — per-upstream seq in manager | Yes — RelayClient | Yes — via RelayClient close logs | Upstream fan-in; same client stack |
| `@garazyk/gruszka` `FirehoseClient` | In-memory `lastSeq` only | Caller must reconnect; passes `lastSeq` if set | Yes — code/reason/`backpressure` on `onclose` | Short-lived scripts; use `relay_ws_stability` / `monitor_relay_firehose` for long runs |
| `scripts/test/relay_ws_stability.ts` | Resume from last seq | Yes | Yes | Optional `--no-parse` for catch-up |
| `scripts/monitor_relay_firehose.ts` | Resume from last seq | Yes | Partial (logs close) | Stats-oriented |
| Hubble / external mirrors | Outside Garazyk | — | — | Prefer cursors; not owned here |

**Exceptions:** none for Garazyk-owned long-lived services. Gruszka’s client remains a library primitive without auto-reconnect by design.

## Operator runbook (A8.3)

### Classify a disconnect

| Close | Meaning | Action |
| --- | --- | --- |
| `1008` + `ConsumerTooSlow` | Firehose pending-send/byte policy | Client too slow or catching up; resume with last seq after short backoff |
| `1009` + `Outbound queue limit exceeded` | WebSocket outbound queue policy | Same as above |
| Unclean / non-1000 without those reasons | Network / proxy / process | Check path, deploy health, IPv6, proxy idle timeouts |
| `1000` | Normal close | Usually client stop |

Defaults (tunable via env on the firehose handler): `512` pending sends, `16 MiB` pending bytes (`PDS_FIREHOSE_MAX_PENDING_SENDS` / `PDS_FIREHOSE_MAX_PENDING_BYTES`). Do **not** raise these without probe evidence that a *fast* cursor-correct consumer still dies.

### Reproduce

```sh
# Catch-up (expect policy closes without cursor)
deno run -A scripts/test/relay_ws_stability.ts \
  --relay-url https://relay.garazyk.xyz --duration 90 \
  --json-out /tmp/relay-ws-catchup.json

# Near-tip (expect 0 unexpected disconnects)
deno run -A scripts/test/relay_ws_stability.ts \
  --relay-url https://relay.garazyk.xyz --duration 600 \
  --cursor <near-tip-seq> \
  --json-out /tmp/relay-ws-neartip.json
```

Alert on **bursts of 1008/1009 from the same peer**, not on every disconnect.
A quiet near-tip socket with idle heartbeats is healthy.

### Deploy variable

When investigating prod, note the running `zuk` revision vs `main`. Stale
binaries are a variable; the 2026-08-12 probe already showed policy closes on
the then-deployed build, so upgrading alone may not “fix” catch-up kills.
## What this experiment does not measure

- Correctness of event payload / MST / signature validation
- WAN latency or multi-region paths
- Proxy / CDN idle timeouts in front of the relay (configure long-lived
  WebSocket upgrades separately)
- Whether upgrading the production binary to current `main` changes thresholds
- Concurrent multi-subscriber load on the relay

## Implementation map

| Concern | Location |
| --- | --- |
| Stability probe | `scripts/test/relay_ws_stability.ts` |
| Probe unit tests | `scripts/test/relay_ws_stability_test.ts` |
| Live firehose monitor | `scripts/monitor_relay_firehose.ts` |
| Bounded stream report | `scripts/relay_stream_report.ts` |
| ConsumerTooSlow policy | `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m` |
| Outbound queue close | `Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m` |
| Deterministic ConsumerTooSlow scenario | `scripts/scenarios/scenarios/33_tortoise_consumer.ts` |

## See also

- [STAR-lite v0 vs CAR export benchmark](star-lite-vs-car-export-benchmark.md)
  (same “document the experiment” pattern)
- [NixOS build and deployment](NIXOS.md) (relay admin / firehose smoke notes)
- [Deployment](DEPLOYMENT.md)
