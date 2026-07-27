---
phase: 17
title: WebSocket RFC conformance and HTTP framing
status: in-progress
agent: worker
depends_on: []
---

# Phase 17: WebSocket RFC conformance and HTTP framing

## Progress

Recovery started 2026-07-27: four isolated implementation commits were
rebased onto current `main`. The recovered work is being reread and verified
against S10, the named RFC sections, registered XCTest execution, and the
four firehose regression scenarios before it can be marked complete.

## Mission

Close the unauthenticated, unbounded ingress defects in workstream 01 § S10
slices 1-4. The WebSocket codec today enforces per-frame limits but no
aggregate limits, and validates frame *contents* but not frame *sequences*.
The firehose is a public endpoint, so every gap here is reachable without
credentials.

RFC 6455 is the contract; read §5.1 (masking), §5.4 (fragmentation), and §5.5
(control frames) before writing code. RFC 7230 §3.3.3 governs the
`Content-Length` slice.

## Read first

- `docs/plans/workstreams/01-security-and-protocol-correctness.md` § S10
  (authoritative; if this prompt disagrees, the workstream wins)
- `Garazyk/Sources/Sync/WebSocket/WebSocketCodec.m` — the whole file is in
  scope; it is only ~300 lines
- `Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:812-818` — the
  `isKindOfClass:` discipline this codebase already applies to query params.
  Match that standard.
- Scenarios 33, 65, 66, and 95 (`packages/hamownia`) — they exercise this
  codec and must still pass

## Decisions already taken (do not re-litigate)

- Full RFC 6455 conformance: fail the connection on unmasked client frames,
  oversized or fragmented control frames, reserved opcodes, set RSV bits, and
  invalid fragmentation sequences. Not log-and-count — fail closed.

## Scope and order

One coherent slice per commit.

1. **Aggregate caps.** Add a total-reassembly limit across `self.fragments`
   (`WebSocketCodec.m:141`), enforced as fragments accumulate rather than when
   FIN arrives at `:144-147`. Enforce RFC 6455 §5.5 on control frames: ≤125
   byte payload, never fragmented. Bound the ping payload echoed by
   `Sync/WebSocket/WebSocketConnection.m:517-518`, which currently returns a
   16 MB pong for a 16 MB ping.
2. **Frame validation.** Enforce masking on client frames (`:70` reads the bit
   and ignores it). Fail on reserved opcodes 0x3-0x7 and 0xB-0xF, currently
   silently ignored at `:122` and `:224`. Fail on set RSV bits, never checked.
   Fix the fragmentation state machine at `:128-160`: reject a new non-FIN
   data frame while a fragmented message is in progress (today it overwrites
   `fragmentOpcode` and merges payloads) and reject a CONTINUE with no
   preceding start (today it accumulates, then silently drops the message when
   `eventForOpcode:0` returns nil).
3. **Overflow guard and buffer cost.** Guard the `headerLength + payloadLength`
   addition at `:101` independently of `maxFrameSize`, which is a public
   settable property. Replace the per-call `replaceBytesInRange:` compaction at
   `:167` with a read-offset buffer; today a stream of small frames across many
   reads is quadratic.
4. **HTTP framing.** In `Network/Http1Parser.m:110-115`, reject duplicate or
   conflicting `Content-Length` — `CFHTTPMessageCopyHeaderFieldValue` joins
   them as `"5, 10"` and `longLongValue` silently takes `5`. Parse the value
   strictly (digits only; no leading whitespace, sign, or trailing garbage).
   The existing `Transfer-Encoding` + `Content-Length` rejection at `:198-199`
   is the pattern to follow. Also validate the firehose env limits at
   `Sync/Firehose/SubscribeReposHandler.m:134,137`, which currently accept a
   typo as 0.

## Acceptance gate

Negative tests, each asserting a connection close with the correct RFC close
code rather than acceptance or silent ignoring:

- an unmasked client frame
- a 200-byte ping; a fragmented control frame
- each reserved opcode (0x3-0x7, 0xB-0xF)
- a set RSV1/RSV2/RSV3 bit
- a CONTINUE frame with no preceding start
- a second non-FIN data frame while a fragment is in progress
- a fragment sequence whose total exceeds the aggregate cap

Plus: a 16 MB ping must not produce a 16 MB pong; two conflicting
`Content-Length` headers must yield 400; and a malformed
`PDS_FIREHOSE_MAX_PENDING_SENDS` must be rejected loudly rather than becoming
0.

Regression: scenarios 33, 65, 66, and 95 must still pass — they drive this
codec, and slices 1-2 are exactly the kind of change that breaks them.

New suites need their header imported and the class registered in
`Garazyk/Tests/test_main.m` plus a cmake reconfigure, or they silently run
zero tests. Then the global gates:

```bash
deno task check
deno task lint
deno task test
cmake --build build --target AllTests --parallel 4
./build/tests/AllTests
```

Bounded parallelism only (`--parallel 4`).

## Rollback

Each slice is a single-commit revert. Slices 1-2 turn currently accepted
frames into connection closes and therefore carry genuine interop risk. If a
real peer breaks, capture its exact frame bytes as a fixture and decide
explicitly whether the peer or the codec is wrong before loosening anything —
do not relax a check to make a client work without recording why.

## On completion

Update S10 slices 1-4 status in workstream 01 with commit hashes, then set
`status: complete` here. If any conformance change proves visible to real
peers, record it as an ADR.
