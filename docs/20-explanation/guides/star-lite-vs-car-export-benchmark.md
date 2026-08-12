---
title: STAR-lite v0 vs CAR export benchmark
---

# STAR-lite v0 vs CAR export benchmark

This document describes the experiment behind
`scripts/test/star_lite_export_benchmark.ts`: what it measures, how it is
wired, what success looks like, and what it deliberately does not cover.

For the format catalog and operator guidance, see
[Repository export formats](repo-export-formats.md). Format authority lives in
[ADR 0034](../../adr/0034-star-lite-v0-interop-export.md).

## Question under test

Garazyk can export a full AT Protocol repository through
`com.atproto.sync.getRepo` in more than one wire encoding. This experiment
compares the two that matter for Microcosm-style mirrors:

| Format | Media type | What it carries |
| --- | --- | --- |
| **CAR** | `application/vnd.ipld.car` | IPLD blocks: commit, MST nodes, and records — the default interop format |
| **STAR-lite v0** | `application/x.microcosm.star-lite` | Microcosm wire format: small header (MST root CID + partial commit) plus a flat `key → record` stream — no MST node blocks on the wire |

Both encodings represent the **same logical repo**. The experiment asks whether
STAR-lite v0 is meaningfully **smaller** and/or **faster** to generate and
transfer at realistic repo sizes, without losing post content.

That tradeoff matters for Hubble-style mirrors and federation backfill:
operators may prefer STAR-lite v0 when talking to Microcosm consumers, but only
if size and latency hold up at scale.

## Topology

The harness starts a **local binary network** (no Docker):

```
campagnola (PLC)  :2582
kaszlak (PDS)     :2583
kaszlak (PDS2)    :2587
kaszlak (PDS3)    :2588
```

PDS rate limiting is disabled for the run so seeding is not throttled.

Default layout (unless overridden by env vars):

| Knob | Default | Effect |
| --- | --- | --- |
| PDS instances | 3 | `pds`, `pds2`, `pds3` |
| Accounts per PDS | 5 | 15 repos total |
| Total export payload target | 10 MB | Split evenly → ~667 KB per account |
| Post text length | 280 chars | `app.bsky.feed.post` max graphemes |

A **quick** mode (`STAR_LITE_BENCH_QUICK=1`) uses ~500 KB / 1 PDS / 2 accounts
for a smoke check. A **100 MB** run sets
`STAR_LITE_BENCH_TARGET_BYTES=100000000` with the same 3×5 topology
(~6.67 MB per account).

## Phase 1: Seeding

For each account the harness:

1. Calls `com.atproto.server.createAccount` on one of the PDS instances.
2. Creates posts in batches (50–100 at a time) via
   `com.atproto.repo.createRecord`.
3. After each batch, samples `getRepo` with STAR-lite `Accept` to measure
   current export size.
4. Keeps posting until that export size is at least the per-account target.
5. Refreshes the session JWT every 100 posts (and on `ExpiredToken`) so long
   seeds do not die mid-run.

Post text is deterministic:

```text
star-lite-bench {label} post {index} xxx…
```

padded to 280 characters. That gives stable, compressible-but-not-trivial
payload and makes correctness checks unambiguous.

Seeding dominates wall-clock time. At 100 MB the run is on the order of
~270k posts across 15 accounts.

## Phase 2: Export measurement

For each seeded account the harness calls `getRepo` twice with the same DID:

1. `Accept: application/vnd.ipld.car`
2. `Accept: application/x.microcosm.star-lite`

For each export it records:

| Metric | How it is measured |
| --- | --- |
| **Size** | Response body byte length |
| **Latency** | Wall-clock `fetch` time (generation + serialization + HTTP transfer on loopback) |
| **Peak RSS** | Max resident set of the owning PDS process (`ps -o rss=`), sampled every 50–100 ms during the export |
| **Avg CPU** | Mean `%CPU` over those samples |
| **Disk Δ** | `du -sk` on the PDS data directory before and after the export |

The PDS PID comes from the binary-service pidfile so cost is attributed to the
correct `kaszlak` instance.

