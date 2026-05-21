# Sub-plan: 51 — Blob Garbage Collection Keep-Alive

## Problem
Keep-alive blob is collected (deleted) by GC when it should be preserved.

## Investigation

### Expected behavior
Blob GC should:
1. Enumerate all blobs referenced by records in the repo
2. Enumerate all "keep-alive" blobs (blobs that should survive even without current record references)
3. Delete only blobs NOT in either set
4. Keep-alive blobs should survive

### Root cause candidates
1. **Keep-alive list not populated**: The keep-alive reference list is empty during GC
2. **Keep-alive not checked**: GC enumerates record-referenced blobs but skips the keep-alive check
3. **Race condition**: Blob becomes keep-alive after GC enumerates but before deletion
4. **Keep-alive stored in wrong place**: Keep-alive references stored in memory but GC reads from DB

## Work

### 1. Find Blob GC implementation
- Search for blob GC code in `Garazyk/Sources/`
- Find where unreferenced blobs are identified and deleted
- Check how blob references are tracked

### 2. Find keep-alive mechanism
- Search for "keep-alive", "keepalive", "keepAlive" in blob-related code
- Find where keep-alive blobs are registered
- Check if keep-alive survives process restart (DB vs. memory)

### 3. Add missing keep-alive check
- If keep-alive is stored in a DB table, ensure GC queries it
- If keep-alive is in memory, ensure GC has access to the same list
- Add the keep-alive set to the GC's deletion sweep logic

## Files
- `Garazyk/Sources/BlobStore/` or `Garazyk/Sources/Blob/` (blob storage)
- `Garazyk/Sources/Services/BlobGC*` (GC logic)
- `scripts/scenarios/scenarios/51_blob_garbage_collection.ts` (scenario)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 51"
```
