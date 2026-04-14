# Design Document: XRPC Registry Modularization

## Overview

This design refactors the 6,308-line XrpcMethodRegistry.m monolith into modular components organized by domain and shared functionality. The refactoring extracts three helper modules (authentication, identity resolution, error handling) and seven domain modules (server, repo, sync, identity, admin, label, app.bsky), reducing the main registry to a thin orchestration layer of ~200-300 lines.

The design preserves exact behavioral equivalence with the existing implementation - all 44 auth call sites, all endpoint handlers, and all error responses will produce identical results. The public API defined in XrpcMethodRegistry.h remains unchanged, ensuring zero impact on existing callers.

### Design Goals

1. **Eliminate Code Duplication**: Centralize repeated patterns (auth extraction, handle resolution, error construction) into reusable helper modules
2. **Improve Maintainability**: Organize 6,308 lines into focused modules of 200-1200 lines each, making the codebase navigable
3. **Enable Testability**: Isolate domain logic into modules that can be tested independently
4. **Preserve Behavior**: Maintain exact functional equivalence - all existing tests must pass without modification
5. **Support Incremental Migration**: Allow phased extraction (helpers first, then domains one at a time) with hybrid states

### Scope

**In Scope:**
- Extract XrpcAuthHelper, XrpcIdentityHelper, XrpcErrorHelper modules
- Extract 7 domain modules for XRPC namespaces
- Reduce XrpcMethodRegistry to orchestration-only code
- Maintain backward compatibility with existing API
- Preserve all existing test coverage

**Out of Scope:**
- Changing XRPC endpoint behavior or adding new endpoints
- Modifying the XrpcDispatcher registration mechanism
- Refactoring service layer dependencies (PDSAccountService, PDSRepositoryService, etc.)
- Performance optimization beyond what modularization naturally provides


## Architecture

### Current Architecture

```
XrpcMethodRegistry.m (6,308 lines)
├── Helper Functions (C functions)
│   ├── extractDIDFromAuthHeader (3 overloads, ~170 lines)
│   ├── authorizeAdminRequest (~50 lines)
│   ├── resolveDid (~80 lines)
│   ├── resolveAccountIdentifierToDid (~40 lines)
│   └── Error construction (inline, scattered)
├── Registration Functions (C functions)
│   ├── registerServerDescribeAndResolveLexiconMethods (~800 lines)
│   ├── registerServerAccountAndSessionMethods (~500 lines)
│   ├── registerRepoCoreMethods (~500 lines)
│   ├── registerSyncCoreMethods (~400 lines)
│   ├── registerPhase1IdentityAndAccountMethods (~1000 lines)
│   ├── registerAdminAccountMaintenanceMethods (~300 lines)
│   ├── registerAdminAccountAndInviteMethods (~350 lines)
│   ├── registerAdminModerationAndLabelMethods (~270 lines)
│   ├── registerTempUtilityMethods (~250 lines)
│   └── registerTempRevokeAccountCredentialsMethod (~80 lines)
└── Orchestration
    └── registerMethodsWithDispatcherUsingServices (~100 lines)
```

### Target Architecture

```
XrpcMethodRegistry.m (~250 lines)
├── Orchestration logic only
└── Delegates to modules

Helper Modules (Objective-C classes with C function wrappers)
├── XrpcAuthHelper (~200 lines)
│   ├── extractDIDFromAuthHeader (3 signatures)
│   ├── authorizeAdminRequest
│   └── JWT/DPoP verification logic
├── XrpcIdentityHelper (~150 lines)
│   ├── resolveHandleToDid
│   ├── resolveAccountIdentifierToDid
│   └── HandleResolver integration
└── XrpcErrorHelper (~100 lines)
    ├── authenticationError (401)
    ├── authorizationError (403)
    ├── validationError (400)
    ├── notFoundError (404)
    └── customError

Domain Modules (Objective-C classes)
├── XrpcServerMethods (~1200 lines)
│   └── com.atproto.server.* endpoints
├── XrpcRepoMethods (~800 lines)
│   └── com.atproto.repo.* endpoints
├── XrpcSyncMethods (~600 lines)
│   └── com.atproto.sync.* endpoints
├── XrpcIdentityMethods (~400 lines)
│   └── com.atproto.identity.* endpoints
├── XrpcAdminMethods (~400 lines)
│   └── com.atproto.admin.* endpoints
├── XrpcLabelMethods (~200 lines)
│   ├── com.atproto.label.* endpoints
│   └── com.atproto.temp.* endpoints
└── XrpcAppBskyMethods (~500 lines)
    └── app.bsky.* endpoints
```

### Module Dependencies

```
XrpcMethodRegistry
    ↓ (creates and uses)
Helper Modules (XrpcAuthHelper, XrpcIdentityHelper, XrpcErrorHelper)
    ↓ (used by)
Domain Modules (XrpcServerMethods, XrpcRepoMethods, etc.)
    ↓ (register with)
XrpcDispatcher
```

**Dependency Rules:**
- Helper modules have no dependencies on domain modules
- Domain modules depend on helper modules for shared functionality
- XrpcMethodRegistry orchestrates but doesn't implement endpoint logic
- All modules depend on service layer (PDSAccountService, PDSRepositoryService, etc.)


## Components and Interfaces

### Helper Modules

#### XrpcAuthHelper

**Purpose:** Centralize authentication logic for extracting and validating DIDs from Authorization headers with JWT and DPoP support.

**Interface:**
```objc
// XrpcAuthHelper.h
@interface XrpcAuthHelper : NSObject

// Extract DID from Authorization header (3 signatures for compatibility)
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request;

+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request
                                       response:(HttpResponse *)response;

+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                     controller:(PDSController *)controller
                                        request:(HttpRequest *)request
                                       response:(HttpResponse *)response;

// Admin authorization check
+ (BOOL)authorizeAdminRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end
```

**Implementation Strategy:**
- Move existing extractDIDFromAuthHeader C functions to class methods
- Preserve exact JWT verification logic (algorithm selection, issuer validation, DPoP binding)
- Maintain DPoP nonce challenge response behavior
- Keep takedown account rejection logic
- Provide C function wrappers for backward compatibility during migration

