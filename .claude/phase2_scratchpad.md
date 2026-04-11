# Phase 2: Add Missing Spec Endpoints

## 2.1 `app.bsky.draft.*` Stubs (4 methods)

- createDraft ✓
- deleteDraft ✓
- getDrafts ✓
- updateDraft ✓

Pattern: Use `proxyOrNotSupported:` like `app.bsky.ageassurance.*`

**Status:** [X] COMPLETED

## 2.2 `app.bsky.graph.verification.*` Stubs (2 methods)

- createVerification ✓
- deleteVerification ✓

Pattern: Use `proxyOrNotSupported:`

**Status:** [X] COMPLETED

## 2.3 `app.bsky.unspecced` Age Assurance Stubs (2 methods)

- getAgeAssuranceState ✓
- initAgeAssurance ✓

Pattern: Use `proxyOrNotSupported:`

**Status:** [X] COMPLETED

File: `ATProtoPDS/Sources/Network/XRPC/XrpcAppBskyMethods.m`

## Implementation Summary

All 8 stub registrations added to XrpcAppBskyMethods.m:
- Forward declarations added (lines 278-285)
- Registration calls added in registerWithDispatcher (lines 2860-2871)
- Method implementations added (lines 2969-3019)

All methods use the `proxyOrNotSupported:` pattern consistently with existing stubs.
