---
title: Standard.site AppView — kickstart prompt (slices S1-S2)
status: pending
agent: worker
derives_from: docs/standard-site-appview.md
---

# Kickstart: longform lexicon indexing

This is an execution prompt in the style of `docs/plans/prompts/`, but it is
**not** in the phase loop and has no phase number. `docs/plans/prompts/`
holds prompts derived from mega-plan workstreams; this one derives from
`docs/standard-site-appview.md`, which is a product design doc, not a
workstream. If this work is adopted into the mega plan, promote the design
doc to a workstream first and renumber this as phase 29.

Scope is slices **S1 and S2 only**. Stop at the boundary marked below.

---

## Mission

Make the Garazyk AppView index long-form blog records from the
`site.standard.*` lexicon family, and give it a collection allowlist so a
longform-only deployment does not materialize every indexed author's entire
Bluesky history.

S1 is configuration, not code: the AppView already claims any collection
whose NSID has a loaded lexicon with a record `main` def. S2 is the smallest
code change that makes a scoped deployment practical.

Do not build ingest, discovery, normalization, or a read API. Those are
S3-S7 and they depend on decisions this slice does not make.

## Read first

- `docs/standard-site-appview.md` — authoritative. If this prompt and the
  design doc disagree, the design doc wins and this prompt gets fixed.
  Sections §1.1 (the empty-refs open union), §2 (what already works), and
  §2.1 (gaps) are the ones that matter here.
- `Garazyk/Sources/AppView/Server/AppViewRuntime.m:159-173` — lexicon load.
- `Garazyk/Sources/AppView/Server/AppViewRuntime.m:217-246` — the hardcoded
  `domainCollections` set and generic indexer construction.
- `Garazyk/Sources/AppView/Server/AppViewRuntime.m:400-420` — the op-dispatch
  loop, the second enforcement point for S2.
- `Garazyk/Sources/AppView/Server/Indexers/AppViewGenericIndexer.m:55-66` —
  `handlesCollection:`, the first enforcement point.
- `Garazyk/Sources/Lexicon/ATProtoLexiconValidator.m:920-1000` —
  `validateUnion:`. Read this before touching anything; understanding why it
  already handles the empty-refs case is the difference between S1 being a
  no-op and S1 being a rewrite.
- `Garazyk/Resources/lexicons/statusphere/` — the existing precedent for
  vendoring a third-party lexicon family.

## Decisions already taken (do not re-litigate)

- **Vendor the lexicon JSON into the repo.** Do not fetch schemas at
  runtime from `com.atproto.lexicon.schema`, and do not add a network
  dependency to AppView startup.
- **Do not publish anything under `site.standard.*`, `pub.leaflet.*`,
  `blog.pckt.*`, or `app.offprint.*`.** Those namespaces belong to their
  publishers. This slice only consumes.
- **The allowlist defaults to empty, meaning current behaviour.** No
  existing deployment changes unless an operator opts in.
- **Prefix matching, not exact NSID matching.** `site.standard.` must cover
  the whole family. A trailing dot means prefix; no trailing dot means exact.

## Slice 1 — vendor the lexicons