**Key Behaviors:**
- Bearer token: Extract JWT, verify signature, return DID from `sub` claim
- DPoP token: Verify DPoP proof, validate thumbprint binding, return DID
- Missing nonce: Set `DPoP-Nonce` and `WWW-Authenticate` headers, return nil
- Takedown account: Reject with nil return
- Invalid token: Return nil (optionally set error response if response object provided)


#### XrpcIdentityHelper

**Purpose:** Centralize handle-to-DID resolution logic for consistent identity resolution across all endpoints.

**Interface:**
```objc
// XrpcIdentityHelper.h
@interface XrpcIdentityHelper : NSObject

// Resolve handle to DID using HandleResolver
+ (nullable NSString *)resolveHandleToDid:(NSString *)handle
                           handleResolver:(HandleResolver *)resolver
                                    error:(NSError **)error;

// Resolve account identifier (handle or DID) to DID
+ (nullable NSString *)resolveAccountIdentifierToDid:(NSString *)identifier
                                      handleResolver:(HandleResolver *)resolver
                                    serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                                               error:(NSError **)error;

// Resolve DID document (PLC or local fallback)
+ (nullable NSDictionary *)resolveDid:(NSString *)did
                     serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                        configuration:(PDSConfiguration *)configuration
                                error:(NSError **)error;

@end
```

**Implementation Strategy:**
- Extract resolveAccountIdentifierToDid C function to class method
- Extract resolveDid C function to class method
- Add resolveHandleToDid wrapper for common handle resolution pattern
- Use HandleResolver service for DNS/HTTPS resolution
- Maintain PLC directory resolution with local fallback

**Key Behaviors:**
- Handle resolution: Use HandleResolver service, return DID or error
- Account identifier: Detect if input is DID (starts with "did:") or handle, resolve accordingly
- DID resolution: For did:plc, query PLC directory; for did:web, construct from issuer; fallback to local account data


#### XrpcErrorHelper

**Purpose:** Standardize XRPC error response construction for consistent error formats across all endpoints.

**Interface:**
```objc
// XrpcErrorHelper.h
@interface XrpcErrorHelper : NSObject

// Standard error responses
+ (void)setAuthenticationError:(HttpResponse *)response
                       message:(nullable NSString *)message;

+ (void)setAuthorizationError:(HttpResponse *)response
                      message:(nullable NSString *)message;

+ (void)setValidationError:(HttpResponse *)response
                   message:(nullable NSString *)message;

+ (void)setNotFoundError:(HttpResponse *)response
                 message:(nullable NSString *)message;

+ (void)setInternalServerError:(HttpResponse *)response
                       message:(nullable NSString *)message;

// Custom error with code
+ (void)setError:(HttpResponse *)response
      statusCode:(HttpStatusCode)statusCode
       errorCode:(NSString *)errorCode
         message:(NSString *)message;

// Convenience for common patterns
+ (void)setInvalidRequestError:(HttpResponse *)response
                       message:(NSString *)message;

+ (void)setAccountNotFoundError:(HttpResponse *)response
                            did:(NSString *)did;

@end
```

**Implementation Strategy:**
- Analyze existing error response patterns in XrpcMethodRegistry
- Standardize on JSON format: `{"error": "<code>", "message": "<message>"}`
- Map HTTP status codes to standard error codes (401→AuthRequired, 403→Forbidden, etc.)
- Provide convenience methods for common error scenarios
- Ensure exact format compatibility with existing responses

**Key Behaviors:**
- Authentication error (401): `{"error": "AuthRequired", "message": "..."}`
- Authorization error (403): `{"error": "Forbidden", "message": "..."}`
- Validation error (400): `{"error": "InvalidRequest", "message": "..."}`
- Not found error (404): `{"error": "NotFound", "message": "..."}`
- Custom error: Caller-specified status, code, and message


### Domain Modules

All domain modules follow a consistent pattern:

**Common Interface Pattern:**
```objc
@interface XrpcDomainMethods : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                    authHelper:(XrpcAuthHelper *)authHelper
                identityHelper:(XrpcIdentityHelper *)identityHelper
                   errorHelper:(XrpcErrorHelper *)errorHelper
                accountService:(id<PDSAccountService>)accountService
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                     jwtMinter:(JWTMinter *)jwtMinter
                 configuration:(PDSConfiguration *)configuration
                 emailProvider:(id<PDSEmailProvider>)emailProvider;

@end
```

**Design Rationale:**
- **Class methods vs instances**: Use class methods with explicit parameter passing to avoid hidden state and make dependencies clear
- **Dependency injection**: Pass all required services as parameters rather than storing in instance variables
- **Helper integration**: Accept helper module instances for auth, identity, and error handling
- **Service access**: Receive all necessary services (account, record, blob, repository, admin, databases, JWT, config, email)

#### XrpcServerMethods

**Responsibility:** Register all `com.atproto.server.*` endpoint handlers

**Endpoints (~20 endpoints, ~1200 lines):**
- `com.atproto.server.describeServer`
- `com.atproto.server.createAccount`
- `com.atproto.server.createSession`
- `com.atproto.server.refreshSession`
- `com.atproto.server.getSession`
- `com.atproto.server.deleteSession`
- `com.atproto.server.revokeAppPassword`
- `com.atproto.server.createAppPassword`
- `com.atproto.server.listAppPasswords`
- `com.atproto.server.createInviteCode`
- `com.atproto.server.createInviteCodes`
- `com.atproto.server.getAccountInviteCodes`
- `com.atproto.server.requestAccountDelete`
- `com.atproto.server.deleteAccount`
- `com.atproto.server.updateEmail`
- `com.atproto.server.requestEmailUpdate`
- `com.atproto.server.confirmEmail`
- `com.atproto.server.requestEmailConfirmation`
- `com.atproto.server.getServiceAuth`
- `com.atproto.server.reserveSigningKey`
- `com.atproto.server.activateAccount`
- `com.atproto.server.deactivateAccount`

**Key Patterns:**
- Session endpoints: Use XrpcAuthHelper for JWT validation
- Account creation: Complex validation, invite code checks, repository initialization
- Email operations: Integration with PDSEmailProvider
- Service auth: JWT minting for service-to-service authentication


#### XrpcRepoMethods

**Responsibility:** Register all `com.atproto.repo.*` endpoint handlers

