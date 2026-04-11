# Phase 1: Wire Up Existing Internals

## 1.1 OAuth Token Introspection Endpoint

**Goal:** Add `POST /oauth/introspect` route to expose existing `OAuthProvider.introspectToken:` method

**Files modified:**
- `ATProtoPDS/Sources/Auth/OAuth2Handler.m` — added route registration and handleIntrospectRequest method
- `ATProtoPDS/Tests/Auth/OAuthConformanceTests.m` — added testIntrospectToken

**Implementation:**
1. Added POST /oauth/introspect route registration (line ~1483)
2. Added OPTIONS /oauth/introspect CORS preflight handler
3. Implemented handleIntrospectRequest method that:
   - Parses client_id, token from form-encoded body
   - Validates client credentials
   - Calls [oauthProvider introspectToken:token completion:]
   - Returns RFC 7662 JSON: {active: bool, sub, scope, client_id, exp, iat, cnf}
4. Added test testIntrospectToken to verify endpoint returns {active: false} for unknown tokens

**Status:** [x] Complete

## 1.2 Blob Range Support on repo.getBlob

**Goal:** Extract Range-parsing helper and apply to both `sync.getBlob` and `repo.getBlob`

**Files modified:**
- `ATProtoPDS/Sources/Blob/BlobStorage.h` — added respondWithBlobData:filePath:totalLength:forRequest:response:error: method
- `ATProtoPDS/Sources/Blob/BlobStorage.m` — implemented Range parsing helpers and main response method
- `ATProtoPDS/Sources/Network/XrpcSyncMethods.m` — refactored to use shared BlobStorage method
- `ATProtoPDS/Sources/Network/XrpcRepoMethods.m` — updated repo.getBlob to use shared method
- `ATProtoPDS/Tests/Blob/BlobXrpcTests.m` — added Range tests for repo.getBlob

**Implementation:**
1. Added shared Range-parsing helpers to BlobStorage.m:
   - trimmedNonEmptyString()
   - parseUnsignedLongLongString()
   - parseByteRangeHeader()
   - blobFileChunkProducer()
2. Implemented respondWithBlobData:filePath:totalLength:forRequest:response:error: on BlobStorage
3. Refactored sync.getBlob handler to use shared method (eliminated ~100 lines of duplication)
4. Updated repo.getBlob handler to use shared method with full Range support
5. Added testRepoGetBlobRangeReturnsPartialContent and testRepoGetBlobRangeUnsatisfiableReturns416 tests

**Status:** [x] Complete

## Summary

Both Phase 1 tasks completed successfully:
- OAuth introspection endpoint wired up per RFC 7662
- Blob Range support extracted to shared helper and applied to both sync.getBlob and repo.getBlob
- Full test coverage added for new functionality

Ready for commit.
