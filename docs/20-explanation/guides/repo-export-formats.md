---
title: Repository export formats
---

# Repository export formats

AT Protocol repositories can be transferred as whole archives through
`com.atproto.sync.getRepo` and `com.atproto.sync.getCheckout`. Garazyk
supports several encodings. They all carry the same logical repo; they differ
in wire shape, how easy it is to verify the MST, and which peers negotiate
them.

This page is a decision guide. Format authority and history live in
[ADR 0009](../../adr/0009-star-versioning-and-variants.md) and
[ADR 0034](../../adr/0034-star-lite-v0-interop-export.md).

## Quick chooser

| Goal | Prefer |
| --- | --- |
| Default interop with unknown clients | **CAR** |
| AppView / Garazyk federation backfill from a PDS | **STAR-L0**, CAR fallback |
| Hubble or other Microcosm backfill from a Garazyk PDS | **STAR-lite v0** |
| Smallest Garazyk-only archive for experiments | **STAR-lite v2** (local) |
| Firehose commit frames, sparse proofs, multi-root DRISL | **CAR only** (not STAR) |

## How clients ask

Negotiation uses the HTTP `Accept` header on `getRepo` / `getCheckout`.
Recognized media types:

| Format | Media type |
| --- | --- |
| CAR | `application/vnd.ipld.car` |
| STAR-L0 | `application/vnd.atproto.star` |
| STAR-lite (local v2) | `application/vnd.atproto.star-lite` |
| STAR-lite v0 (Microcosm) | `application/x.microcosm.star-lite` |

Quality values (`q=`) work. If the client sends no preference, Garazyk serves
**CAR**.

### Content-Encoding (zstd / gzip)

Archive media types are always identity bytes. Clients that want compression
send a separate `Accept-Encoding` header. Garazyk negotiates like Hubble:

| Client asks | Response |
| --- | --- |
| `zstd` (or tie with gzip) | `Content-Encoding: zstd` |
| `gzip` preferred by q-value | `Content-Encoding: gzip` |
| nothing / unusable | identity (no `Content-Encoding`) |

`Vary` is `Accept, Accept-Encoding`. Default compression level is **3**. Set
`PDS_HTTP_CONTENT_ENCODING=0` to force identity. Applies to `getRepo`,
`getCheckout`, and `tools.garazyk.sync.getRepoFiltered`.

```sh
curl -fsS \
  -H 'Accept: application/x.microcosm.star-lite' \
  -H 'Accept-Encoding: zstd' \
  "https://pds.example/xrpc/com.atproto.sync.getRepo?did=did:plc:…" \
  --compressed \
  -o repo.starlite
```

Note: many `curl` builds understand `--compressed` for gzip but not zstd;
decode zstd with `zstd -d` when needed.

For operators and debugging, Garazyk also accepts `?accept=…` on those
methods. A recognized value overrides `Accept`. Example:

```sh
curl -fsS \
  -H 'Accept: application/x.microcosm.star-lite' \
  "https://pds.example/xrpc/com.atproto.sync.getRepo?did=did:plc:…" \
  -o repo.starlite
```

or:

```sh
curl -fsS \
  "https://pds.example/xrpc/com.atproto.sync.getRepo?did=did:plc:…&accept=star-lite" \
  -o repo.starlite
```

Helpers that build Accept strings live in `Repository/STAR.h`
(`PDSRepoAcceptHeaderForPreferredFormat`).

## Format catalog

### CAR (`application/vnd.ipld.car`)

**What it is.** IPLD Content Addressable aRchive: a bag of CID-addressed
blocks plus one or more roots. For a normal repo export the root is the
commit CID; blocks include the commit, MST nodes, and records.

**Useful for.** Broadest ecosystem support; account migration
(`importRepo`); tooling that already speaks CAR; any payload that is not a
single canonical MST walk (firehose frames, collection proofs, multi-root
archives).

**Not ideal when.** You want streaming verification of a full repo with less
overhead than a full CAR parse, or a peer that prefers STAR.

**Garazyk.** PDS exports CAR. AppView backfill and federation clients accept
it as the fallback. Always safe as a lowest-common-denominator.

### STAR-L0 (`application/vnd.atproto.star`)

**What it is.** STAR version **1**: magic `*` + varint `1`, then a full signed
commit and a **depth-first MST** stream (nodes interleaved with records).
Readers can verify node CIDs against the commit’s `data` chain while reading.

**Useful for.** Canonical STAR export inside Garazyk; AppView repo backfill;
federation clients that prefer a verifiable streaming archive over CAR.

**Not ideal when.** Talking to Hubble / Microcosm STAR-lite v0 consumers
(different format); or when you only need flat records and do not care about
on-wire MST.

**Garazyk.** PDS can export it. AppView backfill **requests** STAR-L0 with CAR
fallback (`AppViewBackfillWorker`). Prefer this for in-tree consumers.

### STAR-lite v2 — local (`application/vnd.atproto.star-lite`)

**What it is.** STAR version **2**: magic `*` + varint `2`, full commit, then
a **flat** lexicographic `key → record` stream with **no MST node blocks**.
Smaller and simpler; rebuilding a verifiable MST is the reader’s problem.

**Useful for.** Garazyk-only experiments, storage snapshots, or tooling that
wants maximum compression and already trusts the commit another way.

**Not ideal when.** You need external interop, streaming MST verification, or
Hubble compatibility. ADR 0009 treats this as a **local** variant; there is
no known external consumer.

**Garazyk.** PDS can export it. Do not assume AppView or third parties will
request or understand it. Prefer STAR-L0 or CAR for anything that crosses a
process or organization boundary.

