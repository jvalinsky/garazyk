# Implementation Plan: XRPC Registry Modularization

## Overview

This plan refactors the 6,308-line XrpcMethodRegistry.m monolith into modular components. The approach extracts three helper modules (authentication, identity resolution, error handling) and seven domain modules (server, repo, sync, identity, admin, label, app.bsky), reducing the main registry to ~250 lines of orchestration code.

The refactoring preserves exact behavioral equivalence - all 1012 existing tests must pass without modification. Each task builds incrementally, with validation checkpoints to catch regressions early.

## Tasks

- [x] 1. Extract XrpcAuthHelper module
  - [x] 1.1 Create XrpcAuthHelper class with authentication methods
    - Create Garazyk/Sources/Network/XrpcAuthHelper.h with interface
    - Create Garazyk/Sources/Network/XrpcAuthHelper.m with implementation
    - Implement extractDIDFromAuthHeader (3 method signatures)
    - Implement authorizeAdminRequest method
    - Move JWT verification logic from XrpcMethodRegistry
    - Move DPoP proof verification logic from XrpcMethodRegistry
    - Preserve exact DPoP nonce challenge behavior
    - Preserve takedown account rejection logic
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_
  
  - [x] 1.2 Write property test for JWT authentication extraction
    - **Property 1: JWT Authentication Extraction**
    - **Validates: Requirements 1.2**
    - Generate random valid JWTs with different DIDs
    - Verify extracted DID matches `sub` claim
    - Test with ES256, ES256K, RS256 algorithms
  
  - [x] 1.3 Write property test for DPoP authentication extraction
    - **Property 2: DPoP Authentication Extraction**
    - **Validates: Requirements 1.3**
    - Generate random valid DPoP-bound tokens
    - Generate matching DPoP proofs
    - Verify DID extraction and thumbprint validation
  
  - [x] 1.4 Write property test for authentication failure
    - **Property 3: Authentication Failure Returns Nil**
    - **Validates: Requirements 1.5**
    - Generate random invalid tokens (expired, wrong signature, malformed)
    - Verify nil return for all invalid inputs
  
  - [x] 1.5 Update XrpcMethodRegistry to delegate to XrpcAuthHelper
    - Replace all 44 extractDIDFromAuthHeader call sites
    - Delegate to XrpcAuthHelper class methods
    - Maintain backward compatibility for public API
    - _Requirements: 1.7_
  
  - [x] 1.6 Update CMakeLists.txt to include XrpcAuthHelper sources
    - Add Sources/Network/XrpcAuthHelper.m to ATPROTOPDS_SOURCES
    - _Requirements: 1.1_
  
  - [x] 1.7 Verify all tests pass after XrpcAuthHelper extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures (all 1012 tests pass)
    - _Requirements: 13.1, 13.3_

