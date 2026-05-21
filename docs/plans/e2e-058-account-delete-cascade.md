# Sub-plan: 58 — Account Delete Cascade

## Problem
After account deletion, records, CAR archive, and blobs remain accessible. Three failures:
1. "Records gone after delete" — records still accessible (expected failure)
2. "Repo CAR inaccessible after delete" — CAR still accessible (expected failure)
3. "Blob inaccessible after account delete" — blobs still accessible (expected failure)

## Work

### 1. Find account deletion handler
- Search for `com.atproto.server.deleteAccount` or `com.atproto.account.delete` handler
- Find the `deleteAccount` flow in `Garazyk/Sources/`

### 2. Audit current deletion scope
- Does it only mark the account as deleted/tombstoned?
- Does it delete the session?
- Does it touch records, CAR, or blobs at all?

### 3. Implement full deletion cascade

Phase 1 — Records:
- Delete all records associated with the DID from the `records` table
- Or revoke access to them (return 404 after deletion)

Phase 2 — CAR archive:
- Delete or invalidate the CAR file from blob storage
- If CAR is stored as a blob, remove it

Phase 3 — Blob cleanup:
- Delete blobs associated with the account's records
- Or mark them as orphaned for GC to clean up later

### 4. Transaction safety
- Ensure deletion is atomic (all-or-nothing) or at least idempotent
- Handle partial failures gracefully

## Files
- `Garazyk/Sources/Network/XrpcServerPack.m` (server handlers)
- `Garazyk/Sources/Services/AccountService*` (account management)
- `Garazyk/Sources/BlobStore/` (blob storage)
- `Garazyk/Sources/Database/` (record queries)
- `scripts/scenarios/scenarios/58_account_delete_cascade.ts` (scenario)

## Verification
```bash
nix develop -c bash -c "cd scripts/scenarios && deno run -A e2e_runner.ts --scenario 58"
```
