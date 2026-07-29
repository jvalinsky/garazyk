---
title: Standard.site longform AppView and macOS reader
status: proposal
last_verified: 2026-07-28
---

# Standard.site longform AppView and macOS reader

A plan for (a) a Garazyk AppView deployment that backfills and serves
long-form blog content from the `site.standard.*` lexicon family, and
(b) a local macOS application for discovering and reading it.

All lexicon facts below were read from the canonical
`com.atproto.lexicon.schema` records on each project's PDS on 2026-07-28,
not from prose documentation. Raw copies are in the session scratchpad
under `lex/`.

---

## 1. The lexicon landscape

### 1.1 `site.standard.*` is a metadata spine, not a content format

Published by `did:plc:re3ebnp5v7ffagz6rb6xfei4` (`standard.site`), PDS
`auriporia.us-west.host.bsky.network`. Eight schema records:

| NSID | Type | Role |
| --- | --- | --- |
| `site.standard.document` | record, `tid` | One article/post |
| `site.standard.publication` | record, `tid` | Blog/site container |
| `site.standard.graph.subscription` | record, `tid` | Reader → publication follow |
| `site.standard.graph.recommend` | record, `tid` | Reader → document endorsement |
| `site.standard.theme.basic` | record, `tid` | 4-colour theme |
| `site.standard.theme.color` | defs | `#rgb` colour def |
| `site.standard.authFull` | permission-set | OAuth scope: all four record types |
| `site.standard.authSocial` | permission-set | OAuth scope: subscription + recommend only |

`site.standard.document` requires only `site`, `title`, `publishedAt`.
Everything else is optional: `path`, `description`, `coverImage` (blob,
≤1 MB), `textContent`, `tags[]`, `bskyPostRef` (strongRef),
`contributors[]`, `updatedAt`, `labels`, `links`, and `content`.

**The critical property is `content`:**

```json
"content": { "refs": [], "type": "union", "closed": false }
```

An open union with **zero refs**. Standard.site deliberately declines to
define a content format — it defines the metadata envelope and lets other
lexicons fill the body. `links` is the same shape. This is the single most
important design fact in the whole family, and it drives most of the plan
below.

Consequences:

- A consumer cannot render a document from `site.standard.document` alone.
  It must understand at least one *foreign* content vocabulary.
- Any validator that treats an empty-refs union as "matches nothing" will
  reject every rich document in the network. Garazyk gets this right —
  `ATProtoLexiconValidator.m:987-999` fails only when `closed` is set and
  otherwise returns `YES` for unknown `$type`s.
- `content` is a **single object**, not an array, despite the description
  saying "each entry". Confirmed against live records; the object's
  `$type` is the vendor content wrapper.

`site.standard.publication` requires `url` and `name`; optional `icon`
(blob), `description`, `basicTheme` (a `ref` to the *record* NSID
`site.standard.theme.basic`, not a `#fragment` — unusual and worth a
validator test), and `preferences.showInDiscover` (default `true`).

`site.standard.graph.recommend` requires `document` (at-uri) and
`createdAt`. `graph.subscription` requires `publication` (at-uri), with
optional `createdAt`.

### 1.2 The three content vocabularies

Each publishing platform ships its own block vocabulary and its own
`*.content` wrapper that plugs into `site.standard.document#content`.

**Leaflet** (`leaflet.pub`, `did:plc:btxrwcaeyodrap5mnjw2fvmz`) — 38
published schemas. `pub.leaflet.content` requires `pages[]`, a union of
`pub.leaflet.pages.linearDocument` | `pub.leaflet.pages.canvas`. A
linearDocument holds `blocks[]` of `pub.leaflet.pages.linearDocument#block`
wrappers, each containing one of ~20 block types:

```
text  header  blockquote  image  imageGallery  code  math  html
iframe  website  bskyPost  poll  button  page  signup  postsList
horizontalRule  orderedList  unorderedList  membersOnlyDelimiter
standardSitePost  standardSitePublication
```

Rich text uses `pub.leaflet.richtext.facet` with byte-offset ranges and
features `bold`, `italic`, `strikethrough`, `underline`, `code`,
`highlight`, `link`, `atMention`, `didMention` — the same *shape* as
`app.bsky.richtext.facet` but different `$type`s, so `@atproto/api`'s
`RichText` cannot segment them and neither can a naive Bluesky facet
reuse on our side.

