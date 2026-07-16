# ADR 0005: Space Reconciliation After Oplog Pruning

## Status

Accepted — 2026-07-16

## Context

Proposal 0016 defines the permissioned-data sync protocol. A syncer (reader
PDS) keeps a local copy of each member's repo and a running set hash over
that copy. The syncer advances by calling `com.atproto.space.listRepoOps`
with a `since` revision. If the response includes the signed commit, the
syncer compares the commit's `hash` against its running set hash to verify
synchronization.

The oplog is explicitly a **transport optimization, not a committed data
structure**. The proposal states:

> A repo host may compact or drop it, retaining only a backfill window. It
> is also reset on account migration. In any such case, a syncer that
> cannot find its `since` revision falls back to full-state recovery, which
> does not depend on the oplog.

Full-state recovery fetches the whole repo as a CAR from
`com.atproto.space.getRepo`, folds the DRISL index into a running set hash,
compares against the signed commit, validates each record block against its
index CID, and rebuilds the local copy.

For slight divergence, the proposal also describes a lightweight path:

> For the narrower case of healing a copy that has only slightly diverged,
> a syncer may prefer to avoid transferring the whole repo. It can fetch
> the latest commit through `com.atproto.space.getLatestCommit`, enumerate
> the repo's structure (paths → CIDs) with `com.atproto.space.listRecords`
> using `excludeValues`, diff that lightweight listing against its local
> copy, and fetch just the differing records with
> `com.atproto.space.getRecord`.

### Current implementation

- `listRepoOps`, `getRepo`, `getLatestCommit`, `listRecords`, `getRecord`
  are implemented in `XrpcSpacePack.m` and authenticated via
  `SpaceReadAuthentication`.
- `SpaceRepoCAR` produces a correct two-root CAR (commit + DRISL index,
  then records in lexicographic order).
- `PDSSpaceReconciler` handles **outbound** notification replay (writer →
  authority). It does not do **inbound** sync (reader → authority).
- `PDSSpaceStore` has no method to import a CAR, no oplog pruning method,
  and no local record index method for diffing.
- `CARReader` only exposes the first root (`rootCID`). The space CAR has
  two roots; the second (DRISL index) is not accessible via the reader API.
- `listRecords` and `listRepoOps` handlers do not return `cursor` in their
  responses, despite the lexicons defining the field. This makes
  pagination impossible for clients. This is a bug that must be fixed for
  the lightweight recovery path to work.
- Scenario 93 does not exercise full-state recovery after oplog pruning.
- The compatibility gate states: "remote state-import/full-CAR
  reconciliation pending."

## Decision

Implement the full reconciliation protocol as defined by the upstream
proposal, including both recovery paths (full CAR and lightweight) and
oplog pruning. No new XRPC endpoints are needed — the server already has
all required endpoints. The missing pieces are client-side: CAR reader
multi-root support, a store import method, a local record index method,
oplog pruning, pagination fixes, and a reconciler inbound sync loop.

### Gap detection: client-side chain validation

The syncer detects an oplog gap by checking whether the first returned
op's `prev` matches the `since` revision it passed. If not, the oplog has
been pruned past the cursor and the syncer falls back to recovery.

No server-side change or lexicon change is needed. The `prev` field on
oplog entries already provides the chain linkage. A future enhancement
could add a `SinceNotFound` error to `listRepoOps` for explicit
server-side signaling, but it is not required for correctness.

### Recovery path selection

After detecting a gap, the reconciler must choose between two recovery
paths. The decision tree:

1. **Local repo is empty** (first sync, or after space deletion recovery):
   → Full CAR via `getRepo`. No point diffing against nothing.

2. **Local repo exists, gap detected**:
   a. Fetch the lightweight listing via `listRecords(excludeValues=true)`
      with pagination. This is cheap — just `{collection, rkey, cid}` per
      record, no record data.
   b. Build remote `{path → CID}` map.
   c. Get local `{path → CID}` map from `PDSSpaceStore`.
   d. Compute diff: records to add (in remote, not local), records to
      update (in both, CID differs), records to delete (in local, not
      remote).
   e. If the total number of changed records is small (≤ threshold):
      fetch each changed record via `getRecord`, apply locally.
   f. If the total number of changed records is large (> threshold):
      fall back to full CAR via `getRepo`.

