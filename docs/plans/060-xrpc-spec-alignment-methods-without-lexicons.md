---
title: "Spec alignment: reconcile code-registered methods missing in lexicons"
---

# Spec alignment: reconcile code-registered methods missing in lexicons

## Summary

The code registers several XRPC methods that are not present in the current `Garazyk/Resources/lexicons/**` set. We need to decide for each:

- Remove the endpoint (if obsolete),
- Rename it to match a current lexicon method,
- Add/restore a lexicon definition (if it's a vendored/legacy method we want to keep).

This work matters because:
- Clients and tooling expect lexicons to describe the API surface.
- Our coverage reports become noisy and misleading if the server ships methods that have no schema.
- Several of these methods live in *standard namespaces* (`com.atproto.*`, `app.bsky.*`); if they're not in upstream lexicons, we should strongly prefer aligning rather than diverging.

## Current mismatch list (as of 2026-02-12)

In-scope (`com.atproto.*`) mismatch status:
- `missing_in_lexicons`: **0** (resolved)
- `unknown` IDs: **0** (resolved)

Out-of-scope note:
- `app.bsky.user.getUserStats` remains intentionally out of `com.atproto.*` scope policy.

## Execution update (2026-02-12)

Added compatibility lexicons for previously unmatched in-scope method IDs:

- `com.atproto.admin.moderateAccount`
- `com.atproto.admin.moderateRecord`
- `com.atproto.admin.takeDownAccount`
- `com.atproto.admin.getAccountTakedown`
- `com.atproto.label.createLabel`
- `com.atproto.label.getLabels`
- `com.atproto.repo.getBlob`
- `com.atproto.repo.deleteBlob`
- `com.atproto.repo.updateRecord`
- `com.atproto.server.getAccount`

Added files:
- `Garazyk/Resources/lexicons/com/atproto/admin/moderateAccount.json`
- `Garazyk/Resources/lexicons/com/atproto/admin/moderateRecord.json`
- `Garazyk/Resources/lexicons/com/atproto/admin/takeDownAccount.json`
- `Garazyk/Resources/lexicons/com/atproto/admin/getAccountTakedown.json`
- `Garazyk/Resources/lexicons/com/atproto/label/createLabel.json`
- `Garazyk/Resources/lexicons/com/atproto/label/getLabels.json`
- `Garazyk/Resources/lexicons/com/atproto/repo/getBlob.json`
- `Garazyk/Resources/lexicons/com/atproto/repo/deleteBlob.json`
- `Garazyk/Resources/lexicons/com/atproto/repo/updateRecord.json`
- `Garazyk/Resources/lexicons/com/atproto/server/getAccount.json`

Validation:
- `node scripts/generate_xrpc_coverage_report.js --source-only` now reports `missing_in_lexicons: 0` for `com.atproto.*`.
- Targeted suites pass:
  - `AdminAuthXrpcTests` (30/0)
  - `LexiconResolveXrpcTests` (4/0)
  - `RepoAuthXrpcTests` (66/0)

## Goals

- Every code-registered XRPC method has an explicit decision: keep (with lexicon), rename/alias, or remove.
- Prefer upstream-standard method IDs/lexicons whenever possible.
- If we keep a non-standard endpoint for internal tooling:
  - consider moving it to a vendor namespace, or
  - add a vendor lexicon and explicitly include it in scope tooling.

## Non-goals

- Achieving full `app.bsky.*` parity (that's outside core PDS scope unless we explicitly opt in).

## Proposed resolution workflow

1) For each method ID:
- Identify whether there is a current lexicon equivalent.
- If yes: rename registration + adjust handler request/response shape to match.
- If no:
  - decide "keep as vendored legacy" vs "remove"
  - if kept: add lexicon JSON under a "vendor" namespace (or restore old lexicon)

2) Fix coverage tooling
- Update schema-sync tooling to parse `registerMethod:@"<nsid>"` so the diff report doesn't include `unknown`.

## Per-method investigation notes

- `com.atproto.label.createLabel` / `com.atproto.label.getLabels`:
  - Current `Garazyk/Resources/lexicons/com/atproto/label/` contains `queryLabels` + `subscribeLabels`, not these.
  - Decide whether to:
    - remove the old endpoints and keep only `queryLabels/subscribeLabels`, or
    - add lexicon definitions for the old endpoints as legacy.
  - Note: these methods are used by `scripts/test_moderation.sh` today; migrating scripts/tests is part of the work if we remove/rename.

- `com.atproto.repo.getBlob` / `deleteBlob`:
  - Current lexicons likely use `com.atproto.sync.getBlob` (exists) and blob upload methods.
  - Decide whether repo-scoped blob access endpoints should exist.
  - Note: these method IDs also appear in fuzzing corpus inputs; removal requires updating fuzz inputs.

- `com.atproto.repo.updateRecord`:
  - Current write API uses `putRecord` and `applyWrites`.
  - Decide whether `updateRecord` is legacy and should be removed.

- `com.atproto.server.getAccount`:
  - There are now admin endpoints for account info; likely legacy.

- `app.bsky.user.getUserStats`:
  - Not present in bundled app.bsky lexicons; likely not PDS scope.
  - Note: this method is exercised by `scripts/test_getUserStats.sh`; decide whether to:
    - de-scope/remove, or
    - add a vendored lexicon (risky in `app.bsky.*` namespace).

- `com.atproto.admin.takeDownAccount` / `getAccountTakedown`:
  - String-based registrations with no lexicons present.
  - Decide whether these are internal/vendored admin endpoints; if so, add lexicon definitions or remove.
  - Strong preference: align with the standard admin moderation surface:
    - `com.atproto.admin.updateSubjectStatus`
    - `com.atproto.admin.getSubjectStatus`
    - (or other upstream-admin methods, depending on desired semantics)

## Files likely touched

- `Garazyk/Sources/Network/XrpcMethodRegistry.m`
- `Garazyk/Sources/Network/XrpcHandler.{h,m}`
- `Garazyk/Resources/lexicons/**` (if we add/restore lexicons)
- `lexicons/**` (if we decide to add vendor lexicons outside the bundled set)
- `scripts/generate_xrpc_coverage_report.js` / schema-sync tooling (to keep reports accurate)
- `scripts/test_moderation.sh` / `scripts/test_getUserStats.sh` (if we migrate off legacy endpoints)
- `fuzzing/corpus_xrpc/*` (if we remove legacy endpoints referenced by corpus)

## Definition of done

- [x] Every in-scope mismatched method has an explicit decision: keep via compatibility lexicon.
- [x] Diff report contains no `unknown` IDs (string-based registrations are parsed).
- [x] Tests cover compatibility behavior and lexicon loading for this change set.

## Subtasks (suggested breakdown)

- [x] For each in-scope mismatched method:
  - [x] Locate registration + handler code.
  - [x] Search for internal usage (scripts/tests/CLI/fuzz corpus).
  - [x] Identify upstream lexicon equivalent (if any).
  - [x] Decide: keep via compatibility lexicon for now.
- [ ] Follow-up (optional hardening pass):
  - [ ] Replace legacy methods with canonical upstream methods where feasible.
  - [ ] Remove compatibility methods only after scripts/tests/fuzz corpus are migrated.
  - [ ] Re-run schema-sync/coverage after each removal batch.