Results are printed as a human summary and optionally written as JSON
(`STAR_LITE_BENCH_JSON_OUT`).

## Phase 3: Correctness

The harness checks **cross-format agreement**:

1. Parse the STAR-lite v0 archive and extract all `app.bsky.feed.post/*`
   records; decode CBOR; collect sorted post texts.
2. Walk CAR blocks with `@ipld/car`; find post records; collect sorted texts.
3. Pass if counts match and every sorted text is identical.

A run fails if any seeded repo mismatches.

As of workstream 01 S21 (2026-08-12), `com.atproto.repo.listRecords` supports
keyset cursor pagination, so a full collection walk is now possible and can be
added later as an optional independent ground-truth check. The benchmark still
uses cross-format agreement by default.

## Configurations on bingus

A typical large-host run chain:

1. **Quick smoke** (~500 KB) — verify binaries, seeding, export, and teardown.
2. **10 MB default** — multi-PDS sanity at a size that still finishes in a
   reasonable time; write `star-lite-10mb.json`.
3. **100 MB** — fig-scale numbers for size / latency / RSS; write
   `star-lite-100mb.json`.

Example:

```sh
STAR_LITE_BENCH_QUICK=1 ./scripts/test/star_lite_export_benchmark.sh

STAR_LITE_BENCH_JSON_OUT=/tmp/star-lite-10mb.json \
  ./scripts/test/star_lite_export_benchmark.sh

STAR_LITE_BENCH_TARGET_BYTES=100000000 \
  STAR_LITE_BENCH_JSON_OUT=/tmp/star-lite-100mb.json \
  ./scripts/test/star_lite_export_benchmark.sh
```

Environment knobs (also listed in [repo-export-formats](repo-export-formats.md)):

| Variable | Default | Purpose |
| --- | --- | --- |
| `STAR_LITE_BENCH_TARGET_BYTES` | `10000000` | Approx total repo payload across all accounts |
| `STAR_LITE_BENCH_PDS_COUNT` | `3` | PDS instances |
| `STAR_LITE_BENCH_ACCOUNTS_PER_PDS` | `5` | Accounts seeded per PDS |
| `STAR_LITE_BENCH_QUICK` | off | When `1`, ~500 KB / 1 PDS / 2 accounts |
| `STAR_LITE_BENCH_JSON_OUT` | — | Optional machine-readable summary path |
| `STAR_LITE_BENCH_ACCEPT_ENCODING` | — | Optional `Accept-Encoding` for timed size/latency fetches (e.g. `zstd`). Correctness still uses identity archives |
| `BUILD_DIR` | `build/bin` | Directory containing `kaszlak` and `campagnola` |

## What we expect to see

Working hypotheses, calibrated by a completed ~500 KB smoke on bingus
(~674 posts/account):

| Metric | Smoke observation | Expectation at 10–100 MB |
| --- | --- | --- |
| **Size** | STAR-lite ~80.7% of CAR (~19% smaller) | Same ballpark. STAR-lite omits MST interior nodes; overhead difference is mostly per-record framing plus a ~223 B header |
| **Latency** | ~1.00× (parity on loopback) | STAR-lite equal or modestly faster — less to serialize. Absolute times grow with size; ratio should stay near parity unless CAR's block-graph walk dominates |
| **Peak RSS** | ~307 MB for both (warm PDS) | Similar across formats. Both paths walk the same repo; large absolute differences would be surprising |
| **CPU** | ~87% during export | High on both; export is CPU-bound serialization |
| **Disk Δ** | 0 KB | Export is read-only |
| **Correctness** | OK | Must stay OK at every scale |

Size savings should scale roughly linearly with repo size for this post-heavy
workload. Latency is less predictable; we do **not** expect an
order-of-magnitude win on loopback.

We also do **not** expect STAR-lite to use dramatically less memory: the PDS
still loads the repo to export it. The experiment measures export-path cost,
not cold-start migration cost.

## Results (bingus, 2026-08-12)

### Caveat

These numbers are from a host that was also running a live relay (and other
services) at the same time. CPU, latency, and RSS are **contended** —
treat absolute times and resource samples as directional, not as a clean
isolated baseline. Size and correctness are unaffected by that load.

