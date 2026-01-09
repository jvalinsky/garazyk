# PDS Code Documentation Improvement Plan

## Executive Summary

After reviewing the ATProto PDS codebase (23,268 lines across 115 source files), a critical documentation gap was identified:

| Metric | Count | Percentage |
|--------|-------|------------|
| Header files | 47 | 100% |
| Files with ANY documentation | 5 | 10.6% |
| Files WITHOUT documentation | 42 | 89.4% |

**The majority (89%) of header files lack documentation.**

## Current Documentation State

### Files WITH Documentation (Good Examples)
1. **CID.h** - Excellent (`///` style comments)
2. **TID.h** - Good (timestamp ID utilities)
3. **DID.h** - Good (decentralized identifier support)
4. **BlobStorage.h** - Good (blob storage interface)
5. **FederationClient.h** - Basic (federation protocol)

### Files WITHOUT Documentation (Critical Gaps)

#### Core Controllers
- **PDSController.h/m** - Main PDS controller, 40+ methods
- **PDSController.h** - No class/method documentation
- **PDSController.m** - Minimal inline comments

#### Database Layer
- **PDSDatabase.h/m** - Database operations, 30+ methods
- **Schema.h/m** - Schema definitions, no docs
- **All model classes** - PDSDatabaseAccount, PDSDatabaseRepo, etc.

#### Repository Layer
- **MST.h/m** - Merkle Search Tree implementation
- **CAR.h/m** - Content Addressable Records format
- **CBOR.h/m** - CBOR encoding/decoding
- **RepoCommit.h/m** - Repository commit logic

#### Network Layer
- **HttpServer.h/m** - HTTP server implementation
- **HttpRequest.h/m** - HTTP request parsing
- **HttpResponse.h/m** - HTTP response building
- **XrpcHandler.h/m** - XRPC protocol handler
- **XrpcMethodRegistry.h/m** - Method registration
- **RateLimiter.h/m** - Rate limiting logic

#### Auth Layer
- **Session.h/m** - Session management
- **OAuth2.h/m** - OAuth 2.0 implementation
- **OAuthSession.h/m** - OAuth session handling
- **JWT.h/m** - JWT token handling
- **KeyManager.h/m** - Key management
- **DPoPUtil.h/m** - DPoP proof generation
- **Secp256k1.h/m** - Secp256k1 cryptography
- **PKCEUtil.h/m** - PKCE utilities

#### AppView Layer
- **ActorService.h/m** - Actor profile endpoints
- **FeedService.h/m** - Feed-related endpoints
- **NotificationService.h/m** - Push notifications

#### Sync Layer
- **Firehose.h/m** - Event streaming
- **WebSocketServer.h/m** - WebSocket handling
- **WebSocketConnection.h/m** - WebSocket connection
- **SubscribeReposHandler.h/m** - Repo subscription
- **EventFormatter.h/m** - Event formatting

#### Admin Tools
- **PDSMetrics.h/m** - Prometheus metrics (new, undocumented)
- **PDSAdminAuth.h/m** - Admin authentication (new, undocumented)
- **PDSAdminHandler.h/m** - Admin HTTP handlers (new, undocumented)
- **PDSCLIDefinitions.h** - CLI framework (new, undocumented)
- **All CLI command files** - New, undocumented

## Documentation Standards

### 1. Header File Documentation Template

```objc
/**
 * @file ClassName.h
 * @brief Brief description of the class/file purpose
 *
 * Detailed description of what this component does, its role in the system,
 * and any important usage notes or relationships to other components.
 *
 * @ingroup core-components
 */

// Or using Swift-style documentation comments:
/// ClassName handles...
@interface ClassName : NSObject

/// Short description of what the method does.
/// @param param1 Description of first parameter
/// @param param2 Description of second parameter
/// @return Description of return value
/// @error NSError code description for error conditions
- (nullable ReturnType)methodName:(Param1Type)param1
                         param2:(Param2Type)param2
                          error:(NSError **)error;

@end
```

### 2. Documentation Checklist by Component