- [x] 2. Extract XrpcIdentityHelper module
  - [x] 2.1 Create XrpcIdentityHelper class with resolution methods
    - Create Garazyk/Sources/Network/XrpcIdentityHelper.h with interface
    - Create Garazyk/Sources/Network/XrpcIdentityHelper.m with implementation
    - Implement resolveHandleToDid method
    - Implement resolveAccountIdentifierToDid method
    - Implement resolveDid method
    - Move handle resolution logic from XrpcMethodRegistry
    - Integrate with HandleResolver service
    - Maintain PLC directory resolution with local fallback
    - _Requirements: 2.1, 2.2, 2.3, 2.4_
  
  - [x] 2.2 Write property test for handle resolution round trip
    - **Property 4: Handle Resolution Round Trip**
    - **Validates: Requirements 2.2**
    - Generate random valid handles
    - Resolve to DID, then resolve DID document
    - Verify handle in `alsoKnownAs`
  
  - [x] 2.3 Write property test for invalid handle resolution
    - **Property 5: Invalid Handle Resolution Fails**
    - **Validates: Requirements 2.3**
    - Generate random invalid handles
    - Verify error return for all invalid inputs
  
  - [x] 2.4 Update XrpcMethodRegistry to use XrpcIdentityHelper
    - Replace inline handle resolution with XrpcIdentityHelper calls
    - Update all endpoints that perform handle resolution
    - _Requirements: 2.5_
  
  - [x] 2.5 Update CMakeLists.txt to include XrpcIdentityHelper sources
    - Add Sources/Network/XrpcIdentityHelper.m to ATPROTOPDS_SOURCES
    - _Requirements: 2.1_
  
  - [x] 2.6 Verify all tests pass after XrpcIdentityHelper extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 3. Extract XrpcErrorHelper module
  - [x] 3.1 Create XrpcErrorHelper class with error construction methods
    - Create Garazyk/Sources/Network/XrpcErrorHelper.h with interface
    - Create Garazyk/Sources/Network/XrpcErrorHelper.m with implementation
    - Implement setAuthenticationError (401)
    - Implement setAuthorizationError (403)
    - Implement setValidationError (400)
    - Implement setNotFoundError (404)
    - Implement setInternalServerError (500)
    - Implement setError with custom code
    - Implement convenience methods (setInvalidRequestError, setAccountNotFoundError)
    - Standardize JSON format: `{"error": "<code>", "message": "<message>"}`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_
  
  - [x] 3.2 Write property test for error response format
    - **Property 6: Error Response Format Consistency**
    - **Validates: Requirements 3.6**
    - Generate random error codes and messages
    - Verify JSON response contains correct fields
  
  - [x] 3.3 Update XrpcMethodRegistry to use XrpcErrorHelper
    - Replace inline error construction with XrpcErrorHelper calls
    - Standardize all error responses across endpoints
    - _Requirements: 3.7_
  
  - [x] 3.4 Update CMakeLists.txt to include XrpcErrorHelper sources
    - Add Sources/Network/XrpcErrorHelper.m to ATPROTOPDS_SOURCES
    - _Requirements: 3.1_
  
  - [x] 3.5 Verify all tests pass after XrpcErrorHelper extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Extract XrpcServerMethods domain module
  - [x] 5.1 Create XrpcServerMethods class
    - Create Garazyk/Sources/Network/XrpcServerMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcServerMethods.m with implementation
    - Define registerWithDispatcher class method with all service parameters
    - _Requirements: 4.1_
  
  - [x] 5.2 Move com.atproto.server.* endpoint handlers to XrpcServerMethods
    - Move describeServer endpoint
    - Move createAccount endpoint
    - Move createSession, refreshSession, getSession, deleteSession endpoints
    - Move revokeAppPassword, createAppPassword, listAppPasswords endpoints
    - Move createInviteCode, createInviteCodes, getAccountInviteCodes endpoints
    - Move requestAccountDelete, deleteAccount endpoints
    - Move updateEmail, requestEmailUpdate, confirmEmail, requestEmailConfirmation endpoints
    - Move getServiceAuth endpoint
    - Move reserveSigningKey, activateAccount, deactivateAccount endpoints
    - Use XrpcAuthHelper for authentication
    - Use XrpcIdentityHelper for handle resolution
    - Use XrpcErrorHelper for error responses
    - Target ~1200 lines or less
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.6_
  
  - [x] 5.3 Update XrpcMethodRegistry to call XrpcServerMethods.register
    - Remove moved endpoint code from XrpcMethodRegistry
    - Add XrpcServerMethods.registerWithDispatcher call
    - Pass all required services as parameters
    - _Requirements: 4.5, 11.4, 11.5_
  
  - [x] 5.4 Update CMakeLists.txt to include XrpcServerMethods sources
    - Add Sources/Network/XrpcServerMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 4.1_
  
  - [x] 5.5 Verify all tests pass after XrpcServerMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 6. Extract XrpcRepoMethods domain module
  - [x] 6.1 Create XrpcRepoMethods class
    - Create Garazyk/Sources/Network/XrpcRepoMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcRepoMethods.m with implementation
    - Define registerWithDispatcher class method
    - _Requirements: 5.1_
  
  - [x] 6.2 Move com.atproto.repo.* endpoint handlers to XrpcRepoMethods
    - Move createRecord, putRecord, deleteRecord endpoints
    - Move getRecord, listRecords, describeRepo endpoints
    - Move uploadBlob endpoint
    - Move applyWrites, importRepo endpoints
    - Use XrpcAuthHelper for authentication
    - Use XrpcErrorHelper for error responses
    - Target ~800 lines or less
    - _Requirements: 5.1, 5.2, 5.3, 5.5_
  
  - [x] 6.3 Update XrpcMethodRegistry to call XrpcRepoMethods.register
    - Remove moved endpoint code
    - Add XrpcRepoMethods.registerWithDispatcher call
    - _Requirements: 5.4, 11.4, 11.5_
  
  - [x] 6.4 Update CMakeLists.txt to include XrpcRepoMethods sources
    - Add Sources/Network/XrpcRepoMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 5.1_
  
  - [x] 6.5 Verify all tests pass after XrpcRepoMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [ ] 7. Extract XrpcSyncMethods domain module
  - [x] 7.1 Create XrpcSyncMethods class
    - Create Garazyk/Sources/Network/XrpcSyncMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcSyncMethods.m with implementation
    - Define registerWithDispatcher class method
    - _Requirements: 6.1_
  
  - [x] 7.2 Move com.atproto.sync.* endpoint handlers to XrpcSyncMethods
    - Move getBlob, getBlocks, getCheckout endpoints
    - Move getCommitPath, getHead, getLatestCommit endpoints
    - Move getRecord, getRepo endpoints
    - Move listBlobs, listRepos endpoints
    - Move subscribeRepos WebSocket endpoint
    - Use XrpcAuthHelper for authentication where required
    - Use XrpcErrorHelper for error responses
    - Target ~600 lines or less
    - _Requirements: 6.1, 6.2, 6.3, 6.5_
  
  - [x] 7.3 Update XrpcMethodRegistry to call XrpcSyncMethods.register
    - Remove moved endpoint code
    - Add XrpcSyncMethods.registerWithDispatcher call
    - _Requirements: 6.4, 11.4, 11.5_
  
  - [x] 7.4 Update CMakeLists.txt to include XrpcSyncMethods sources
    - Add Sources/Network/XrpcSyncMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 6.1_
  
  - [x] 7.5 Verify all tests pass after XrpcSyncMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 8. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Extract XrpcIdentityMethods domain module
  - [x] 9.1 Create XrpcIdentityMethods class
    - Create Garazyk/Sources/Network/XrpcIdentityMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcIdentityMethods.m with implementation
    - Define registerWithDispatcher class method
    - _Requirements: 7.1_
  
  - [x] 9.2 Move com.atproto.identity.* endpoint handlers to XrpcIdentityMethods
    - Move resolveHandle, updateHandle endpoints
    - Move getRecommendedDidCredentials endpoint
    - Move requestPlcOperationSignature, signPlcOperation, submitPlcOperation endpoints
    - Move resolveDid endpoint
    - Use XrpcAuthHelper for authentication
    - Use XrpcIdentityHelper for handle resolution
    - Use XrpcErrorHelper for error responses
    - Target ~400 lines or less
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.6_
  
  - [x] 9.3 Update XrpcMethodRegistry to call XrpcIdentityMethods.register
    - Remove moved endpoint code
    - Add XrpcIdentityMethods.registerWithDispatcher call
    - _Requirements: 7.5, 11.4, 11.5_
  
  - [x] 9.4 Update CMakeLists.txt to include XrpcIdentityMethods sources
    - Add Sources/Network/XrpcIdentityMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 7.1_
  
  - [x] 9.5 Verify all tests pass after XrpcIdentityMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 10. Extract XrpcAdminMethods domain module
  - [x] 10.1 Create XrpcAdminMethods class
    - Create Garazyk/Sources/Network/XrpcAdminMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcAdminMethods.m with implementation
    - Define registerWithDispatcher class method
    - _Requirements: 8.1_
  
  - [x] 10.2 Move com.atproto.admin.* endpoint handlers to XrpcAdminMethods
    - Move disableAccountInvites, enableAccountInvites endpoints
    - Move getAccountInfo, getAccountInfos endpoints
    - Move getInviteCodes, getSubjectStatus endpoints
    - Move searchAccounts endpoint
    - Move updateAccountEmail, updateAccountHandle, updateAccountPassword endpoints
    - Move updateSubjectStatus endpoint
    - Move sendEmail endpoint
    - Use XrpcAuthHelper for authentication and admin authorization
    - Use XrpcErrorHelper for error responses
    - Target ~400 lines or less
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.6_
  
  - [x] 10.3 Update XrpcMethodRegistry to call XrpcAdminMethods.register
    - Remove moved endpoint code
    - Add XrpcAdminMethods.registerWithDispatcher call
    - _Requirements: 8.5, 11.4, 11.5_
  
  - [x] 10.4 Update CMakeLists.txt to include XrpcAdminMethods sources
    - Add Sources/Network/XrpcAdminMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 8.1_
  
  - [x] 10.5 Verify all tests pass after XrpcAdminMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 11. Extract XrpcLabelMethods domain module
  - [x] 11.1 Create XrpcLabelMethods class
    - Create Garazyk/Sources/Network/XrpcLabelMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcLabelMethods.m with implementation
    - Define registerWithDispatcher class method
    - _Requirements: 9.1_
  
  - [x] 11.2 Move com.atproto.label.* and com.atproto.temp.* endpoint handlers to XrpcLabelMethods
    - Move queryLabels endpoint
    - Move subscribeLabels WebSocket endpoint
    - Move temp.fetchLabels endpoint (with deprecation warnings)
    - Move temp.requestPhoneVerification endpoint
    - Use XrpcAuthHelper for authentication where required
    - Use XrpcErrorHelper for error responses
    - Target ~200 lines or less
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.6_
  
  - [x] 11.3 Update XrpcMethodRegistry to call XrpcLabelMethods.register
    - Remove moved endpoint code
    - Add XrpcLabelMethods.registerWithDispatcher call
    - _Requirements: 9.5, 11.4, 11.5_
  
  - [x] 11.4 Update CMakeLists.txt to include XrpcLabelMethods sources
    - Add Sources/Network/XrpcLabelMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 9.1_
  
  - [x] 11.5 Verify all tests pass after XrpcLabelMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 12. Extract XrpcAppBskyMethods domain module
  - [x] 12.1 Create XrpcAppBskyMethods class
    - Create Garazyk/Sources/Network/XrpcAppBskyMethods.h with interface
    - Create Garazyk/Sources/Network/XrpcAppBskyMethods.m with implementation
    - Define registerWithDispatcher class method
    - _Requirements: 10.1_
  
  - [x] 12.2 Move app.bsky.* endpoint handlers to XrpcAppBskyMethods
    - Move actor.getProfile, actor.getProfiles endpoints
    - Move actor.searchActors, actor.searchActorsTypeahead endpoints
    - Move feed.getAuthorFeed, feed.getTimeline, feed.getActorLikes endpoints
    - Move feed.getPostThread, feed.getPosts endpoints
    - Move graph.getFollowers, graph.getFollows endpoints
    - Move notification.listNotifications, notification.getUnreadCount, notification.updateSeen endpoints
    - Use XrpcAuthHelper for authentication where required
    - Use XrpcErrorHelper for error responses
    - Target ~500 lines or less
    - _Requirements: 10.1, 10.2, 10.3, 10.5_
  
  - [x] 12.3 Update XrpcMethodRegistry to call XrpcAppBskyMethods.register
    - Remove moved endpoint code
    - Add XrpcAppBskyMethods.registerWithDispatcher call
    - _Requirements: 10.4, 11.4, 11.5_
  
  - [x] 12.4 Update CMakeLists.txt to include XrpcAppBskyMethods sources
    - Add Sources/Network/XrpcAppBskyMethods.m to ATPROTOPDS_SOURCES
    - _Requirements: 10.1_
  
  - [x] 12.5 Verify all tests pass after XrpcAppBskyMethods extraction
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - _Requirements: 13.1, 13.3_