### STAR-lite v0 — Microcosm (`application/x.microcosm.star-lite`)

**What it is.** Upstream “STAR-lite” from
[microcosm.blue/star](https://tangled.org/microcosm.blue/star): magic `*l\0`
(`2A 6C 00`), **MST root CID in the header**, a **partial** commit with
`data` stripped, then flat `key → record` chunks. A reader re-inserts `data`
from the header CID before checking `sig`. Full-repo only — a `since` filter
cannot verify against the named root.

**Useful for.** Hubble (and similar Atmosphere mirrors) backfilling from a
Garazyk PDS without converting through CAR.

**Not ideal when.** Building Garazyk AppView backfill (we do not implement a
v0 **reader**); incremental (`since`) exports; or confusing it with local
STAR-lite v2 (same English name, different bytes and media type).

**Garazyk.** PDS **exports** v0 (ADR 0034). No in-tree v0 reader. AppView does
**not** negotiate this type today.

## Suggestions by role

### PDS operators

- Leave default negotiation alone for public clients (CAR).
- Ensure STAR-lite v0 export works if you want Hubble-style mirrors:
  `Accept: application/x.microcosm.star-lite` on `getRepo` should return that
  Content-Type and magic `*l\0`.
- Use STAR-L0 when debugging Garazyk AppView backfill against your PDS.

### AppView / Syrena

- Keep requesting **STAR-L0 + CAR**. That matches current
  `AppViewBackfillWorker` behavior.
- Do not depend on STAR-lite v0 until a reader and Accept preference exist.
- Firehose ingest remains the primary path; getRepo formats only matter for
  the backfill / repair plane.

### Relay

- Continue redirecting `getRepo` to the account’s PDS. Relays should not
  re-encode archives.

### Migration and tooling authors

- Prefer **CAR** for `importRepo` and cross-implementation moves.
- Use STAR only when both ends are known to speak the same variant.

### Indexers outside Garazyk (Hubble, Constellation, etc.)

- For **repo backfill**: negotiate **STAR-lite v0** against Garazyk PDSes.
- For **social graph / backlinks**: that is a different Microcosm surface
  (Constellation / Mikrus-style link APIs), not a STAR archive.

## Naming traps

1. **“STAR-lite” alone is ambiguous.** Say **v0** (Microcosm,
   `x.microcosm.star-lite`) or **v2 / local** (`vnd.atproto.star-lite`).
2. **L0 is not “lite”.** L0 means layer-0 / MST-structured STAR version 1.
3. **Firehose “blocks” are not getRepo STAR.** Commit events still use CAR
   (or STAR conversion on ingest); that path is separate from export
   negotiation.

## Implementation map

| Concern | Location |
| --- | --- |
| Writers / readers / Accept helpers | `Garazyk/Sources/Repository/STAR.{h,m}` |
| CAR | `Garazyk/Sources/Repository/CAR.{h,m}` |
| PDS `getRepo` / `getCheckout` negotiation | `Garazyk/Sources/Network/XrpcSyncPack.m` |
| PDS export producers | `Garazyk/Sources/Services/PDS/PDSRepositoryService+Export.m` |
| AppView backfill Accept preference | `Garazyk/Sources/AppView/Server/Backfill/AppViewBackfillWorker.m` |
| Hubble smoke topology | `scripts/scenarios/topologies/hubble-star-lite.json` |
| STAR-lite vs CAR benchmark | `scripts/test/star_lite_export_benchmark.ts` |

## Benchmarking STAR-lite vs CAR

The full experiment design (topology, seeding, metrics, expectations, and the
`listRecords` pagination gap) is in
[STAR-lite v0 vs CAR export benchmark](star-lite-vs-car-export-benchmark.md).

`scripts/test/star_lite_export_benchmark.ts` (wrapper:
`scripts/test/star_lite_export_benchmark.sh`) starts PLC plus one or more PDS
binaries, seeds repos to a configurable total payload size, then exports each
account with `com.atproto.sync.getRepo` negotiated as CAR and STAR-lite v0.
For each export it records size, generation+transfer latency, peak RSS, average
CPU (`ps`), and on-disk data-dir delta (`du`). Correctness is checked by
comparing sorted post texts parsed from both archives. (`listRecords` cursor
pagination landed in workstream 01 S21 and can be used as optional independent
ground truth in a follow-up.)

Environment knobs:

| Variable | Default | Purpose |
| --- | --- | --- |
| `STAR_LITE_BENCH_TARGET_BYTES` | `10000000` (~10 MB) | Approx total repo payload across all accounts |
| `STAR_LITE_BENCH_PDS_COUNT` | `3` | PDS instances (`pds`, `pds2`, `pds3`) |
| `STAR_LITE_BENCH_ACCOUNTS_PER_PDS` | `5` | Accounts seeded per PDS |
| `STAR_LITE_BENCH_QUICK` | off | When `1`, ~500 KB / 1 PDS / 2 accounts dev smoke |
| `STAR_LITE_BENCH_JSON_OUT` | — | Optional path for machine-readable summary JSON |

Example:

```sh
STAR_LITE_BENCH_QUICK=1 ./scripts/test/star_lite_export_benchmark.sh
STAR_LITE_BENCH_TARGET_BYTES=100000000 ./scripts/test/star_lite_export_benchmark.sh
```

## See also

- [ADR 0009 — STAR versioning and variants](../../adr/0009-star-versioning-and-variants.md)
- [ADR 0034 — STAR-lite v0 interoperable export](../../adr/0034-star-lite-v0-interop-export.md)
- Upstream STAR-lite notes: https://tangled.org/microcosm.blue/star
