# PDS Hardening Remediation - 2026-05-22

## Goal

Remediate the PDS hardening findings linked from outcome `574` in three staged PRs.

## PR 1 - Repo Import And Write-Batch Safety

- Add route-boundary `applyWrites` shape and size validation.
- Remove full request body/write payload info logs.
- Add private repo-import validation before actor-store writes.
- Bound import body, CAR block count, MST node/record count, and MST depth.
- Recompute CAR block CIDs, verify CAR root/commit CID, verify commit signatures, and reject missing/cyclic MST links.

## PR 2 - Public Sync Resource Bounds

- Use SQL-backed account pagination for public sync scans.
- Bound `listRepos` and `listReposByCollection` scans with DID cursors.
- Cap `getBlocks` CID count and response size.
- Stream `getCheckout` from repo chunk producers.
- Lower public full-repo export safety cap to 100000 records.

## PR 3 - Blob, Path, And SQL Sink Hardening

- Reject active MIME uploads.
- Add `nosniff` and attachment disposition for unsafe blob downloads.
- Validate DID path sinks in database path derivation.
- Validate public sync DID parameters with `ATProtoValidator`.
- Replace dynamic SQL column type permissiveness with an exact allowlist.