- [x] 13. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Simplify XrpcMethodRegistry to orchestration-only
  - [x] 14.1 Remove all extracted code from XrpcMethodRegistry.m
    - Remove all moved helper functions
    - Remove all moved endpoint registration functions
    - Keep only orchestration logic
    - Keep publicKeyBytesFromMultibase implementation (not moved)
    - Target ~250 lines
    - _Requirements: 11.1, 11.6_
  
  - [x] 14.2 Update XrpcMethodRegistry.h with forward declarations if needed
    - Add forward declarations for helper modules if required
    - Maintain unchanged public interface
    - _Requirements: 11.1, 12.1, 12.4_
  
  - [x] 14.3 Verify registerMethodsWithDispatcherUsingServices orchestration
    - Verify all domain modules called in correct order
    - Verify all services passed correctly
    - Verify installXrpcProxyInterceptor still called
    - _Requirements: 11.5, 15.3_
  
  - [x] 14.4 Verify backward compatibility
    - Verify public API unchanged
    - Verify extractDIDFromAuthHeader delegates to XrpcAuthHelper
    - Verify publicKeyBytesFromMultibase still works
    - _Requirements: 12.1, 12.2_
  
  - [x] 14.5 Verify all tests pass after registry simplification
    - Run `xcodebuild -scheme AllTests build`
    - Run `./build/tests/AllTests`
    - Verify 0 failures
    - Run `xcodebuild -scheme ATProtoPDS-CLI build`
    - Verify CLI build succeeds
    - _Requirements: 13.1, 13.2, 13.3_