Write a re-runnable fetch script (`scripts/fetch_longform_lexicons.ts`,
Deno, matching the repo's existing script conventions) that pulls
`com.atproto.lexicon.schema` records from four publishers and writes them
to NSID-shaped paths under `Garazyk/Resources/lexicons/`.

| Family | DID | PDS |
| --- | --- | --- |
| `site.standard.*` | `did:plc:re3ebnp5v7ffagz6rb6xfei4` | `https://auriporia.us-west.host.bsky.network` |
| `pub.leaflet.*` | `did:plc:btxrwcaeyodrap5mnjw2fvmz` | `https://chanterelle.us-west.host.bsky.network` |
| `blog.pckt.*` | `did:plc:revjuqmkvrw6fnkxppqtszpv` | `https://pds.pckt.cafe` |
| `app.offprint.*` | `did:plc:pgjkomf37an4czloay5zeth6` | `https://losers.club` |

Resolve each PDS from `https://plc.directory/{did}` rather than hardcoding
the endpoints above — they are recorded here so you can verify the script
resolves what is expected, not so you can skip resolution.

For each record: take `.value`, strip the `$type` and `revision` wrapper
fields that belong to the schema record rather than the schema, and write to
the path implied by the NSID (`site.standard.document` →
`site/standard/document.json`). Roughly 110 files total. Skip the
`*.auth*` permission-set records — they are OAuth scope definitions, not
schemas the indexer needs, and the registry may or may not accept a
`permission-set` def type. If it accepts them cleanly, keeping them is fine;
do not spend time making it work if it does not.

Re-running the script against an unchanged network must produce no diff.
That property is the point: it is how upstream lexicon drift gets noticed.

**Do not write any Objective-C in this slice.** If indexing does not work
after dropping the files in, that is a finding to report, not a signal to
start patching the indexer. Report it and stop.

## Slice 2 — collection scoping

Add to `AppViewConfiguration`:

```
appview.index.collections[]    APPVIEW_INDEX_COLLECTIONS (comma-separated)
```

Empty (the default) preserves today's behaviour exactly. Non-empty makes it
an allowlist. Update the key/env-var table in the `AppViewConfiguration.h`
header comment — that table is documentation the file promises to keep
current.

Enforce in both places:

1. `AppViewGenericIndexer.handlesCollection:` — the correctness boundary.
2. The op-dispatch loop in `AppViewRuntime.m:400-420` — the cost boundary.
   Skipping here is what makes backfilling a prolific Bluesky poster cheap
   when you only want their blog.

Put the matcher somewhere both can reach it, with its own unit tests. It is
about fifteen lines and it is the only thing in this slice that can be wrong
in a subtle way: exercise exact match, prefix match, non-match, empty
allowlist, empty NSID, and an NSID that is a strict prefix of an allowlist
entry without being a match (`site.standardX` must not match
`site.standard.`).

## Verification

Do not rely on the firehose. Backfill known DIDs directly through the
existing admin surface (`POST /admin/backfill/repos`), which needs no relay
connection and gives a deterministic corpus.

Acceptance:

1. `GET /admin/lexicons/collections` lists all four families.
2. With no allowlist set, backfilling `did:plc:btxrwcaeyodrap5mnjw2fvmz`
   (leaflet.pub, 29 collections) stores rows across many collections.
3. With `APPVIEW_INDEX_COLLECTIONS=site.standard.`, the same backfill on a
   clean database stores rows for **only** the four `site.standard.*`
   collections.
4. A Leaflet-authored `site.standard.document` — whose `content` is a
   `pub.leaflet.content` object, i.e. an unknown `$type` in an open union
   with zero refs — round-trips through the generic indexer with **no
   dead-letter row**. This is the single most important assertion in the
   slice. If it fails, the problem is in `validateUnion:` and you should
   read §1.1 of the design doc again before changing anything.
5. A content-less SSG document (try `did:plc:3danwc67lo7obz2fmdg6jxcr`,
   steveklabnik.com) also indexes cleanly. Most real documents have no
   `content` at all; that path must not be an afterthought.

Global gates, per repo convention:

```bash
cmake --build build --target AllTests --parallel 4 && ./build/tests/AllTests --gated=run
```

Bound the build to `-j4`. An unbounded `--parallel` has crashed this machine.
Check free disk before a full gated run — these flake with `SQLITE_FULL`
under disk pressure, and a flake will cost more time than the check.

If you add a new XCTest suite, it needs a cmake reconfigure **and** manual
registration in `test_main.m`. Without both, it silently runs zero tests and
reports success.

## Stop here

Do not start S3 (Jetstream ingest). It introduces a new network client and a
cursor-semantics change that wants an ADR — Jetstream cursors are microsecond
timestamps and reusing the relay checkpoint column for them is a decision,
not a detail.

Report back with:

- The lexicon file count actually vendored, and any schema the registry
  rejected (with the rejection reason).
- The before/after row counts per collection from acceptance items 2-3.
- Whether items 4 and 5 passed unmodified, or what had to change.
- Anything in the design doc's §2.1 gap list that turned out to be wrong.

## Note on a concurrent fix

A separate session may be fixing an rkey mismatch in
`AppViewGenericIndexer.m:115-142` (the URI is built from `effectiveRkey` but
the raw `rkey` parameter is stored). It touches the same file as S2. Check
whether it has landed before you start, and rebase rather than resolving a
conflict by hand — the two changes are independent and should not be
entangled.