**Endpoints (~12 endpoints, ~800 lines):**
- `com.atproto.repo.createRecord`
- `com.atproto.repo.putRecord`
- `com.atproto.repo.deleteRecord`
- `com.atproto.repo.getRecord`
- `com.atproto.repo.listRecords`
- `com.atproto.repo.describeRepo`
- `com.atproto.repo.uploadBlob`
- `com.atproto.repo.applyWrites`
- `com.atproto.repo.importRepo`

**Key Patterns:**
- All endpoints require authentication via XrpcAuthHelper
- Record operations: Validate collection, rkey, and record data
- Blob uploads: Integration with BlobStorage service
- Repository writes: Use PDSRepositoryService for MST operations
- Apply writes: Batch operation support with transaction semantics

#### XrpcSyncMethods

**Responsibility:** Register all `com.atproto.sync.*` endpoint handlers

**Endpoints (~8 endpoints, ~600 lines):**
- `com.atproto.sync.getBlob`
- `com.atproto.sync.getBlocks`
- `com.atproto.sync.getCheckout`
- `com.atproto.sync.getCommitPath`
- `com.atproto.sync.getHead`
- `com.atproto.sync.getLatestCommit`
- `com.atproto.sync.getRecord`
- `com.atproto.sync.getRepo`
- `com.atproto.sync.listBlobs`
- `com.atproto.sync.listRepos`
- `com.atproto.sync.subscribeRepos` (WebSocket)

**Key Patterns:**
- Most endpoints are public (no auth required) for federation
- CAR file generation for repository export
- WebSocket support for subscribeRepos
- Integration with PDSRepositoryService for commit history

#### XrpcIdentityMethods

**Responsibility:** Register all `com.atproto.identity.*` endpoint handlers

**Endpoints (~6 endpoints, ~400 lines):**
- `com.atproto.identity.resolveHandle`
- `com.atproto.identity.updateHandle`
- `com.atproto.identity.getRecommendedDidCredentials`
- `com.atproto.identity.requestPlcOperationSignature`
- `com.atproto.identity.signPlcOperation`
- `com.atproto.identity.submitPlcOperation`
- `com.atproto.identity.resolveDid`

**Key Patterns:**
- Handle resolution: Use XrpcIdentityHelper
- PLC operations: Integration with PLCRotationKeyManager and DIDPLCResolver
- Handle updates: Require authentication and validation
- DID resolution: Support did:plc and did:web


#### XrpcAdminMethods

**Responsibility:** Register all `com.atproto.admin.*` endpoint handlers

**Endpoints (~10 endpoints, ~400 lines):**
- `com.atproto.admin.disableAccountInvites`
- `com.atproto.admin.enableAccountInvites`
- `com.atproto.admin.getAccountInfo`
- `com.atproto.admin.getAccountInfos`
- `com.atproto.admin.getInviteCodes`
- `com.atproto.admin.getSubjectStatus`
- `com.atproto.admin.searchAccounts`
- `com.atproto.admin.updateAccountEmail`
- `com.atproto.admin.updateAccountHandle`
- `com.atproto.admin.updateAccountPassword`
- `com.atproto.admin.updateSubjectStatus`
- `com.atproto.admin.sendEmail`

**Key Patterns:**
- All endpoints require admin authorization via XrpcAuthHelper.authorizeAdminRequest
- Account management: Direct database access via PDSServiceDatabases
- Subject status: Takedown and suspension management
- Email operations: Integration with PDSEmailProvider

#### XrpcLabelMethods

**Responsibility:** Register all `com.atproto.label.*` and `com.atproto.temp.*` endpoint handlers

**Endpoints (~4 endpoints, ~200 lines):**
- `com.atproto.label.queryLabels`
- `com.atproto.label.subscribeLabels` (WebSocket)
- `com.atproto.temp.fetchLabels` (deprecated)
- `com.atproto.temp.requestPhoneVerification`

**Key Patterns:**
- Label queries: Database lookups for moderation labels
- Deprecation warnings: temp.fetchLabels includes sunset headers
- Phone verification: Integration with PDSPhoneVerificationProvider
- WebSocket support for label subscriptions

#### XrpcAppBskyMethods

**Responsibility:** Register all `app.bsky.*` endpoint handlers

**Endpoints (~15 endpoints, ~500 lines):**
- `app.bsky.actor.getProfile`
- `app.bsky.actor.getProfiles`
- `app.bsky.actor.searchActors`
- `app.bsky.actor.searchActorsTypeahead`
- `app.bsky.feed.getAuthorFeed`
- `app.bsky.feed.getTimeline`
- `app.bsky.feed.getActorLikes`
- `app.bsky.feed.getPostThread`
- `app.bsky.feed.getPosts`
- `app.bsky.graph.getFollowers`
- `app.bsky.graph.getFollows`
- `app.bsky.notification.listNotifications`
- `app.bsky.notification.getUnreadCount`
- `app.bsky.notification.updateSeen`

**Key Patterns:**
- AppView integration: Use ActorService, FeedService, NotificationService
- Optional authentication: Some endpoints work with or without auth
- Pagination: Cursor-based pagination for list endpoints
- Social graph: Follower/following queries


### XrpcMethodRegistry (Orchestrator)

**Responsibility:** Thin orchestration layer that instantiates modules and delegates registration

**Reduced Interface:**
```objc
// XrpcMethodRegistry.h (unchanged)
@interface XrpcMethodRegistry : NSObject

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller;

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application;

// Legacy auth helper (delegates to XrpcAuthHelper)
+ (nullable NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                                      jwtMinter:(JWTMinter *)jwtMinter
                                adminController:(id<PDSAdminController>)adminController
                                        request:(HttpRequest *)request;

+ (nullable NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                           error:(NSError **)error;

@end
```