### 10 MB default run (`targetBytes=10000000`, 3×5 accounts)

| Aggregate | CAR | STAR-lite | STAR-lite / CAR |
| --- | ---: | ---: | ---: |
| Total export bytes | 12 686 640 | 10 248 195 | **0.808** (~19.2% smaller) |
| Total generation+transfer ms | 92 484 | 32 230 | **0.348** |
| Peak RSS (max over run, KB) | 924 820 | 928 080 | ~1.00 |

Per-account shape:

- **15 / 15** repos passed cross-format correctness (1774 posts each).
- STAR-lite size was identical across accounts (**683 213 B**, header 223 B) —
  expected for equal post counts and fixed-length text.
- CAR sizes clustered ~842–849 KB (MST layout differs slightly by DID/rkey set).
- Per-export wall times were noisy: early/cold CAR exports on a PDS were much
  slower; later pairs were near parity and occasionally CAR was faster. The
  aggregate **0.35×** time ratio is dominated by those cold starts — do not
  read it as a stable 3× win.
- Disk Δ during export was 0 KB for STAR-lite and usually **+32 KB** for CAR
  (likely WAL/page-cache noise, not export payload).
- Avg CPU samples sat ~32–33% on both formats (lower than the quiet smoke’s
  ~87%, consistent with a busy host).

Larger targets (e.g. 100 MB) were still running when this section was written;
add those rows here when they finish.

HTTP `Content-Encoding` (zstd/gzip) for exports landed as workstream 02 **A9**
(2026-08-12). Re-run with `STAR_LITE_BENCH_ACCEPT_ENCODING=zstd` to measure
compressed wire sizes; see [repo-export-formats](repo-export-formats.md).

## Success criteria

A run is green when:

1. Every seeded repo passes cross-format correctness.
2. The optional JSON summary is written when requested.
3. STAR-lite is smaller than CAR (a reverse result would be surprising and
   worth investigating).
4. Seeding completes without auth/token failures.

## What this experiment does not measure

- End-to-end migration (`importRepo` on a remote client)
- Incremental export (`since` cursor) — STAR-lite v0 is full-repo only
- STAR-L0 or local STAR-lite v2 (different formats and media types)
- WAN network transfer (measurements are loopback only)
- Concurrent multi-client load during export
- Non-post record types (follows, likes, blobs) — seeded repos are post-only

## `listRecords` pagination (resolved)

`com.atproto.repo.listRecords` now keyset-paginates on `rkey` (default order
**DESC**, exclusive cursor, `cursor` returned when the page is full). See
workstream 01
[S21](../../plans/workstreams/01-security-and-protocol-correctness.md).

**Behavioral note:** first-page order changed from ASC to DESC to match the
Bluesky PDS. Clients that assumed ascending rkeys on the first page need to
pass `reverse=true` or follow returned cursors.

## Implementation map

| Concern | Location |
| --- | --- |
| Benchmark driver | `scripts/test/star_lite_export_benchmark.ts` |
| Shell wrapper | `scripts/test/star_lite_export_benchmark.sh` |
| Size / latency / RSS / CPU / disk helpers | `scripts/lib/deno/repo_export_benchmark.ts` |
| STAR-lite v0 parser (Deno) | `scripts/lib/deno/star_lite_v0.ts` |
| PDS export producers | `Garazyk/Sources/Services/PDS/PDSRepositoryService+Export.m` |
| Accept negotiation | `Garazyk/Sources/Network/XrpcSyncPack.m` |
| `listRecords` handler (cursor gap) | `Garazyk/Sources/Network/XrpcRepoPack+Records.m` |
| `listRecords` service (cursor ignored) | `Garazyk/Sources/Services/PDS/PDSRecordService+RecordCRUD.m` |

## See also

- [Repository export formats](repo-export-formats.md)
- [ADR 0034 — STAR-lite v0 interoperable export](../../adr/0034-star-lite-v0-interop-export.md)
- [ADR 0009 — STAR versioning and variants](../../adr/0009-star-versioning-and-variants.md)
- Upstream STAR-lite notes: https://tangled.org/microcosm.blue/star