#### A. Core Controllers (PDSController)
```
Required Documentation:
- @class description: Main PDS controller coordinating all operations
- @property descriptions: All 15+ properties
- @method descriptions: All 40+ methods including:
  * createSessionForIdentifier:password:handle:did:error:
  * createAccountForEmail:password:handle:did:error:
  * createRecordForDid:collection:record:rkey:error:
  * putRecordForDid:collection:rkey:record:error:
  * getRecordForDid:collection:rkey:error:
  * deleteRecordForDid:collection:rkey:error:
  * applyWrites:repo:validate:swapCommit:error:
  * describeRepo:error:
  * uploadBlob:mimeType:did:error:
  * getBlobWithCID:did:error:
```

#### B. Database Layer (PDSDatabase)
```
Required Documentation:
- @class description: SQLite database wrapper for PDS data
- Database schema overview (tables: accounts, repos, records, blocks, blobs)
- Transaction management documentation
- All CRUD operations for each entity type
- Error domain and error code documentation
```

#### C. Repository Layer (MST, CAR, CBOR)
```
Required Documentation:
- MST: Merkle Search Tree data structure for record indexing
  * Tree structure and operations
  * Entry format and key encoding
  * Hash computation
  
- CAR: Content Addressable Records format
  * Block structure
  * Root CID handling
  * Serialization format
  
- CBOR: Concise Binary Object Representation
  * Encoding/decoding methods
  * Type mappings
```

#### D. Auth Layer
```
Required Documentation:
- Session: User session management
  * Token types (access, refresh)
  * Token lifecycle
  * Expiration handling
  
- OAuth2: OAuth 2.0 authorization flow
  * Grant types supported
  * Token endpoints
  * Scope handling
  
- JWT: JWT token handling
  * Claims structure
  * Signing/verification
  
- DPoP: Demonstrating Proof-of-Possession
  * Proof generation
  * Key binding
```

#### E. Network Layer
```
Required Documentation:
- HttpServer: Built-in HTTP server
  * Request routing
  * Response building
  
- XrpcHandler: XRPC protocol implementation
  * Method invocation
  * Response formatting
  
- RateLimiter: Rate limiting
  * Rate limits by endpoint
  * Rate limit headers
```

## Implementation Phases

### Phase 1: Critical Core Components (Week 1)
**Priority: HIGH - These are the most used components**

1. **PDSController.h/m** (40 methods)
   - Estimated: 200 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

2. **PDSDatabase.h/m** (30+ methods)
   - Estimated: 150 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

3. **Schema.h/m** (tables and indexes)
   - Estimated: 100 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

### Phase 2: Repository Layer (Week 2)
**Priority: HIGH - Data structures critical for understanding**

1. **MST.h/m** - Merkle Search Tree
   - Estimated: 150 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

2. **CAR.h/m** - Content Addressable Records
   - Estimated: 100 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

3. **CBOR.h/m** - CBOR encoding
   - Estimated: 80 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

4. **RepoCommit.h/m** - Repository commits
   - Estimated: 100 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

### Phase 3: Network Layer (Week 3)
**Priority: MEDIUM - HTTP and XRPC handling**

1. **HttpServer.h/m**
   - Estimated: 100 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

2. **XrpcHandler.h/m**
   - Estimated: 120 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

3. **XrpcMethodRegistry.h/m**
   - Estimated: 80 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

4. **RateLimiter.h/m**
   - Estimated: 60 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

### Phase 4: Auth Layer (Week 4)
**Priority: MEDIUM - Security-critical code**

1. **Session.h/m**
   - Estimated: 100 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

2. **OAuth2.h/m**
   - Estimated: 150 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

3. **JWT.h/m**
   - Estimated: 80 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

4. **KeyManager.h/m**
   - Estimated: 80 lines of documentation
   - Owner: [Assign]
   - Status: [ ]

### Phase 5: Remaining Components (Week 5-6)
**Priority: LOW - Less frequently used**

1. **Sync Layer** (Firehose, WebSocket, SubscribeRepos)
2. **AppView Layer** (ActorService, FeedService, NotificationService)
3. **Admin Tools** (Metrics, AdminHandler, CLI)
4. **Test Files** (Documentation for test coverage)

## Documentation Style Guide

### 1. Use Apple's Documentation Tags