**Implementation (~250 lines):**
```objc
// XrpcMethodRegistry.m
@implementation XrpcMethodRegistry

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application {
    // Extract services from application
    id<PDSAccountService> accountService = application.accountService;
    PDSRecordService *recordService = application.recordService;
    // ... extract all services
    
    // Instantiate helper modules (or use class methods directly)
    // No instantiation needed for class-method-only helpers
    
    // Register in order (some endpoints depend on others being registered first)
    [XrpcServerMethods registerWithDispatcher:dispatcher
                                   authHelper:nil  // Use class methods
                               identityHelper:nil
                                  errorHelper:nil
                               accountService:accountService
                                recordService:recordService
                                  blobService:blobService
                            repositoryService:repositoryService
                              adminController:adminController
                             serviceDatabases:serviceDatabases
                             userDatabasePool:userDatabasePool
                                    jwtMinter:jwtMinter
                                configuration:configuration
                                emailProvider:emailProvider];
    
    [XrpcRepoMethods registerWithDispatcher:dispatcher ...];
    [XrpcSyncMethods registerWithDispatcher:dispatcher ...];
    [XrpcIdentityMethods registerWithDispatcher:dispatcher ...];
    [XrpcAdminMethods registerWithDispatcher:dispatcher ...];
    [XrpcLabelMethods registerWithDispatcher:dispatcher ...];
    [XrpcAppBskyMethods registerWithDispatcher:dispatcher ...];
    
    // Install proxy interceptor
    installXrpcProxyInterceptor(dispatcher, configuration);
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
    // Delegate to application-based registration
    [self registerMethodsWithDispatcher:dispatcher
                            application:controller.application];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request {
    // Delegate to XrpcAuthHelper
    return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                         jwtMinter:jwtMinter
                                   adminController:adminController
                                           request:request];
}

+ (NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                  error:(NSError **)error {
    // Keep existing implementation (not moved to helper)
    // ... existing code ...
}

@end
```

**Key Behaviors:**
- Maintain exact public API from XrpcMethodRegistry.h
- Extract services from PDSApplication or PDSController
- Call domain module registration methods in correct order
- Delegate legacy extractDIDFromAuthHeader to XrpcAuthHelper
- Keep publicKeyBytesFromMultibase implementation (not moved)


## Data Models

This refactoring does not introduce new data models. All existing data structures remain unchanged:

**Service Layer Models (unchanged):**
- `PDSAccountService`: Account creation, session management
- `PDSRecordService`: Record CRUD operations
- `PDSBlobService`: Blob storage and retrieval
- `PDSRepositoryService`: MST operations, commit management
- `PDSServiceDatabases`: Service-level database access
- `PDSDatabasePool`: User-level database pool
- `JWTMinter`: JWT token generation
- `PDSConfiguration`: Server configuration
- `id<PDSAdminController>`: Admin operations interface
- `id<PDSEmailProvider>`: Email sending interface

**Request/Response Models (unchanged):**
- `HttpRequest`: HTTP request with headers, query params, body
- `HttpResponse`: HTTP response with status, headers, body
- `XrpcDispatcher`: XRPC method registration and dispatch

**Authentication Models (unchanged):**
- `JWT`: JWT token parsing and payload access
- `JWTVerifier`: JWT signature verification
- `OAuth2DPoPProof`: DPoP proof verification
- `PDSNonceManager`: DPoP nonce generation

**Identity Models (unchanged):**
- `HandleResolver`: Handle-to-DID resolution
- `DIDPLCResolver`: PLC directory DID resolution
- `PLCRotationKeyManager`: PLC operation signing

**Module Organization:**
The refactoring organizes existing code into modules but does not change data structures or introduce new models. All service dependencies are passed as parameters to module registration methods.


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property Reflection

Before defining properties, we analyze the testable acceptance criteria to eliminate redundancy:

**Identified Redundancies:**
1. Requirements 1.7, 2.5, 3.7, 4.5, 5.4, 6.4, 7.5, 8.5, 9.5, 10.4, 12.3, 13.3 all express the same metamorphic property: "refactored code produces identical behavior to original code for all inputs"
   - **Consolidation:** Combine into a single comprehensive behavioral equivalence property
   
2. Requirements 12.2 and 13.3 both test that existing callers work unchanged
   - **Consolidation:** 12.2 (compilation compatibility) is subsumed by 13.3 (test suite passes)
   
3. Requirements 4.2, 4.3, 4.4 (and similar for other domain modules) test implementation details (which helper is used)
   - **Elimination:** These are not functional requirements; behavioral equivalence (4.5) already validates correctness
   
4. Requirements 11.2, 11.3, 11.4 test internal orchestration details
   - **Elimination:** These are implementation details; 11.5 (correct registration order) and behavioral equivalence validate correctness

**Remaining Unique Properties:**
- Authentication extraction correctness (1.2, 1.3, 1.5)
- Identity resolution correctness (2.2, 2.3)
- Error response format correctness (3.6)
- Behavioral equivalence across all endpoints (consolidated metamorphic property)
- Lexicon validation preservation (15.2, 15.4)
- Hybrid state correctness during migration (14.3)


### Property 1: JWT Authentication Extraction

*For any* valid JWT access token with a DID in the `sub` claim, when XrpcAuthHelper extracts the DID from an Authorization header, the returned DID SHALL match the `sub` claim value.

**Validates: Requirements 1.2**

### Property 2: DPoP Authentication Extraction

*For any* valid DPoP-bound access token with matching DPoP proof, when XrpcAuthHelper extracts the DID from an Authorization header with DPoP proof, the returned DID SHALL match the token's `sub` claim and the DPoP thumbprint SHALL match the token's `cnf.jkt` claim.

**Validates: Requirements 1.3**

### Property 3: Authentication Failure Returns Nil

*For any* invalid Authorization header (malformed JWT, expired token, invalid signature, or missing DPoP proof), when XrpcAuthHelper attempts to extract a DID, it SHALL return nil.

**Validates: Requirements 1.5**

### Property 4: Handle Resolution Round Trip

*For any* valid handle that resolves to a DID, when XrpcIdentityHelper resolves the handle to a DID and then resolves that DID back to its handle (via DID document `alsoKnownAs`), the original handle SHALL be present in the `alsoKnownAs` list.

**Validates: Requirements 2.2**

### Property 5: Invalid Handle Resolution Fails

*For any* invalid handle (malformed, non-existent, or resolution timeout), when XrpcIdentityHelper attempts to resolve the handle, it SHALL return an error with appropriate error code.

**Validates: Requirements 2.3**

### Property 6: Error Response Format Consistency

*For any* error response constructed by XrpcErrorHelper with a custom error code and message, the response body SHALL contain a JSON object with `error` and `message` fields matching the provided values.