The threshold is configurable with a default of 50 records or 25% of the
total record count, whichever is smaller. This means:
- For a repo with 100 records: threshold is 25 (25% of 100).
- For a repo with 1000 records: threshold is 50 (min of 50 and 250).
- For a repo with 10 records: threshold is 2 (25% of 10, min of 50 and 2).

The rationale: the lightweight path costs `ceil(R/100) + C` round-trips
(listing pages + getRecord calls), while the full CAR costs 1 round-trip
but transfers all record data. When `C` is small relative to `R`, the
lightweight path saves bandwidth at the cost of a few extra round-trips.
When `C` is large, the full CAR is more efficient.

### Full-state recovery: CAR import via CARReader

The CAR from `getRepo` has two roots:

1. **Signed commit** (DAG-CBOR): `{ ver, hash, mac, ikm, sig, rev }`
2. **DRISL index** (DAG-CBOR): `{ "{collection}/{rkey}" → CID }`

Followed by record blocks in lexicographic order.

The import procedure uses `CARReader` (after adding multi-root support):

1. Parse the CAR via `CARReader`, extract both roots from the `roots`
   array.
2. Fetch the commit block (root 0) and index block (root 1) by their
   root CIDs using `blockWithCID:`.
3. Decode the commit block as DAG-CBOR: `{ ver, hash, mac, ikm, sig, rev }`.
4. Verify the commit signature using the author's `#atproto` public key
   via `PDSSpaceCommit.verifySignatureForSpace:author:publicKey:error:`.
5. Verify the commit MAC via `PDSSpaceCommit.verifyIntegrityForSpace:author:error:`.
6. Decode the index block as DAG-CBOR: `{ path → CID }`.
7. For each entry in the index, locate the corresponding record block by
   CID via `blockWithCID:` and validate the block's CID matches.
8. Rebuild the LtHash from the index entries: `addElement("{collection}/{rkey}/{cid}")`
   for each.
9. Compute the SHA-256 digest of the LtHash state and compare against the
   commit's `hash`.
10. In a single SQLite transaction: delete existing `space_record` rows
    for this space+author, insert the imported records, update `space_repo`
    with the new lthash_state and rev, truncate the oplog for this author.

This is a **full-state replacement**, not a merge. The CAR is authoritative
from the repo host.

### Lightweight recovery: listRecords diff + getRecord

After the lightweight listing and diff (see "Recovery path selection"
above), the reconciler applies changes individually:

1. For each record to add or update: fetch the record via `getRecord`,
   decode the value, apply via `applyWrites:` with the appropriate action.
2. For each record to delete: apply via `applyWrites:` with delete action.
3. After all changes, rebuild LtHash from the final record set and verify
   against the commit's `hash`.

The lightweight path applies changes through the existing `applyWrites:`
method, which handles LtHash updates and oplog entries atomically. This
means the oplog is populated with the recovery operations, which is
correct — the oplog should reflect what happened, even if it was a
recovery rather than a normal write.

### Oplog pruning: best practices

The proposal says: "A repo host may compact or drop it, retaining only a
backfill window." The best practices implementation:

**Retention policy:** Count-based. Keep the last N distinct revisions per
(space, author) pair. Default: 100 revisions. This is simpler than
time-based pruning (which would require parsing TID timestamps) and
provides a predictable bound on oplog size.

**Implementation:**
- `PDSSpaceStore.pruneOplogForSpace:author:keepingRevisions:error:` —
  per-repo pruning. Deletes all oplog entries except the last N distinct
  revisions.
- `PDSSpaceStore.pruneAllOplogsKeepingRevisions:error:` — batch pruning
  for all repos with oplog entries. Iterates over all distinct
  (space, author_did) pairs and prunes each one.
- A periodic timer in the PDS runtime calls `pruneAllOplogsKeepingRevisions:`
  on a configurable interval (default: 1 hour).
