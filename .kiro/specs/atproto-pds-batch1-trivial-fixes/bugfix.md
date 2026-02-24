# Bugfix Requirements Document

## Introduction

This bugfix addresses four trivial spec compliance and code quality issues in the ATProto PDS implementation that can be resolved quickly (<1 hour total):

1. **sync.getHead returns block data instead of CID** - PDSRepositoryService.getRepoRoot returns block content bytes instead of CID bytes, causing sync.getHead to base32-encode the wrong data
2. **Debug fprintf calls in production code** - Multiple fprintf(stderr, ...) debug statements remain in XrpcMethodRegistry.m, polluting stderr in production
3. **Placeholder public key in synthetic DID documents** - resolveDid helper function returns "zQ3sh..." placeholder instead of real verification method
4. **repo.importRepo unimplemented** - Endpoint returns 501 stub (correct behavior until implementation, but should be documented)

These issues affect spec compliance, interoperability with crawlers, code quality, and debugging clarity.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN PDSRepositoryService.getRepoRoot is called for a DID THEN the system returns block data (the content of the root block) instead of the root CID bytes

1.2 WHEN com.atproto.sync.getHead is called THEN the system base32-encodes block data instead of CID bytes, returning an invalid CID string that breaks crawlers

1.3 WHEN resolveDid function is called THEN the system writes debug messages to stderr: "[resolveDid] Resolving DID: ...", "[resolveDid] Account not found...", "[resolveDid] Found account handle: ..."

1.4 WHEN com.atproto.identity.resolveDid handler is invoked THEN the system writes "[resolveDid] Handler invoked" to stderr

1.5 WHEN com.atproto.sync.getBlocks handler is invoked THEN the system writes "[getBlocks] Handler invoked" to stderr

1.6 WHEN resolveDid helper function constructs a synthetic DID document THEN the system includes a placeholder verificationMethod with publicKeyMultibase "zQ3sh..." instead of the account's actual public key

1.7 WHEN a client calls com.atproto.repo.importRepo with valid CAR data THEN the system returns HTTP 501 with error "NotImplemented" without attempting import

### Expected Behavior (Correct)

2.1 WHEN PDSRepositoryService.getRepoRoot is called for a DID THEN the system SHALL return the root CID bytes (not block data)

2.2 WHEN com.atproto.sync.getHead is called THEN the system SHALL base32-encode the CID bytes and return a valid CID string per the lexicon spec (format: "cid")

2.3 WHEN resolveDid function is called THEN the system SHALL NOT write any debug messages to stderr

2.4 WHEN com.atproto.identity.resolveDid handler is invoked THEN the system SHALL NOT write debug messages to stderr

2.5 WHEN com.atproto.sync.getBlocks handler is invoked THEN the system SHALL NOT write debug messages to stderr

2.6 WHEN resolveDid helper function constructs a synthetic DID document THEN the system SHALL omit the verificationMethod array entirely (synthetic documents should not include placeholder keys)

2.7 WHEN a client calls com.atproto.repo.importRepo with valid CAR data THEN the system SHALL return HTTP 501 with error "NotImplemented" (unchanged - proper stub behavior until full implementation)

### Unchanged Behavior (Regression Prevention)

3.1 WHEN com.atproto.sync.getHead is called with a valid DID THEN the system SHALL CONTINUE TO return HTTP 200 with JSON response containing "root" field

3.2 WHEN com.atproto.sync.getHead is called with an invalid/missing DID THEN the system SHALL CONTINUE TO return HTTP 404 with error "RepoNotFound"

3.3 WHEN PDSRepositoryService methods other than getRepoRoot access block data THEN the system SHALL CONTINUE TO function correctly

3.4 WHEN com.atproto.identity.resolveDid is called with a valid DID THEN the system SHALL CONTINUE TO return a DID document with correct structure (id, alsoKnownAs, service fields)

3.5 WHEN resolveDid helper function is called for an existing account THEN the system SHALL CONTINUE TO return the account's DID, handle, and didDoc dictionary

3.6 WHEN any XRPC handler processes requests THEN the system SHALL CONTINUE TO use PDS_LOG_* macros for structured logging (not fprintf)

3.7 WHEN com.atproto.repo.importRepo is called THEN the system SHALL CONTINUE TO require authentication and return 501 until full implementation is added

3.8 WHEN com.atproto.sync.getBlocks processes requests THEN the system SHALL CONTINUE TO function correctly after debug output removal