**pckt** (`pckt.blog`, `did:plc:revjuqmkvrw6fnkxppqtszpv`) — 36 schemas.
`blog.pckt.content` is a hybrid: `items[]` (open union, empty refs) for
≤20 KB, or `blob` + `references[]` above that. Blocks are ProseMirror-ish:
`text heading blockquote bulletList orderedList listItem taskList taskItem
table tableRow tableHeader tableCell codeBlock image gallery iframe website
blueskyEmbed noteEmbed mention hardBreak horizontalRule`. Note
`blog.pckt.document` requires only `document` and `site` — it is a
*pointer* record, and pckt also has `blog.pckt.domain.*` procedures for
custom-domain verification.

**Offprint** (`offprint.app`, `did:plc:pgjkomf37an4czloay5zeth6`) — 28
schemas. `app.offprint.content` requires `items[]`, and unlike the other
two it is a **closed union** naming 18 concrete block types:

```
text heading blockquote callout bulletList orderedList taskList codeBlock
horizontalRule image imageGrid imageCarousel imageDiff webBookmark
webEmbed button mathBlock blueskyPost
```

Offprint has gone furthest on adoption: `app.offprint.document.article`
requires exactly one field — a `strongRef` to "a `site.standard.document`
compatible record". The article record is a pure sidecar; the content lives
in the standard.site record.

### 1.3 The dual-write pattern is the norm

`describeRepo` on all three accounts shows both the native collection *and*
the `site.standard.*` mirror:

| Account | Native | Mirror |
| --- | --- | --- |
| leaflet.pub | `pub.leaflet.{document,publication,publicationPage,comment,graph.subscription,poll.definition}` | `site.standard.{document,publication,graph.recommend,graph.subscription}` |
| pckt.blog | `blog.pckt.{document,publication,gallery}` | `site.standard.{document,publication,graph.recommend,graph.subscription}` |
| offprint.app | `app.offprint.{document.article,publication,actor.profile}` | `site.standard.{document,publication,graph.subscription}` |

So **indexing `site.standard.document` alone reaches all three platforms**,
plus the static-site-generator crowd (Astro/Eleventy/Hugo/Zola plugins,
`marmite`, `emdash`, Bridgy Fed, granary, WordPress via `wireservice`).
The native collections are worth indexing only for platform-specific extras
(Leaflet comments and polls, pckt galleries, Offprint pages/components).

### 1.4 Content storage: the blob-spill trap

Two of the three spill large documents into an opaque JSON blob:

- Leaflet: `pub.leaflet.content.blobPages` (`application/json`, ≤5 MB).
  When set, "consumers **MUST** ignore `pages`". A `blobs[]` array mirrors
  every nested image blob at top level, because the PDS only scans the
  record's top level when deciding GC reachability.
- pckt: `blog.pckt.content.blob` above 20 KB, with `references[]` serving
  the same GC-anchoring role.

Colibri's `@colibri-social/standard-renderer` — currently the most complete
open renderer — explicitly does *not* implement `blobPages` decoding. Any
reader that does gets the long-tail of big posts for free, and it is a
straightforward `com.atproto.sync.getBlob` + JSON parse.

### 1.5 What real records actually look like

Sampled live from three publishers:

| Publisher | Keys present | `content`? |
| --- | --- | --- |
| standard.site | `canonicalUrl coverImage description path publishedAt site title` | absent |
| isabelroses.com | `canonicalUrl coverImage description path publishedAt site tags textContent title` | absent |
| steveklabnik.com | `description path publishedAt site tags textContent title` | absent |
| leaflet.pub | `bskyPostRef content coverImage description path publishedAt site tags title` | `pub.leaflet.content` |

Two findings the docs do not mention:

1. **Most documents in the wild carry no `content` at all.** SSG-published
   blogs emit metadata + `textContent` and rely on `site` + `path` for the
   canonical URL. A reader needs three tiers: rich `content` → plaintext
   `textContent` → fetch the canonical URL.
2. **`canonicalUrl` appears in real records but is not in the lexicon.**
   Undeclared extra fields — harmless under optimistic validation, but a
   strict validator would flag them, and it is a useful field to keep.

### 1.6 Verification

Publication ownership is proved bidirectionally:

- `GET https://{publication.url}/.well-known/site.standard.publication`
  returns the publication's AT-URI. Consumers compare it to the record's
  own AT-URI; match ⇒ verified.
- `<link rel="site.standard.publication">` and
  `<link rel="site.standard.document">` head tags exist but the spec says
  they are **hints only** — never trust them for verification.

