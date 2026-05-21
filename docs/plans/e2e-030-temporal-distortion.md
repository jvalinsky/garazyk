# Sub-plan: 30 — Temporal Distortion (MST Race Condition)

## Problem
"Missing root in getHead" — MST root CID not found after concurrent operations.

## Investigation

### Expected behavior
Under concurrent writes, the MST (Merkle Search Tree) should correctly track the current root CID. `getHead` returns the root CID of the repository.

### Root cause candidates
1. **Concurrent commit race**: Two concurrent writes produce overlapping MST mutations, and the final root CID doesn't match any commit's root
2. **MST merge bug**: When two branches are merged, the resulting root isn't stored consistently
3. **In-memory cache stale**: MST node cache has stale entries after concurrent mutations
4. **Commit ordering**: The `getHead` endpoint reads from a different snapshot than where commits are written

## Work

### 1. Understand MST commit flow
- Find MST implementation in `Garazyk/Sources/`
- Trace the commit path: `createRecord` → MST mutation → root CID update
- Check for locks/synchronization around MST operations

### 2. Reproduce with logging
- Add verbose logging to MST operations during concurrent writes
- Show before/after root CIDs for each commit

### 3. Check synchronization
- Is there a lock protecting MST mutations?
- Are reads (getHead) synchronized with writes?
- Is there a transaction boundary issue?

### 4. Potential fix directions
- Add write lock around MST mutations
- Use compare-and-swap for root CID updates
- Add retry on concurrent modification

## Files
- `Garazyk/Sources/Core/MST*` (MST implementation)
- `Garazyk/Sources/Repo/` (repo/commit management)
- `Garazyk/Sources/Network/XrpcServerPack.m` (getHead handler)
- `scripts/scenarios/scenarios/30_temporal_distortion.ts` (scenario)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 30"
```
