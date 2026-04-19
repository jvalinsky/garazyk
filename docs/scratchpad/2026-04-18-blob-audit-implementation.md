# Blob Audit Implementation Scratchpad

## Goal
Implement missing logic for blob auditing operations: orphan detection, CID verification, and consistency checking.

## Architectural Choices
- **Generic Blob Listing**: Added `listAllCIDsWithError:` to `PDSBlobProvider` protocol and implemented it for disk storage.
- **Actor Store Iteration**: Since blob metadata is sharded per-actor, audit operations will iterate through all registered accounts to build a global map of "expected" blobs.
- **Progress Tracking**: Operations will report progress based on the number of accounts processed and files scanned.

## Implementation Details
- `PDSBlobOrphanScanOperation`: 
  1. List all CIDs from provider.
  2. Iterate all accounts in `PDSDatabasePool`.
  3. Query `blobs` table for each account to mark CIDs as "registered".
  4. Compare results to find unregistered (orphan) files.
- `PDSBlobCIDVerificationOperation`:
  1. List all CIDs from provider.
  2. For each CID, read data and re-calculate SHA256.
  3. Flag mismatches.
- `PDSBlobConsistencyCheckOperation`:
  1. Iterate all accounts.
  2. For each account, scan `records` or MST for blob references.
  3. Verify each reference has a corresponding entry in `blobs` table AND exists in `PDSBlobProvider`.

## Tracking
- Choice: Handling sharded actor store databases for blob metadata comparison. [deciduous: 20260418-sharded-blob-audit]