This is cheap and worth doing at index time: a `verified` boolean on the
publication row, re-checked on a slow cadence, is the difference between a
trustworthy reader and a spoofable one.

### 1.7 Volume

A 25-second Jetstream sample across `site.standard.document`,
`site.standard.publication`, `pub.leaflet.document`, `blog.pckt.document`,
`app.offprint.document.article`, and `com.whtwnd.blog.entry` produced
**3 events** (2 documents, 1 publication).

Extrapolated: roughly 5–10k longform events per day network-wide. This is
three to four orders of magnitude below `app.bsky.feed.post`. A complete,
un-scoped, whole-network longform AppView is entirely tractable on a single
machine — the storage and CPU budget is dominated by the blob-spill fetches,
not by the record stream.

---

## 2. What Garazyk's AppView already provides

Answering the question directly: **yes, but the lever is lexicon files, not
a backfill setting — and backfill itself is DID-scoped, not
collection-scoped.**

Concretely:

- `AppViewRuntime.m:159-173` loads every lexicon JSON found under the
  search paths from `ATProtoLexiconRegistry.searchPathsForDirectory:`
  (`$PDS_LEXICON_PATH`, the app bundle, `/usr/share/garazyk/lexicons`,
  `Garazyk/Resources/lexicons`, and `$APPVIEW_DATA_DIR/lexicons`).
- `AppViewGenericIndexer.m:58-66` claims **any** collection whose NSID has
  a loaded schema with a `main` def of type `record`, minus the hardcoded
  `app.bsky.*` / `chat.bsky.*` set at `AppViewRuntime.m:219-238`.
- `AppViewLexiconEndpointGenerator` then auto-registers `GET/POST
  /xrpc/{nsid}` for every query/procedure def in the registry, with
  `AppViewCustomQueryRegistry` providing per-NSID overrides.
- Indexed records land in the shared `records` table
  (`uri, did, collection, rkey, cid, handle, value, subject_did,
  created_at, indexed_at`), with `value` holding the full record JSON.
- Admin surface already exists: `/admin/backfill/{status,queue,repos}`,
  `/admin/backfill/repos/:did/{retry,cancel}`,
  `/admin/backfill/scope/rebuild`, `/admin/lexicons`,
  `/admin/lexicons/collections`, `/admin/records`.
- The precedent for third-party lexicons is established —
  `Garazyk/Resources/lexicons/` already carries `statusphere`,
  `skylights`, `linkat`, `social.grain`, `place.stream`, and
  `com.germnetwork`.

So dropping the ~110 schema records from the four families into
`Garazyk/Resources/lexicons/` gets indexing and generic query endpoints
with no code change. That is the good news.

### 2.1 Gaps

1. **No collection scoping anywhere.** `AppViewBackfillOrchestrator` runs
   `com.atproto.sync.getRepo` per DID and dispatches every op through every
   indexer. With ~110 longform schemas loaded there is no way to say "index
   only these" — and conversely, backfilling a DID for its blog also
   materializes its entire Bluesky history. For a longform-only deployment
   this is mostly wasted I/O and disk.
2. **No discovery.** Nothing enumerates *which* DIDs publish
   `site.standard.document`. `AppViewRelevanceSet` expands from seed DIDs
   via the follow graph — the wrong graph for this problem. The right graph
   is publication ↔ subscription ↔ recommend.
3. **No Jetstream client.** Only full `subscribeRepos`. Given the traffic
   numbers in §1.7, a collection-filtered Jetstream connection is the
   natural ingest for this AppView — a few events per minute instead of the
   full network firehose.
4. **No blob fetching in the index path.** `blobPages` / `blob` spill
   requires `com.atproto.sync.getBlob` against the author's PDS at index
   time (or lazily at read time).
5. **No cross-vocabulary normalization.** Three block dialects and three
   facet dialects need one internal representation, or every client
   reimplements all three.
6. **Latent bug.** `AppViewGenericIndexer.m:115-142` computes
   `effectiveRkey` (falling back through `record[@"rkey"]` and a generated
   UUID) and uses it to build the URI, but then passes the raw `rkey`
   parameter to `saveRecordWithURI:...rkey:`. When `rkey` is nil the URI
   and the stored `rkey` column disagree, and the column is `NOT NULL`.
   Worth a fix and a regression test independent of this plan.

---

## 3. Plan — server side