```objc
/**
 * @brief A short summary of what the method/class does.
 *
 * A more detailed description that can span multiple paragraphs.
 * Explain the purpose, behavior, and any important considerations.
 *
 * @param paramName Description of the parameter.
 * @return Description of the return value.
 * @retval errorCode Description of error condition and when it occurs.
 * @see RelatedClass
 * @see https://example.com/reference-link
 */
```

### 2. Property Documentation

```objc
/// The primary identifier for this entity (RFC 3986 format)
@property (nonatomic, copy, readonly) NSString *identifier;

/// Timestamp when this record was created, in seconds since Unix epoch
@property (nonatomic, assign, readonly) NSTimeInterval createdAt;
```

### 3. Enum Documentation

```objc
/// Error codes for database operations
typedef NS_ENUM(NSInteger, PDSDatabaseError) {
    /// Database file could not be opened
    PDSDatabaseErrorNotOpen = 1000,
    /// SQL query execution failed
    PDSDatabaseErrorQueryFailed = 1001,
    /// Database migration failed
    PDSDatabaseErrorMigrationFailed = 1002,
};
```

### 4. Protocol Documentation

```objc
/// Protocol for handling HTTP requests
/// Implement this protocol to add custom request handlers
@protocol HTTPRequestHandler <NSObject>

/// Handle an incoming HTTP request
/// @param request The HTTP request to process
/// @return The HTTP response to send back
- (HTTPResponse *)handleRequest:(HTTPRequest *)request;

@optional
/// Called before the server starts listening
- (void)serverWillStart;
/// Called after the server stops
- (void)serverDidStop;

@end
```

## Quality Checklist

Before marking documentation as complete, verify:

- [ ] File has `@file` and `@brief` documentation at top
- [ ] All public classes have class documentation
- [ ] All properties have single-line descriptions
- [ ] All methods have:
  - [ ] Brief description (`@brief` or `///`)
  - [ ] Parameter descriptions (`@param`)
  - [ ] Return value description (`@return`)
  - [ ] Error conditions (`@retval` or `@error`)
- [ ] Cross-references for related classes (`@see`)
- [ ] Links to external references (`@sa` or links)
- [ ] Examples where helpful
- [ ] Consistency with existing documentation (CID.h style)

## Documentation Tools

### 1. Generate Documentation

```bash
# Using HeaderDoc or Doxygen
headerdoc2html -o docs/ ATProtoPDS/ATProtoPDS/
```

### 2. Lint Documentation

```bash
# Create a script to check for undocumented public APIs
#!/bin/bash
for header in ATProtoPDS/**/*.h; do
    # Check for missing documentation
    grep -E "^\s*(extern|@interface|@protocol|@property)" "$header" | \
    while read line; do
        if ! grep -B1 "$line" "$header" | grep -q "^/\*\*\|^\s*///"; then
            echo "Missing docs: $header - $line"
        fi
    done
done
```

## File Template

Use this template for new header files:

```objc
/**
 * @file NewClass.h
 * @brief Brief description of this component.
 *
 * Detailed description explaining:
 * - What this component does
 * - How it fits into the overall architecture
 * - Key concepts users should understand
 * - Usage examples and patterns
 *
 * @ingroup module-name
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Class description for NewClass
@interface NewClass : NSObject

/// Property description
@property (nonatomic, copy, readonly) NSString *propertyName;

/// Method description
/// @param param Description of parameter
/// @return Description of return value
- (ReturnType)methodName:(ParamType)param;

@end

NS_ASSUME_NONNULL_END
```

## Progress Tracking

| Component | Files | Status | Lines Doc |
|-----------|-------|--------|-----------|
| Core Controllers | 1 | [ ] | 0/200 |
| Database Layer | 2 | [ ] | 0/250 |
| Repository Layer | 4 | [ ] | 0/430 |
| Network Layer | 4 | [ ] | 0/360 |
| Auth Layer | 7 | [ ] | 0/590 |
| AppView Layer | 3 | [ ] | 0/150 |
| Sync Layer | 5 | [ ] | 0/200 |
| Admin Tools | 4 | [ ] | 0/150 |
| **TOTAL** | **30** | **0%** | **0/2330** |

## Next Steps

1. Assign documentation owners for each phase
2. Create documentation linting script
3. Set up documentation generation pipeline
4. Review documentation for completeness
5. Merge documentation changes
