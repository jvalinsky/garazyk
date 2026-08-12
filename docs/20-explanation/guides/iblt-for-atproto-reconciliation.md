---
title: IBLT for atproto reconciliation
---

# IBLT for atproto reconciliation

This guide explains **Invertible Bloom Lookup Tables (IBLT)** and the
“rateless IBLT” variant, and shows how they map onto practical atproto-style
inventory reconciliation problems (caches, indexes, mirror inventories).

The focus is on *when* IBLT helps, *what* you reconcile, and *what you must
cap* to keep it operationally safe.

IBLT is one of several answers to "what differs between us", and in this
codebase it is usually not the best one. Read
[Range-based set reconciliation and the Willow protocol](range-based-set-reconciliation.md)
alongside this guide before choosing: atproto keyspaces are ordered and
content-addressed data often publishes its own inventory, and both facts erode
IBLT's advantages.

## What problem IBLT solves

IBLT is a **set reconciliation** protocol: two peers each hold a large set
`A` and `B` and want to learn the **symmetric difference**:

`(A - B) ∪ (B - A)`

without exchanging the whole sets.

IBLT is most helpful when:

- the sets are large,
- overlap is high (diff is small relative to set size),
- you don’t know the diff size ahead of time (or you want to avoid tuning a
  fixed “right” table size).

## How fixed-size IBLT works (conceptual)

At a high level, a peer:

1. Chooses an IBLT table size `m` (number of cells) and hash functions `k`.
2. Inserts each element of its set into the table using `k` hash locations.
3. Sends the IBLT cells (not the original set).
4. The receiver subtracts its own IBLT from the sender's.
5. The remaining “peeled” cells allow decoding of the missing/extra elements.

When the set difference is too large relative to `m`, decoding fails.

## Rateless IBLT (rIBLT) in one paragraph

“Rateless IBLT” variants encode the set difference into an **incremental
infinite stream of coded symbols**, so the receiver can stop after it has
received enough symbols to decode.

This avoids hard sizing parameters and is particularly attractive when diff
size is unknown or adversarial.