Pilot-sized slices, each independently landable and testable.

### S1 — Vendor the lexicons (no code)

Add under `Garazyk/Resources/lexicons/`:

```
site/standard/{document,publication,theme.basic,theme.color,
               graph.subscription,graph.recommend}.json
pub/leaflet/…      (content, document, publication, publicationPage,
                    pages.linearDocument, pages.canvas, richtext.facet,
                    blocks.* ×20, comment, poll.*)
blog/pckt/…        (content, document, publication, richtext.facet,
                    block.* ×17, gallery, theme)
app/offprint/…     (content, document.article, publication, page,
                    component, richtext.facet, block.* ×18, theme)
```

Fetch script: `com.atproto.repo.listRecords` on each publisher's
`com.atproto.lexicon.schema` collection, unwrap `.value`, strip `$type`
and `revision`, write to the NSID path. Make it re-runnable so upstream
lexicon revisions can be diffed — Leaflet's records already carry
`"revision": 1`.

**Exit:** `/admin/lexicons/collections` lists all four families;
`AppViewGenericIndexer` claims `site.standard.document`; a hand-fed
Leaflet record round-trips through the validator without a dead-letter
entry (this is the empty-refs open-union check from §1.1).

### S2 — Collection scoping

Add `appview.index.collections[]` / `APPVIEW_INDEX_COLLECTIONS` to
`AppViewConfiguration`. Empty ⇒ current behaviour (index everything with a
loaded schema). Non-empty ⇒ an allowlist, matched with prefix support so
`site.standard.` and `pub.leaflet.` cover their families.

Enforce in two places:

- `AppViewGenericIndexer.handlesCollection:` — cheap, and the only place a
  longform-only deployment strictly needs.
- The op-dispatch loop in `AppViewRuntime.m:400-420` — skips work before it
  reaches any indexer, and is what makes a whole-repo backfill of a prolific
  Bluesky poster cheap.

**Exit:** with the allowlist set to `site.standard.`, backfilling
`did:plc:btxrwcaeyodrap5mnjw2fvmz` (leaflet.pub — 29 collections) stores
only the four `site.standard.*` collections. Unit test on the matcher,
integration test on the backfill.

### S3 — Jetstream ingest

New `JetstreamClient` alongside `RelayClient`, subscribing to
`wss://jetstream2.us-east.bsky.network/subscribe` with repeated
`wantedCollections` params. Jetstream emits decoded JSON, so this bypasses
CAR/CBOR decoding entirely for the live path.

Config: `appview.ingest.mode = relay | jetstream`, plus
`appview.ingest.jetstream_urls[]`. Cursor handling reuses the existing
checkpoint mechanism (Jetstream cursors are microsecond timestamps, so the
persisted-cursor column needs no schema change but does need a distinct
interpretation — worth an ADR note).

Rationale: §1.7. At ~5–10k events/day the full firehose is ~99.99% waste.

**Exit:** a live 60-second run indexes every `site.standard.document`
commit observed, with the cursor surviving a restart.

### S4 — Discovery and seeding

Three complementary sources, in order of value:

1. **Backlink expansion.** Every indexed `site.standard.document.site`
   pointing at an `at://` URI names a publication DID. Every
   `graph.subscription.publication` and `graph.recommend.document` names
   another. Feed these into `AppViewRelevanceSet` under a new
   `AppViewRelevanceReasonLongformGraph` and enqueue backfill. This is the
   correct interest graph for longform, replacing the follow-graph
   expansion.
2. **Bootstrap list.** GitHub code search for
   `.well-known/site.standard.publication` returns hundreds of static-site
   publishers with the AT-URI in plaintext. One-time seed file, checked in.
3. **Sidecar crawl.** `app.offprint.document.article` and
   `blog.pckt.document` are strongRef pointers; resolving them surfaces
   documents whose authors we have not yet seen.

**Exit:** starting from the three platform DIDs as seeds, a 1-hour run
discovers ≥100 distinct publication DIDs.

### S5 — Normalized document model

A `documents` projection table populated by a new
`AppViewStandardSiteIndexer` (a domain indexer, claiming
`site.standard.*`, so it takes priority over the generic one):

```
uri, did, rkey, cid, publication_uri, publication_did, canonical_url,
title, description, text_content, cover_blob_cid, published_at,
updated_at, tags_json, bsky_post_uri, content_type, content_json,
content_blob_cid, blob_resolved, indexed_at
```

