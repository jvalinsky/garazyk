# Phase 6: Lexicon Completeness Test

## Verify `com.atproto.lexicon.resolveLexicon`

**Goal:** Confirm all registered XRPC method lexicons can be resolved

**Test in LexiconResolveXrpcTests.m:**

1. Get all registered method names from `XrpcMethodRegistry`
2. For each method, call `/xrpc/com.atproto.lexicon.resolveLexicon?def={method}`
3. Verify response:
   - `200 OK` (not 404 or 501)
   - `lexiconDoc` field present
   - `lexiconDoc.id` matches requested method
   - `proxied` field is boolean

**Status:** [ ] In progress

## Coverage

Must resolve without 404:
- All `com.atproto.*` methods
- All `app.bsky.*` methods (whether proxied or local)
- All non-standard methods (at least return valid lexicon)