- Config: `permissionedSpacesOplogRetentionCount` (default: 100),
  `permissionedSpacesOplogPruneInterval` (default: 3600 seconds).
- For tests: call `pruneOplogForSpace:author:keepingRevisions:error:`
  directly on the store.

**SQL for per-repo pruning:**
```sql
DELETE FROM space_record_oplog
WHERE space = ? AND author_did = ?
  AND rev NOT IN (
    SELECT DISTINCT rev FROM space_record_oplog
    WHERE space = ? AND author_did = ?
    ORDER BY rev DESC
    LIMIT ?
  )
```

This keeps the last N distinct revisions (each revision may have multiple
ops with different `idx` values). The `NOT IN` subquery selects the
revisions to keep, and the outer query deletes everything else.

**Why count-based, not time-based:**
- TIDs are monotonic but parsing timestamps from them adds complexity.
- Count-based provides a predictable bound on oplog size.
- The proposal says "backfill window" — a count-based window is a valid
  interpretation.
- Time-based pruning could be added later as a secondary policy (keep
  last N revisions OR entries from last T hours, whichever is larger).

**Why a background timer, not inline pruning:**
- Pruning during request handling would add latency to writes.
- A background timer decouples pruning from the write path.
- The timer is configurable and disabled by default (since permissioned
  spaces are experimental). When enabled, it runs on a serial queue
  similar to the reconciler.

### Pagination fix for listRecords and listRepoOps

Both handlers currently accept a `cursor` query parameter but do not
return a `cursor` in the response. The lexicons define the `cursor`
field in the output schema. This is a bug.

**Fix:** When the number of returned records/ops equals the limit, include
the cursor in the response. The cursor is the last record's
`{collection}/{rkey}` (for `listRecords`) or the last op's `rev` (for
`listRepoOps`).

This fix is a prerequisite for the lightweight recovery path, which
requires paginating through all records via `listRecords`.

### Reconciler inbound sync

Extend `PDSSpaceReconciler` to perform inbound sync in addition to its
existing outbound notification replay. The inbound sync loop:

1. For each replicated space+author (where this PDS is not the authority):
   a. Call `getLatestCommit` on the remote authority.
   b. If the remote head's `rev` matches local `rev` → done.
   c. If not, call `listRepoOps` with `since=local_rev`.
   d. If the first op's `prev` matches `since` (or `since` is nil):
      apply ops locally, update LtHash, check commit hash.
   e. If the first op's `prev` does not match `since` (gap detected):
      enter recovery path selection (see above).

The inbound sync runs on the same periodic timer as the existing outbound
replay. It uses the same service-auth JWT mechanism for authentication.

**Replicated space enumeration:** The reconciler needs to know which
spaces it has local copies of (where it's not the authority). The existing
`repositoriesForReconciliation:` method returns all repos with state,
including both authority-owned and replicated. The reconciler filters to
only non-authority repos by checking `[space.authorityDID isEqualToString:author]`
(like the existing `replayHead:` method does).

## Consequences

- `CARReader` gains a `roots` property (NSArray<CID *> of all root CIDs).
  The existing `rootCID` property is preserved as `roots.firstObject` for
  backward compatibility.
- `PDSSpaceStore` gains:
  - `importRepoFromCAR:space:author:commitPublicKey:error:` — full-state CAR import.
  - `recordIndexForSpace:author:error:` — local `{path → CID}` map for diffing.
  - `pruneOplogForSpace:author:keepingRevisions:error:` — per-repo oplog pruning.
  - `pruneAllOplogsKeepingRevisions:error:` — batch oplog pruning.
- `PDSSpaceReconciler` gains an inbound sync pass alongside its existing
  outbound replay, with the three-path recovery strategy (incremental,
  lightweight, full CAR).
- `listRecords` and `listRepoOps` handlers return `cursor` for pagination.
- Scenario 93 gains a reconciliation test step (or a new scenario tests
  CAR recovery specifically).
- The compatibility gate "Multi-PDS recovery" row can move to "Implemented"
  once the scenario passes.