Plus `publications` (uri, did, url, name, description, icon_cid, theme,
show_in_discover, verified, verified_at) and edge tables for
subscription/recommend.

`content_type` records which vocabulary the body uses so a client can
decide whether it can render it. Keep `content_json` opaque at this layer —
normalization belongs in S6.

**Exit:** `documents` populated for all three vocabularies plus
content-less SSG records; `.well-known` verification populates
`publications.verified`.

### S6 — Block normalization + blob spill

An `LongformBlockNormalizer` mapping all three vocabularies onto one
internal block model. The vocabularies overlap heavily — text, heading,
blockquote, code, image, list, horizontalRule, math, iframe/embed,
bskyPost, button, callout, table exist in at least two of the three — so a
common core with a `raw` escape hatch for vendor-specific blocks
(`membersOnlyDelimiter`, `imageDiff`, `signup`, `postsList`, `taskList`)
covers essentially everything.

Same for facets: one `{ byteStart, byteEnd, marks[], href?, did? }` run
model, with a shared UTF-8 byte-offset segmenter. All three use byte
offsets in the Bluesky style, so one segmenter serves all.

Blob spill: on index, if `blobPages` or `blob` is set, fetch via
`com.atproto.sync.getBlob` from the author's PDS, parse, and normalize.
Bound it — size cap, timeout, retry with backoff, and a `blob_resolved`
flag so the reader can show a degraded view rather than block.

**Exit:** golden-file tests rendering one real document per vocabulary,
including at least one `blobPages` document, to a stable normalized JSON.

### S7 — Read API

Custom handlers registered through `AppViewCustomQueryRegistry` under a
Garazyk NSID namespace (do **not** squat on `site.standard.*` — that
namespace belongs to its publisher; define our own query lexicons and
publish them if we want them consumable):

```
getDocument          uri | (publication, path)  → normalized doc
getPublication       uri | url | did
listPublicationDocs  publication, cursor, limit
getDiscoverFeed      cursor, limit  (showInDiscover=true, verified, recency)
listSubscriptions    did
getRecommendations   document | did
searchDocuments      q, tag, publication   (SearchIndexService via
                                            AppViewSearchIndexHook)
```

**Exit:** all endpoints answer from the local database with no upstream
calls; a scenario test drives the full path from Jetstream event to
`getDocument`.

---

## 4. Plan — macOS reader

### 4.1 On "macOS UIKit"

UIKit on macOS means **Mac Catalyst**. Three viable framings, and the
choice matters more than usual here because the repo is 100% Objective-C
CLI targets (`project.yml` — every target is `type: tool, platform: macOS`)
with one dormant AppKit `AppDelegate` at `Garazyk/Sources/App/AppDelegate.h`.

| Option | Fit | Cost |
| --- | --- | --- |
| **AppKit + ObjC** | Matches the codebase exactly. Direct linkage to AppView code. Real Mac behaviours (multi-window, sidebar, services) for free. | Most view code to write; no iOS path. |
| **Mac Catalyst + ObjC UIKit** | What was asked for. Opens an iPad/iPhone port later. UIKit-in-ObjC is stable and well-trodden. | Catalyst reading apps feel subtly non-native — scroll behaviour, text selection, menu integration all need work. Cannot link GNUstep-portable code paths that assume no UIKit. |
| **SwiftUI shell over an ObjC core** | Least view code; best text rendering story via `AttributedString`. | Introduces Swift to a pure-ObjC repo; needs a bridging surface and an ADR. |

**Recommendation: AppKit + Objective-C**, with the entire non-UI layer
factored into a `LongformKit` framework that has no UI dependency. If
Catalyst or iOS is wanted later, only the view layer is rewritten. If the
iPad path is a firm near-term requirement rather than a maybe, take
Catalyst — but decide before S8, not after, because it constrains how the
core links.

Either way, **this belongs in an ADR** — it is the first GUI target in the
repo and the first framework decision with a portability cost.

### 4.2 Local-first architecture

The reader should not require the AppView to be running. Two modes over
one storage layer:

- **Direct mode.** The app talks to PDSes and the PLC directory itself:
  resolve handle → DID → PDS, `listRecords` on `site.standard.document`,
  `getBlob` for images and spilled content. Works on day one, before any
  server slice lands, and is how a user follows a single blog they already
  know about.
- **AppView mode.** Points at a Garazyk AppView for discovery, search, and
  the recommend/subscription graph — the things a single client cannot
  compute.