**Validates: Requirements 3.6**

### Property 7: Behavioral Equivalence (Metamorphic Property)

*For any* XRPC request (method, headers, query params, body) that was valid before refactoring, when the refactored XrpcMethodRegistry processes the request, the response (status code, headers, body) SHALL be identical to the response from the original implementation.

**Validates: Requirements 1.7, 2.5, 3.7, 4.5, 5.4, 6.4, 7.5, 8.5, 9.5, 10.4, 12.2, 12.3, 13.3**

**Testing Strategy:** This property is validated by running the existing test suite (1012 tests) against the refactored code. All tests must pass with identical results.

### Property 8: Lexicon Validation Preservation

*For any* XRPC method call with a request body, when the refactored system validates the request against loaded lexicon schemas, the validation result (pass/fail) SHALL be identical to the original implementation's validation result.

**Validates: Requirements 15.2, 15.4**

### Property 9: Hybrid State Correctness

*For any* hybrid configuration where some endpoints use refactored modules and others use legacy code, when an XRPC request is processed, the response SHALL be identical to a fully-legacy or fully-refactored implementation.

**Validates: Requirements 14.3**

**Testing Strategy:** During incremental migration, run integration tests after each module extraction to verify hybrid state correctness.


## Error Handling

### Error Handling Strategy

The refactoring preserves all existing error handling behavior. Error handling is centralized in XrpcErrorHelper but maintains exact compatibility with current error responses.

### Error Categories

**Authentication Errors (401):**
- Missing Authorization header
- Invalid JWT signature
- Expired JWT token
- DPoP proof verification failure
- Missing DPoP nonce
- Takedown account rejection

**Authorization Errors (403):**
- Admin endpoint accessed without admin privileges
- Account lacks permission for requested operation
- Invite code required but not provided

**Validation Errors (400):**
- Missing required parameters
- Invalid parameter format (malformed DID, handle, etc.)
- Invalid record data (schema validation failure)
- Invalid blob content type or size

**Not Found Errors (404):**
- Account not found
- Record not found
- DID not found
- Handle resolution failure

**Internal Server Errors (500):**
- Database connection failure
- Service unavailable
- Unexpected exceptions

### Error Response Format

All errors follow the standard XRPC error format:
```json
{
  "error": "<ErrorCode>",
  "message": "<Human-readable description>"
}
```

**Standard Error Codes:**
- `AuthRequired`: Authentication required but not provided
- `Forbidden`: Authenticated but not authorized
- `InvalidRequest`: Request validation failed
- `NotFound`: Requested resource not found
- `InternalServerError`: Server-side error

### DPoP Nonce Challenge

When DPoP verification fails due to missing or invalid nonce:
```
HTTP/1.1 401 Unauthorized
DPoP-Nonce: <generated-nonce>
WWW-Authenticate: DPoP error="use_dpop_nonce"
Content-Type: application/json

{
  "error": "use_dpop_nonce",
  "message": "DPoP nonce required"
}
```

### Error Handling in Modules

**Helper Modules:**
- XrpcAuthHelper: Returns nil on auth failure, optionally sets error response if response object provided
- XrpcIdentityHelper: Returns nil and sets NSError on resolution failure
- XrpcErrorHelper: Sets response status and body, never throws exceptions

**Domain Modules:**
- Use XrpcErrorHelper for all error responses
- Validate inputs before processing
- Handle service layer errors gracefully
- Log errors for debugging (using PDS_LOG_* macros)

### Backward Compatibility

All error responses maintain exact format compatibility with the original implementation to ensure clients receive expected error structures.


## Testing Strategy

### Dual Testing Approach

This refactoring requires both unit tests and property-based tests to ensure correctness:

**Unit Tests:**
- Verify specific examples and edge cases
- Test module interfaces and integration points
- Validate error handling for known failure scenarios
- Test hybrid states during incremental migration

**Property-Based Tests:**
- Verify universal properties across all inputs
- Test behavioral equivalence between original and refactored code
- Validate authentication extraction with random valid/invalid tokens
- Test handle resolution with generated handles

### Property-Based Testing Configuration

**Library:** Use existing property-based testing library for Objective-C (if available) or implement minimal property testing harness

**Configuration:**
- Minimum 100 iterations per property test
- Each property test references its design document property
- Tag format: `// Feature: xrpc-registry-modularization, Property N: <property text>`

**Property Test Coverage:**

1. **Property 1 (JWT Authentication):**
   - Generate random valid JWTs with different DIDs
   - Verify extracted DID matches `sub` claim
   - Test with various signing algorithms (ES256, ES256K, RS256)

2. **Property 2 (DPoP Authentication):**
   - Generate random valid DPoP-bound tokens
   - Generate matching DPoP proofs
   - Verify DID extraction and thumbprint validation

3. **Property 3 (Authentication Failure):**
   - Generate random invalid tokens (expired, wrong signature, malformed)
   - Verify nil return for all invalid inputs

4. **Property 4 (Handle Resolution Round Trip):**
   - Generate random valid handles
   - Resolve to DID, then resolve DID document
   - Verify handle in `alsoKnownAs`

5. **Property 5 (Invalid Handle Resolution):**
   - Generate random invalid handles
   - Verify error return for all invalid inputs

6. **Property 6 (Error Response Format):**
   - Generate random error codes and messages
   - Verify JSON response contains correct fields

7. **Property 7 (Behavioral Equivalence):**
   - Run existing test suite (1012 tests) against refactored code
   - All tests must pass with identical results
   - This is the primary validation of correctness

8. **Property 8 (Lexicon Validation):**
   - Generate random valid/invalid request bodies
   - Verify validation results match original implementation

9. **Property 9 (Hybrid State):**
   - Test various hybrid configurations during migration
   - Verify responses match fully-migrated implementation

### Unit Test Coverage

**Helper Module Tests:**

1. **XrpcAuthHelper Tests:**
   - Valid Bearer token extraction
   - Valid DPoP token extraction
   - Missing Authorization header
   - Malformed JWT
   - Expired token
   - Invalid signature
   - DPoP nonce challenge
   - Takedown account rejection
   - All three method signature variants