Primary references:
- [Practical Rateless Set Reconciliation (SIGCOMM 2024)](https://doi.org/10.1145/3651890.3672219)
- [Rateless IBLT implementation (riblt)](https://github.com/yangl1996/riblt)
- [ConflictSync (rateless + digest-driven CRDT sync)](https://arxiv.org/html/2505.01144)

## Why IBLT maps to “edge cache inventories”

For atproto infrastructure components like `beskid` (edge caches) or mirror
services, the reconciliation unit is typically a **key inventory**, not the
payload:

- a stable key hash for each cached object
- plus (optionally) a small fingerprint for payload versioning / integrity

In practice:

1. Reconcile `key_hash` sets (fast, bounded transfer).
2. Fetch values only for the decoded `missing` keys (slow path).
3. Validate the fetched values against existing content validation rules
   before writing into the cache.

This two-stage approach turns reconciliation into a “cheap diff” that drives
selective data transfer.

## What you should reconcile in an atproto context

Recommended elements are stable, fixed-size, and cheap to compute.

| Inventory | Example set element | Why it works |
|---|---|---|
| Record cache inventory | `hash(did + collection + rkey)` (+ version marker) | stable identity of cached object |
| Identity cache inventory | `hash(did + plcDocCidOrVersion)` | stable pointer to the cached identity version |
| Segment/manifest cache inventory | `segment_cid` or `manifest_cid` | immutable identifiers make diffs straightforward — but see "When *not* to use IBLT" below: within one asset the manifest already enumerates the set |
| Index/shard inventory | `doc_id` or `shard_key` | indexes are often set-like and can be diffed by keys |

Avoid reconciling:

- raw payload bytes (too big; you end up transferring everything),
- large variable-size strings (complicates fixed element encoding),
- security-sensitive data without a strict validation precondition.

## Fixed-size vs rateless: decision table

| Choice | Pros | Cons | Pick it when |
|---|---|---|---|
| Fixed-size IBLT | simpler protocol, easier implementation | decode failures require retry or fallback | you can bound diff sizes and have a safe fallback path |
| Rateless IBLT | robust to unknown diff sizes; avoids sizing knobs | more complex coding/streaming logic | diff sizes vary widely, and operational tuning is painful |

## Operational guardrails (this is the part that usually matters)

IBLT can be correct and still be a DoS vector if you allow unbounded computation
or transmission. Treat it like a “cap-heavy” protocol.

Mandatory caps:

1. `max_table_size` (or `max_symbols` for rIBLT).
2. `max_decode_cpu_ms` per session.
3. `max_bytes_sent/received` per session.
4. `max_keys_fetched` per session.
5. Circuit breakers when serving latency increases or decode failure rates spike.

Security expectations:

- elements are hashes; never interpret element hashes as trust anchors
- always validate fetched values against existing atproto rules
- authenticate peer sessions; do not allow arbitrary unauthenticated reconcilers

## When *not* to use IBLT

Three disqualifiers, in the order they usually apply. Each is common in this
codebase.

### 1. There is no set-equality invariant

IBLT reconciles sets that are *supposed* to be equal, so that the symmetric
difference means "damage". If divergence between two nodes is the correct
outcome of their differing workloads, the diff is not damage and closing it is
not repair.

This is what sank [workstream 13](../../plans/workstreams/13-beskid-edge-reconciliation.md).
`beskid` is a demand-filled TTL read-through cache, not a replica: two edges
hold what their own users read, and TTL expiry keeps the symmetric difference
continuously non-empty regardless. For TTL caches prefer invalidation
(firehose) plus selective prefetch of hot keys over symmetric-difference
reconciliation.

### 2. The universe is already known and enumerated

Content-addressing frequently publishes the inventory up front, which answers
the question IBLT exists to answer. Under
[ADR 0036](../../adr/0036-content-addressed-video-distribution.md) a `jelcz`
MASL manifest names every segment of a video and commits to them under a single
CID. Two nodes holding the same manifest already agree on what the set should
contain; what remains is *possession* over a known, ordered index, which is a
bitfield, not a set difference — and a bitfield is roughly an order of magnitude
smaller than an IBLT over the same data.

### 3. The keyspace is ordered

Where an ordering exists, range-based reconciliation gives you the same result
with no sizing parameter, no probabilistic decode failure, localized divergence,
and the ability to reconcile only a sub-range. atproto keys are ordered
(`did`/`collection`/`rkey`), and every repo already ships an MST whose subtree
hashes give a hierarchical diff for free.

See [the RBSR guide](range-based-set-reconciliation.md) for the full comparison
and the sizing numbers.

## Where IBLT still fits in Garazyk

What survives the three filters above is narrow but real: **large, unordered,
"should be equal" inventories whose contents are not published anywhere and
where a single round trip is worth more than graceful degradation.**

Candidates, none of them currently planned work:

- mirror or cache fleets that replicate an inventory with a clear convergence
  goal and no manifest enumerating it,
- set-like secondary indexes needing bandwidth-efficient repair after a
  partition, where no ordering on the key is convenient.

For cross-mirror media catalog sync — the largest set-reconciliation problem
this repository is likely to grow, deferred at
[workstream 12](../../plans/workstreams/12-content-addressed-video.md) Phase 10 —
the keyspace *is* ordered, so RBSR is the better default there.

## Concrete “start small” deployment approach

| Phase | What to ship | Why |
|---|---|---|
| Phase 0 | inventory set reconciliation via full keylist diff (capped) | proves wiring and trust boundary |
| Phase 1 | fixed-size IBLT with decode failure fallback to keylist | introduces bandwidth savings safely |
| Phase 2 | rateless IBLT only if decode failures or retries dominate | avoids premature complexity |

## References

- [Range-based set reconciliation and the Willow protocol](range-based-set-reconciliation.md)
  — the ordered alternative, and when to prefer it
- [Practical Rateless Set Reconciliation (SIGCOMM 2024)](https://doi.org/10.1145/3651890.3672219)
- [riblt implementation](https://github.com/yangl1996/riblt)
- [ConflictSync: Bandwidth Efficient Synchronization of Divergent State](https://arxiv.org/html/2505.01144)
- [libp2p rendezvous docs (for broader provider discovery context)](https://libp2p.io/docs/rendezvous/)

