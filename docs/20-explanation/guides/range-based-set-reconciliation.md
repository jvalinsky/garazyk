---
title: Range-based set reconciliation and the Willow protocol
---

# Range-based set reconciliation and the Willow protocol

Companion to [IBLT for atproto reconciliation](iblt-for-atproto-reconciliation.md).
That guide covers the probabilistic, order-free approach to set reconciliation.
This one covers the ordered, recursive alternative — **range-based set
reconciliation (RBSR)** — the protocol suite that made it well known
([Willow](https://willowprotocol.org/)), and which of Willow's ideas transfer to
Garazyk and which do not.

The short version: for most Garazyk problems the interesting parts of Willow are
*not* its reconciliation algorithm. They are its separation of metadata sync from
payload transfer, and its treatment of partial payloads as first-class.

## The question that picks the algorithm

Before comparing anything, answer one question: **do both sides already know
what the set is supposed to contain?**

| Situation | Right tool |
| --- | --- |
| Universe known and enumerated, bounded size, ordered | Possession **bitmap** over the known index |
| Universe unknown, keyspace ordered, diff size unknown | **RBSR** (Willow's approach) |
| Universe unknown, no useful ordering, one round trip matters | **IBLT** / rIBLT |
| A single hash already commits to the whole set | Compare the hash — no reconciliation at all |

Set reconciliation protocols exist to *discover set contents that neither side
knows*. Content-addressing frequently destroys that premise by publishing the
contents up front, which is why the last two rows matter more in this codebase
than the middle two.

## What Willow actually is

Willow is not one algorithm. It is five separable pieces, and they can be
adopted independently.

### 1. The data model

A Willow entry lives at `(namespace, subspace, path)` and carries a `timestamp`,
a `payload_digest`, and a `payload_length`. Queries and sync units are expressed
as **3D products of ranges** — a range over subspaces, a range over paths, and a
range over time — so "everything this author wrote under `/photos/` in the last
week" is a first-class, reconcilable unit.

Entries are subject to **prefix pruning**: writing an entry at a path deletes
older entries at paths that extend it, with newest-timestamp-wins. That is a
conflict-resolution rule, and it is the piece of Willow least applicable to
immutable content-addressed data.

### 2. Range-based set reconciliation

The sync algorithm proper. Covered in detail below.

### 3. Payload transfer as a separate negotiation

Willow reconciles **entries** (the small metadata records above), not payloads.
Payload transfer is a second, explicitly negotiated phase, and peers choose
per-payload between *eager* push (send it unasked, good for small payloads) and
*lazy* push (announce it, send only on request, good for large ones), typically
keyed on `payload_length`.

This is the single most transferable idea in the suite: **never let the
reconciliation unit be the bytes.**

### 4. Partial and incrementally verifiable payloads

A Willow entry may exist with its payload entirely absent, or present only up to
a prefix. A peer can serve, and a peer can verify, *part* of a payload without
holding the whole thing. This forces a constraint on the digest: it must support
incremental verification, which is why a Merkle-structured hash (BLAKE3) is a
natural fit and a flat SHA-256 over the whole payload is not.

### 5. Meadowcap and private area intersection

Meadowcap is Willow's capability system — who may write where, delegable and
attenuable. Private area intersection lets two peers discover which namespaces
and areas they *both* care about without either revealing its full interest set.

Both exist because Willow namespaces can be private and Willow entries are
mutable under prefix pruning. Neither assumption holds for public,
content-addressed media.

## How RBSR works

Both peers hold a set of items with a **total order** and agree on a
**fingerprint function** over ranges — an incremental, associative, commutative
hash (a monoid) so that the fingerprint of a range can be computed from its
parts, in any order.

1. A sends B a range and its fingerprint over that range.
2. B computes its own fingerprint for the same range.
   - **Equal** → the range is in sync. Done, recursively.
   - **Different, and the range holds few items** → B just sends the item list.
   - **Different, and the range is large** → B splits the range into
     sub-ranges, sends a fingerprint per part, and the process recurses.
3. Recursion terminates because ranges shrink monotonically.

Properties that follow from the structure:

- **No sizing parameter.** The recursion adapts to whatever the diff turns out
  to be. There is no table to size and no decode step to fail.
- **It always terminates with the right answer.** Worst case it degrades to
  exchanging item lists for the diverging ranges.
- **It localizes divergence.** You learn *which range* differs, not just a flat
  bag of differing elements. That is directly actionable — "this collection",
  "this time window", "this shard".
- **It can reconcile a slice.** A peer that only carries part of the keyspace
  states that as a range and reconciles only it. IBLT has no equivalent; it is
  whole-set or nothing.
- **Cost.** Roughly `O(d log n)` transferred over `O(log n)` round trips, versus
  IBLT's `O(d)` in one round trip. RBSR trades latency for robustness.

## IBLT versus RBSR

| Dimension | IBLT / rIBLT | RBSR (Willow) |
| --- | --- | --- |
| Requires a total order | No | Yes |
| Requires a range fingerprint | No | Yes (associative + commutative) |
| Diff size unknown a priori | Must size the table, or add rateless machinery | Intrinsic — recursion adapts |
| Round trips | 1 (plus retries) | `O(log n)` |
| Bytes transferred | `O(d)`, best in class when `d << n` | `O(d log n)` |
| Failure mode | **Silent probabilistic decode failure** | None; degrades to item lists |
| Behaviour as `d` → `n` | Worse than sending the whole list | Degrades gracefully |
| Localizes the divergence | No — flat unordered bag | Yes |
| Reconcile a sub-range only | No | Yes |
| Implementation risk | Hash choice, cell sizing, key-check field width, peeling termination | Ordering + fingerprint monoid |

The failure-mode row is the one that matters most for a service codebase. An
undersized IBLT does not crash; it returns *no answer* or, if the key-check
field is too narrow, a *wrong* one. RBSR has no analogous mode.

The implementation-risk row matters second. IBLT is a genuinely subtle structure
to get right, and its bugs are probabilistic and workload-dependent — the worst
kind to reproduce in CI.

## Applying this to `jelcz`

[ADR 0036](../../adr/0036-content-addressed-video-distribution.md) decides that
one **MASL manifest blob** names every segment of a video, and
[workstream 12](../../plans/workstreams/12-content-addressed-video.md) Phase 3
builds it with `resourceCIDForPath:` mapping each path to a segment CID.

That changes what question is even being asked. There are three distinct
questions, at three scales, and they have three different answers:

| Question | Scale | Right answer |
| --- | --- | --- |
| Do two nodes hold the same version of asset X? | 1 asset | Compare manifest CIDs. 32 bytes, already built. |
| Which segments of asset X does the peer hold? | ~10³ segments | Possession **bitmap** over manifest-ordered indices |
| Which assets does this mirror hold at all? | ~10⁷–10⁸ segment CIDs | **RBSR** over the CID-ordered keyspace |

Only the third is a set-reconciliation problem. The first two are answered by
artefacts the workstream already produces.

### Why possession is a bitmap, not a set difference

Once the manifest enumerates and orders the segments, "which do you have" is a
bitfield indexed by segment number — the design BitTorrent settled on in 2001.

Order-of-magnitude comparison for a one-hour video at six-second segments and
three renditions (~1,800 segments). These are estimates from the structures'
sizes, not measurements:

| Approach | Bytes on the wire | Round trips | Failure mode |
| --- | --- | --- | --- |
| Possession bitmap | ~225 raw; far less compressed | 1 | None — exact |
| RBSR, `d` = 100 | ~2–4 KB | ~4–8 | None |
| IBLT, `d` = 100 | ~6–7 KB (≈1.5 × 44-byte cells) | 1 (+ retries) | Silent decode failure |
| Full sorted CID list | ~56 KiB | 1 | None |

The bitmap wins by an order of magnitude *and* is exact. Possession is also
strongly clustered — sequential fetching produces contiguous runs — so run-length
or roaring encoding compresses it to near nothing. An IBLT here costs more than
simply stating possession of the entire set.

### Where RBSR does earn its place

At [workstream 12](../../plans/workstreams/12-content-addressed-video.md)
Phase 10 scale — two mirrors asking which of tens of thousands of assets, and
tens of millions of segment CIDs, they hold between them — the universe is
genuinely unknown to both sides and RBSR's advantages all bind: no sizing
problem, no decode failure, localized divergence, and the ability to reconcile
only a slice (one shard, or assets published since a given date). A mirror with
a partial catalog can express that; with IBLT it cannot.

RBSR also needs less new machinery here than it looks. It wants an ordering
(CID bytes, or `did`/`collection`/`rkey`) and a fingerprint over ranges — and a
MASL manifest CID is already a fingerprint over a subtree. The primitive exists.

## What Garazyk should take from Willow

| Willow idea | Verdict for Garazyk |
| --- | --- |
| Entry/payload split; eager vs lazy push | **Adopt.** Workstream 12 Phase 8's fetch-on-miss seam is the same boundary; Willow arriving at it independently is evidence the seam is placed correctly. |
| Partial payloads with incremental verification | **Adopt the constraint.** It is the argument for resolving Phase 9's open sidecar question with bao outboard encoding rather than a bespoke format. |
| RBSR | **Defer.** Not needed per-asset; the right tool if cross-mirror catalog sync ever becomes real (Phase 10). |
| 3D range products, `AreaOfInterest` | **Partially.** The *idea* of a reconcilable slice is useful for catalog sync. The three-dimensional product is more model than immutable media needs. |
| Meadowcap capabilities | **Do not adopt.** Phase 8's position — mirrors are ordinary HTTPS origins, and manifest CIDs make them untrusted-safe — is correct and strictly simpler. Content addressing gives integrity without authorization on the read path. |
| Prefix pruning, newest-timestamp-wins | **Do not adopt.** Segments are immutable and content-addressed. There is no conflict to resolve, and importing a resolution rule would invent one. |
| Private area intersection | **Do not adopt.** Public CDN content; there is no interest set to conceal. |

### The Phase 9 consequence

Workstream 12 defers Phase 9 with a specific blocker: `ATProtoBDASLVerifier`
provides streaming BLAKE3 verification but *"does not define a wire format for
the chunk-digest sidecar."*

Willow answers this by construction rather than by inventing a format — it
requires that the payload digest itself support incremental verification. In
practice that means BLAKE3 with [bao](https://github.com/oconnor663/bao)'s
outboard encoding, which is also what [iroh](https://iroh.computer/) — named in
Phase 10 as the leading peer-transport candidate — already uses for verified
range streaming.

This does not disturb ADR 0036's decision that *segment CIDs* are SHA-256 raw
(`0x55`). That decision is about atproto interoperability of addresses. Bao
outboard data is verification metadata carried alongside a fetch, not an
address, and ADR 0036 already scopes BLAKE3 to segment `src` values only.

## Prior art already in the tree

For anything scoped to a single atproto repository, neither algorithm is the
first thing to reach for. Every repo already ships a **Merkle Search Tree**, and
comparing MST subtree hashes gives an ordered, hierarchical, localizable diff
with no probabilistic step and no new primitive to implement. RBSR is what you
build when you need MST-like behaviour over a keyspace that has no shared tree;
inside a repo, the tree is right there.

That also corrects a tempting shortcut: atproto data is not an unordered key
set. It is ordered (`did`/`collection`/`rkey`), and its mutations arrive as an
ordered log (the firehose). Both facts argue against the order-free algorithm.

## Related decisions in this repository

- [Workstream 13 (beskid edge reconciliation)](../../plans/workstreams/13-beskid-edge-reconciliation.md)
  was rejected because a demand-filled TTL cache has no set-equality invariant
  to reconcile in the first place — a failure of the premise shared by both
  algorithms, not a choice between them.
- [Video discovery and peer-sharing options](video-discovery-and-peer-sharing-options.md)
  covers the discovery layer, which is a different problem: reconciliation
  answers "what differs between us", discovery answers "who has this at all".

## References

- [Willow protocol](https://willowprotocol.org/)
- [Willow 3d RBSR](https://willowprotocol.org/specs/rbsr/) — the reconciliation
  algorithm, which credits Aljoscha Meyer's "Range-Based Set Reconciliation"
- [Willow Confidential Sync](https://willowprotocol.org/specs/confidential-sync/)
  — private area intersection
- [bao — BLAKE3 verified streaming](https://github.com/oconnor663/bao)
- [iroh](https://iroh.computer/)
- [IBLT for atproto reconciliation](iblt-for-atproto-reconciliation.md) — the
  counterpart guide