2. **XrpcIdentityHelper Tests:**
   - Valid handle resolution
   - Invalid handle format
   - Non-existent handle
   - DID resolution (did:plc, did:web)
   - Account identifier resolution (handle vs DID)
   - PLC directory fallback to local data

3. **XrpcErrorHelper Tests:**
   - Authentication error (401)
   - Authorization error (403)
   - Validation error (400)
   - Not found error (404)
   - Internal server error (500)
   - Custom error with code
   - JSON format validation

**Domain Module Tests:**

For each domain module (Server, Repo, Sync, Identity, Admin, Label, AppBsky):
- Endpoint registration completeness
- Authentication enforcement
- Error response format
- Integration with helper modules
- Service layer interaction

**Integration Tests:**

1. **End-to-End Request Flow:**
   - Full request processing through refactored modules
   - Authentication → endpoint handler → response
   - Error paths (auth failure, validation failure, not found)

2. **Hybrid State Tests:**
   - Mix of refactored and legacy endpoints
   - Verify no interference between modules
   - Test during incremental migration

3. **Lexicon Loading:**
   - Verify lexicon files load correctly
   - Test schema validation against loaded lexicons
   - Verify describeServer returns correct lexicon info

### Regression Testing

**Existing Test Suite:**
- Run all 1012 existing tests against refactored code
- Zero failures required for acceptance
- Any test failure indicates behavioral divergence

**Build Verification:**
- `xcodebuild -scheme AllTests build` must succeed
- `xcodebuild -scheme ATProtoPDS-CLI build` must succeed
- `./build/tests/AllTests` must pass with 0 failures

### Migration Testing Strategy

**Phase 1: Helper Module Extraction**
1. Extract XrpcAuthHelper
2. Run full test suite → must pass
3. Extract XrpcIdentityHelper
4. Run full test suite → must pass
5. Extract XrpcErrorHelper
6. Run full test suite → must pass

**Phase 2: Domain Module Extraction (one at a time)**
1. Extract XrpcServerMethods
2. Run full test suite → must pass
3. Extract XrpcRepoMethods
4. Run full test suite → must pass
5. Continue for each domain module
6. Final verification: all tests pass, all endpoints functional

### Test Automation

All tests must be automated and run in CI:
- GitHub Actions workflow runs full test suite on every PR
- Property-based tests run with 100+ iterations
- Build verification for macOS and Linux
- No manual testing required for acceptance


## Implementation Plan

### Migration Strategy

The refactoring follows a phased approach to minimize risk and enable continuous validation:

**Phase 1: Helper Module Extraction (No Behavioral Change)**
1. Create XrpcAuthHelper class with extractDIDFromAuthHeader methods
2. Move auth logic from XrpcMethodRegistry to XrpcAuthHelper
3. Update XrpcMethodRegistry to delegate to XrpcAuthHelper
4. Run full test suite → verify 0 failures
5. Create XrpcIdentityHelper class with resolution methods
6. Move identity logic to XrpcIdentityHelper
7. Run full test suite → verify 0 failures
8. Create XrpcErrorHelper class with error construction methods
9. Standardize error responses using XrpcErrorHelper
10. Run full test suite → verify 0 failures

**Phase 2: Domain Module Extraction (One Module at a Time)**
1. Create XrpcServerMethods class
2. Move com.atproto.server.* endpoints to XrpcServerMethods
3. Update XrpcMethodRegistry to call XrpcServerMethods.register
4. Run full test suite → verify 0 failures
5. Repeat for each domain module:
   - XrpcRepoMethods
   - XrpcSyncMethods
   - XrpcIdentityMethods
   - XrpcAdminMethods
   - XrpcLabelMethods
   - XrpcAppBskyMethods
6. After each module: run tests, verify 0 failures

**Phase 3: Registry Simplification**
1. Remove all extracted code from XrpcMethodRegistry.m
2. Verify XrpcMethodRegistry is ~250 lines (orchestration only)
3. Run full test suite → verify 0 failures
4. Update documentation and comments

### File Organization

**New Files:**
```
Garazyk/Sources/Network/
├── XrpcAuthHelper.h
├── XrpcAuthHelper.m
├── XrpcIdentityHelper.h
├── XrpcIdentityHelper.m
├── XrpcErrorHelper.h
├── XrpcErrorHelper.m
├── XrpcServerMethods.h
├── XrpcServerMethods.m
├── XrpcRepoMethods.h
├── XrpcRepoMethods.m
├── XrpcSyncMethods.h
├── XrpcSyncMethods.m
├── XrpcIdentityMethods.h
├── XrpcIdentityMethods.m
├── XrpcAdminMethods.h
├── XrpcAdminMethods.m
├── XrpcLabelMethods.h
├── XrpcLabelMethods.m
├── XrpcAppBskyMethods.h
└── XrpcAppBskyMethods.m
```

**Modified Files:**
```
Garazyk/Sources/Network/
├── XrpcMethodRegistry.h (minimal changes: forward declarations)
└── XrpcMethodRegistry.m (reduced from 6,308 to ~250 lines)
```

### Build System Updates

**CMakeLists.txt:**
Add new source files to ATProtoPDS target:
```cmake
set(ATPROTOPDS_SOURCES
    # ... existing sources ...
    Sources/Network/XrpcAuthHelper.m
    Sources/Network/XrpcIdentityHelper.m
    Sources/Network/XrpcErrorHelper.m
    Sources/Network/XrpcServerMethods.m
    Sources/Network/XrpcRepoMethods.m
    Sources/Network/XrpcSyncMethods.m
    Sources/Network/XrpcIdentityMethods.m
    Sources/Network/XrpcAdminMethods.m
    Sources/Network/XrpcLabelMethods.m
    Sources/Network/XrpcAppBskyMethods.m
)
```

**project.yml (XcodeGen):**
No changes required - XcodeGen automatically picks up new files in Sources/

### Code Review Checklist

For each module extraction:
- [ ] All endpoints registered correctly
- [ ] Authentication logic preserved exactly
- [ ] Error responses match original format
- [ ] Service dependencies passed correctly
- [ ] Helper modules used consistently
- [ ] No code duplication introduced
- [ ] Comments and documentation updated
- [ ] Full test suite passes (0 failures)
- [ ] Build succeeds on macOS and Linux
- [ ] Module size within target range

### Rollback Strategy