Local store: SQLite with FTS5, mirroring the S5 schema. Offline reading is
the whole point of a native reader, so cache document bodies and images
eagerly on subscribe.

### 4.3 Feature shape

- **Library** — subscribed publications, unread counts, tag filters.
  Backed by `site.standard.graph.subscription` records in the user's own
  repo, so subscriptions are portable and survive the app.
- **Discover** — the S7 discover feed: verified publications with
  `showInDiscover`, recent documents, recommendations from people the user
  follows on Bluesky (the `graph.recommend` graph joined against
  `app.bsky.graph.follow`).
- **Reader** — the core. Renders the normalized block model. This is where
  a native app beats every web reader: real typography, `NSTextView` with
  proper hyphenation and ligatures, adjustable measure, reading position
  sync, full-text search across everything cached.
- **Publication theming** — `site.standard.theme.basic` gives four colours.
  Honour them in a "publisher style" mode, with a "reader style" override.
- **Verification badge** — surface the §1.6 `.well-known` result honestly.
  Unverified is not the same as fake, but the user should be able to tell.

### 4.4 Write path

Optional and later, but the lexicons support it: `graph.subscription` and
`graph.recommend` are exactly the `site.standard.authSocial` OAuth scope.
An app that only subscribes and recommends can request the narrow scope,
which is a genuinely good privacy story — worth designing for even if the
publishing path (`authFull`) is never built.

### 4.5 Slices

- **S8** — `LongformKit`: DID/PDS resolution, record fetch, the S6
  normalizer (shared code with the server), SQLite cache. No UI. Unit-
  testable in the existing XCTest setup, which keeps it inside the current
  build and test story.
- **S9** — Reader window: open an `at://` URI or a blog URL, render it.
  Ship this as a standalone "atproto blog reader" before any library or
  discovery UI exists. It is the smallest thing that is genuinely useful.
- **S10** — Library + subscriptions, local-only (no OAuth), backed by a
  local list.
- **S11** — OAuth (`authSocial`), subscription records written to the
  user's repo, sync across devices for free.
- **S12** — Discover, search, recommendations against the AppView.

Note S8's normalizer is shared with S6. Writing it once, in ObjC, with no
UI dependency, and linking it into both the AppView and the app is the
main reason this pairing is worth doing in this repo rather than as a
separate TypeScript project.

---

## 5. Risks and open questions

- **Lexicon drift.** Leaflet's records carry `revision: 1`; standard.site's
  do not. There is no versioning discipline to rely on. The S1 fetch script
  must be re-runnable and diffable, and a CI job that flags upstream
  changes would pay for itself.
- **Namespace discipline.** Do not publish records or queries under
  `site.standard.*`, `pub.leaflet.*`, `blog.pckt.*`, or `app.offprint.*`.
  Consume them; publish our own.
- **The `content` union will grow.** New platforms will add new
  vocabularies. The normalizer must degrade to `textContent`, then to the
  canonical URL, rather than fail. Design for the unknown-`$type` case
  from the start — it is the common case, not the edge case.
- **Blob spill is unbounded-ish.** 5 MB per Leaflet document, and a
  publication can have hundreds. Cap, rate-limit per host, and make
  resolution lazy if the numbers get uncomfortable.
- **Moderation.** `labels` (self-labels) is the only signal in-lexicon.
  Whether to apply Ozone labels from a labeler to longform content is an
  open question, and the answer probably differs between the AppView and a
  purely local reader.
- **Disk.** Per the existing note on disk pressure, a whole-network
  longform index plus cached blobs is small by AppView standards but not
  free. Budget it before enabling blob resolution by default.

## 6. Prior art worth reading

- `colibri-social/colibri.social` — `packages/standard-renderer`, the most
  complete open renderer; core is framework-agnostic TypeScript. Explicitly
  does not decode `blobPages`.
- `haileyok/blug` — compact TypeScript types for the Leaflet block model.
- `snarfed/bridgy-fed` — maps `site.standard.document` ↔ `app.bsky.feed.post`.
- `bluesky-social/social-app` — `src/components/Post/Embed/StandardSiteEmbed`,
  first-party rendering of standard.site embeds.
- `FiloSottile/mostly-harmless` — `atsites/main.go`, a Go consumer.
- Aggregators to compare against: `docs.surf`, `read.pckt.blog`,
  `standard-search.octet-stream.net`, `potatonet.app`,
  `site-validator.fly.dev`.