- [x] 15. Add module documentation
  - [x] 15.1 Document XrpcAuthHelper responsibilities
    - Add header comments describing authentication responsibilities
    - Document JWT and DPoP verification behavior
    - Document DPoP nonce challenge flow
    - _Requirements: 16.1_
  
  - [x] 15.2 Document XrpcIdentityHelper responsibilities
    - Add header comments describing identity resolution responsibilities
    - Document handle resolution behavior
    - Document DID resolution (PLC and local fallback)
    - _Requirements: 16.2_
  
  - [x] 15.3 Document XrpcErrorHelper responsibilities
    - Add header comments describing error response construction
    - Document standard error codes and formats
    - _Requirements: 16.3_
  
  - [x] 15.4 Document domain module responsibilities
    - Add header comments to each domain module
    - Document which XRPC namespaces each module handles
    - List all endpoints registered by each module
    - _Requirements: 16.4_
  
  - [x] 15.5 Document XrpcMethodRegistry orchestration flow
    - Update header comments describing orchestration responsibilities
    - Document module registration order
    - Document service dependency injection pattern
    - _Requirements: 16.5_

- [x] 16. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional property-based tests and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after major phases
- All tests must pass (0 failures) after each module extraction
- Build must succeed for both AllTests and ATProtoPDS-CLI targets
- Property tests validate universal correctness properties
- The existing test suite (1012 tests) validates behavioral equivalence (Property 7)