If any phase fails:
1. Revert the specific module extraction commit
2. Investigate test failures
3. Fix issues in isolation
4. Re-attempt extraction with fixes

The phased approach ensures that each step is independently reversible without affecting completed phases.

### Success Criteria

The refactoring is complete when:
1. All 20 new files created (10 modules × 2 files each)
2. XrpcMethodRegistry.m reduced to ~250 lines
3. All 1012 existing tests pass with 0 failures
4. Build succeeds on macOS and Linux
5. No behavioral changes detected in integration testing
6. Code review approved
7. Documentation updated


## Appendix: Code Examples

### Example: XrpcAuthHelper Implementation

```objc
// XrpcAuthHelper.m
#import "Network/XrpcAuthHelper.h"
#import "Auth/JWT.h"
#import "Auth/JWTVerifier.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/CryptoUtils.h"
#import "App/PDSConfiguration.h"
#import "Admin/PDSAdminController.h"
#import "Debug/PDSLogger.h"

@implementation XrpcAuthHelper

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:jwtMinter
                         adminController:adminController
                                 request:request
                                response:nil];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
    if (!authHeader) return nil;
    
    // Parse Bearer or DPoP token
    NSString *token = nil;
    BOOL isDPoP = NO;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
        isDPoP = YES;
    } else {
        return nil;
    }
    
    // DPoP verification
    NSString *dpopThumbprint = nil;
    if (isDPoP) {
        NSString *dpopProof = [request headerForKey:@"DPoP"];
        if (!dpopProof) {
            PDS_LOG_AUTH_WARN(@"Missing DPoP header for DPoP authorization");
            return nil;
        }
        
        // Construct DPoP URL
        NSURL *dpopURL = [self constructDPoPURLFromRequest:request];
        if (!dpopURL) {
            PDS_LOG_AUTH_WARN(@"Unable to construct DPoP URL");
            return nil;
        }
        
        // Verify DPoP proof
        NSError *dpopError = nil;
        if (![OAuth2DPoPProof verifyProof:dpopProof
                                   method:request.methodString
                                      url:dpopURL
                                    nonce:nil
                             requireNonce:YES
                            outThumbprint:&dpopThumbprint
                                    error:&dpopError]) {
            if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
                if (response) {
                    [self setDPoPNonceChallengeResponse:response];
                }
                return nil;
            }
            PDS_LOG_AUTH_WARN(@"Invalid DPoP proof: %@", dpopError.localizedDescription);
            return nil;
        }
    }
    
    // Parse and verify JWT
    NSError *parseError = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&parseError];
    if (!jwt) {
        PDS_LOG_HTTP_WARN(@"Failed to parse JWT token");
        return nil;
    }
    
    // Verify JWT signature
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.keyManager = jwtMinter.keyManager;
    verifier.publicKey = jwtMinter.publicKey;
    verifier.expectedIssuer = jwtMinter.issuer;
    verifier.expectedAudience = jwtMinter.issuer;
    verifier.allowedAlgorithms = [self allowedAlgorithmsForMinter:jwtMinter];
    
    NSError *verifyError = nil;
    if (![verifier verifyJWT:jwt error:&verifyError]) {
        PDS_LOG_AUTH_WARN(@"JWT verification failed: %@", verifyError.localizedDescription);
        return nil;
    }
    
    // Enforce DPoP binding
    NSString *tokenJkt = jwt.payload.cnf[@"jkt"];
    if (isDPoP) {
        if (!tokenJkt || ![CryptoUtils constantTimeCompare:tokenJkt to:dpopThumbprint]) {
            PDS_LOG_AUTH_WARN(@"DPoP thumbprint mismatch");
            return nil;
        }
    } else if (tokenJkt) {
        PDS_LOG_AUTH_WARN(@"DPoP-bound token sent as Bearer");
        return nil;
    }
    
    // Extract DID from subject
    NSString *did = jwt.payload.sub;
    if (!did || ![did hasPrefix:@"did:"]) {
        PDS_LOG_AUTH_WARN(@"Invalid DID in JWT subject");
        return nil;
    }
    
    // Check takedown status
    NSError *takedownError = nil;
    if ([adminController isAccountTakedownActive:did error:&takedownError]) {
        PDS_LOG_AUTH_WARN(@"Rejected request for suspended account %@", did);
        return nil;
    }
    
    return did;
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                            controller:(PDSController *)controller
                               request:(HttpRequest *)request
                              response:(HttpResponse *)response {
    return [self extractDIDFromAuthHeader:authHeader
                               jwtMinter:controller.jwtMinter
                         adminController:controller.adminController
                                 request:request
                                response:response];
}

+ (BOOL)authorizeAdminRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *did = [self extractDIDFromAuthHeader:authHeader
                                        jwtMinter:jwtMinter
                                  adminController:adminController
                                          request:request];
    if (!did) {
        if (response.statusCode == HttpStatusOK) {
            response.statusCode = HttpStatusUnauthorized;
            [response setJsonBody:@{@"error": @"AuthRequired",
                                   @"message": @"Admin authentication required"}];
        }
        return NO;
    }
    
    PDSAdminAuth *adminAuth = [PDSAdminAuth sharedAuth];
    if (![adminAuth isAuthenticatedWithRequest:request.headers]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"Forbidden",
                               @"message": @"Admin privileges required"}];
        return NO;
    }
    
    return YES;
}

#pragma mark - Private Helpers

+ (NSURL *)constructDPoPURLFromRequest:(HttpRequest *)request {
    NSString *host = [request headerForKey:@"Host"] ?: @"";
    NSString *scheme = [self schemeFromRequest:request];
    
    NSMutableString *urlString = [NSMutableString string];
    if (host.length > 0) {
        [urlString appendFormat:@"%@://%@%@", scheme, host, request.path ?: @"/"];
        if (request.queryString.length > 0) {
            [urlString appendFormat:@"?%@", request.queryString];
        }
    }
    
    return urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
}

+ (NSString *)schemeFromRequest:(HttpRequest *)request {
    NSString *forwardedProto = [request headerForKey:@"X-Forwarded-Proto"];
    if (forwardedProto.length > 0) {
        return forwardedProto;
    }
    
    NSString *host = [[request headerForKey:@"Host"] lowercaseString];
    if ([host containsString:@"localhost"] ||
        [host hasPrefix:@"127.0.0.1"] ||
        [host hasPrefix:@"::1"]) {
        return @"http";
    }
    
    return @"https";
}

+ (void)setDPoPNonceChallengeResponse:(HttpResponse *)response {
    response.statusCode = HttpStatusUnauthorized;
    NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
    if (nonce.length > 0) {
        [response setHeader:nonce forKey:@"DPoP-Nonce"];
    }
    [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
    [response setJsonBody:@{@"error": @"use_dpop_nonce",
                           @"message": @"DPoP nonce required"}];
}

+ (NSArray<NSString *> *)allowedAlgorithmsForMinter:(JWTMinter *)minter {
    if (!minter) return nil;
    
    NSMutableOrderedSet<NSString *> *algorithms = [NSMutableOrderedSet orderedSet];
    NSString *configured = [[minter.signingAlgorithm
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                            uppercaseString];
    if (configured.length > 0) {
        [algorithms addObject:configured];
    }
    
    if (minter.keyManager) {
        [algorithms addObjectsFromArray:@[@"ES256", @"RS256"]];
    }
    
    if (algorithms.count == 0 && minter.publicKey) {
        [algorithms addObject:@"ES256K"];
    }
    
    return algorithms.count > 0 ? algorithms.array : nil;
}

@end
```

### Example: Domain Module Registration

```objc
// XrpcServerMethods.m
#import "Network/XrpcServerMethods.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcErrorHelper.h"

@implementation XrpcServerMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                    authHelper:(XrpcAuthHelper *)authHelper
                identityHelper:(XrpcIdentityHelper *)identityHelper
                   errorHelper:(XrpcErrorHelper *)errorHelper
                accountService:(id<PDSAccountService>)accountService
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                     jwtMinter:(JWTMinter *)jwtMinter
                 configuration:(PDSConfiguration *)configuration
                 emailProvider:(id<PDSEmailProvider>)emailProvider {
    
    // Register com.atproto.server.describeServer
    [dispatcher registerComAtprotoServerDescribeServer:^(HttpRequest *request,
                                                         HttpResponse *response) {
        // Implementation using helper modules
        // ... endpoint logic ...
    }];
    
    // Register com.atproto.server.createSession
    [dispatcher registerComAtprotoServerCreateSession:^(HttpRequest *request,
                                                        HttpResponse *response) {
        // Extract credentials from request
        NSDictionary *body = [request jsonBody];
        NSString *identifier = body[@"identifier"];
        NSString *password = body[@"password"];
        
        if (!identifier || !password) {
            [XrpcErrorHelper setValidationError:response
                                        message:@"Missing identifier or password"];
            return;
        }
        
        // Resolve identifier to DID
        NSError *error = nil;
        NSString *did = [XrpcIdentityHelper resolveAccountIdentifierToDid:identifier
                                                           handleResolver:configuration.handleResolver
                                                         serviceDatabases:serviceDatabases
                                                                    error:&error];
        if (!did) {
            [XrpcErrorHelper setAuthenticationError:response
                                            message:@"Invalid credentials"];
            return;
        }
        
        // Authenticate and create session
        // ... session creation logic ...
    }];
    
    // Register remaining com.atproto.server.* endpoints
    // ...
}

@end
```

### Example: Simplified Registry Orchestration

```objc
// XrpcMethodRegistry.m (after refactoring)
#import "Network/XrpcMethodRegistry.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcServerMethods.h"
#import "Network/XrpcRepoMethods.h"
#import "Network/XrpcSyncMethods.h"
#import "Network/XrpcIdentityMethods.h"
#import "Network/XrpcAdminMethods.h"
#import "Network/XrpcLabelMethods.h"
#import "Network/XrpcAppBskyMethods.h"

@implementation XrpcMethodRegistry

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                          application:(PDSApplication *)application {
    // Extract services
    id<PDSAccountService> accountService = application.accountService;
    PDSRecordService *recordService = application.recordService;
    PDSBlobService *blobService = application.blobService;
    PDSRepositoryService *repositoryService = application.repositoryService;
    id<PDSAdminController> adminController = application.adminController;
    PDSServiceDatabases *serviceDatabases = application.serviceDatabases;
    PDSDatabasePool *userDatabasePool = application.userDatabasePool;
    JWTMinter *jwtMinter = application.jwtMinter;
    PDSConfiguration *configuration = application.configuration;
    id<PDSEmailProvider> emailProvider = application.emailProvider;
    
    // Register domain modules (order matters for some endpoints)
    [XrpcServerMethods registerWithDispatcher:dispatcher
                                   authHelper:nil
                               identityHelper:nil
                                  errorHelper:nil
                               accountService:accountService
                                recordService:recordService
                                  blobService:blobService
                            repositoryService:repositoryService
                              adminController:adminController
                             serviceDatabases:serviceDatabases
                             userDatabasePool:userDatabasePool
                                    jwtMinter:jwtMinter
                                configuration:configuration
                                emailProvider:emailProvider];
    
    [XrpcRepoMethods registerWithDispatcher:dispatcher /* ... */];
    [XrpcSyncMethods registerWithDispatcher:dispatcher /* ... */];
    [XrpcIdentityMethods registerWithDispatcher:dispatcher /* ... */];
    [XrpcAdminMethods registerWithDispatcher:dispatcher /* ... */];
    [XrpcLabelMethods registerWithDispatcher:dispatcher /* ... */];
    [XrpcAppBskyMethods registerWithDispatcher:dispatcher /* ... */];
    
    // Install proxy interceptor
    installXrpcProxyInterceptor(dispatcher, configuration);
}

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
    [self registerMethodsWithDispatcher:dispatcher
                            application:controller.application];
}

+ (NSString *)extractDIDFromAuthHeader:(NSString *)authHeader
                             jwtMinter:(JWTMinter *)jwtMinter
                       adminController:(id<PDSAdminController>)adminController
                               request:(HttpRequest *)request {
    return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                         jwtMinter:jwtMinter
                                   adminController:adminController
                                           request:request];
}

+ (NSData *)publicKeyBytesFromMultibase:(NSString *)multibase
                                  error:(NSError **)error {
    // Keep existing implementation (not moved to helper)
    // ... existing code ...
}

@end
```

