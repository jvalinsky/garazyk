---
title: PDSController Refactor Plan
---

# PDSController Refactor Plan

## Executive Summary

The `PDSController` class (~800 lines) has grown into a monolithic "god object" that handles too many responsibilities. This plan outlines a phased refactoring approach to decompose it into domain-specific components while maintaining backward compatibility and minimizing disruption to existing tests.

## Current State Analysis

### PDSController Responsibilities (Too Many)

| Category | Methods | Lines (approx) |
|----------|---------|----------------|
| **Initialization & Lifecycle** | `init`, `startServer`, `stopServer` | ~200 |
| **Account Operations** | 7 methods (5 current + 2 legacy) | ~50 |
| **Repository Operations** | 6 methods (3 current + 3 legacy) | ~80 |
| **Record Operations** | 10 methods (4 current + 6 legacy) | ~100 |
| **Blob Operations** | 6 methods (2 current + 4 legacy) | ~40 |
| **Admin Operations** | 4 methods | ~50 |
| **Moderation Operations** | 2 methods (stubs) | ~10 |
| **Labeling Operations** | 2 methods | ~40 |
| **Health & Metrics** | 3 methods | ~20 |
| **HTTP Server Setup** | inline in `startServerWithError:` | ~150 |

### Existing Service Layer

Good news: Service classes already exist but aren't fully utilized:

```

ATProtoPDS/Sources/App/Services/
├── PDSAccountService.h/m      ✅ Well-defined protocol
├── PDSBlobService.h/m         ✅ Good abstraction
├── PDSRecordService.h/m       ✅ Good abstraction  
├── PDSRepositoryService.h/m   ✅ Good abstraction
```

### Problems

1. **PDSController is a facade that mostly delegates** - but also has business logic mixed in
2. **Legacy methods duplicate functionality** - confusing API surface
3. **HTTP routing is inline** - hard to test and modify
4. **Service initialization is tightly coupled** - makes testing difficult
5. **Admin/Moderation/Labeling are stubs** - incomplete implementation
6. **Single 800+ line file** - cognitive overload

---

## Target Architecture

```

┌─────────────────────────────────────────────────────────────────────┐
│                         PDSApplication                               │
│  (Lightweight coordinator - replaces PDSController as entry point)  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
       ▼                       ▼                       ▼
┌──────────────┐      ┌──────────────┐      ┌──────────────────┐
│  PDSServer   │      │PDSServiceMgr │      │PDSConfiguration  │
│  (HTTP+WS)   │      │(DI Container)│      │   (Settings)     │
└──────┬───────┘      └──────┬───────┘      └──────────────────┘
       │                     │
       │    ┌────────────────┼────────────────┐
       │    │                │                │
       ▼    ▼                ▼                ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ XrpcController │  │AdminController │  │ModerationCtrl  │
│  (XRPC routes) │  │ (Admin ops)    │  │ (Moderation)   │
└───────┬────────┘  └───────┬────────┘  └───────┬────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│PDSAccountSvc │   │PDSRecordSvc  │   │PDSBlobSvc    │
│  (accounts)  │   │  (records)   │   │  (blobs)     │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                            ▼
                   ┌──────────────────┐
                   │ PDSDatabasePool  │
                   │ PDSServiceDBs    │
                   └──────────────────┘
```

---

## Refactoring Phases

### Phase 1: Extract HTTP Server Setup (Low Risk)

**Goal**: Move HTTP server configuration out of `PDSController`

**New Files**:
- `ATProtoPDS/Sources/Network/PDSServerConfiguration.h/m`

**Changes**:

```objc
// PDSServerConfiguration.h
@interface PDSServerConfiguration : NSObject

@property (nonatomic, assign) NSUInteger httpPort;
@property (nonatomic, assign) NSUInteger wsPort;
@property (nonatomic, copy) NSString *issuer;

- (instancetype)initWithDefaults;
+ (instancetype)configurationFromEnvironment;

@end
```

```objc
// PDSHttpServerBuilder.h
@interface PDSHttpServerBuilder : NSObject

- (instancetype)initWithConfiguration:(PDSServerConfiguration *)config;
- (HttpServer *)buildWithController:(PDSController *)controller error:(NSError **)error;

@end
```

**Migration**:
1. Extract the ~150 lines of route setup from `startServerWithError:`
2. Create `PDSHttpServerBuilder` that takes controller and configures routes
3. Update `PDSController.startServerWithError:` to use builder

**Tests**: Existing tests should pass unchanged.

---

### Phase 2: Create Admin Controller (Medium Risk)

**Goal**: Extract admin, moderation, and labeling operations

**New Files**:
- `ATProtoPDS/Sources/Admin/PDSAdminController.h/m`

**Interface**:

```objc
// PDSAdminController.h
@protocol PDSAdminController <NSObject>

#pragma mark - Account Administration
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error;
- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error;
- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error;
- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error;

#pragma mark - Moderation
- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error;
- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error;

#pragma mark - Labeling
- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error;
- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error;

@end

@interface PDSAdminController : NSObject <PDSAdminController>

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases
                          accountService:(id<PDSAccountService>)accountService;

@end
```

**Migration**:
1. Create `PDSAdminController` with methods moved from `PDSController`
2. Add `adminController` property to `PDSController`
3. Deprecate methods on `PDSController`, delegate to admin controller
4. Update XRPC handlers to use admin controller

**Deprecation Pattern**:

```objc
// In PDSController.m
- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    // TODO: Deprecated - use adminController directly
    return [_adminController getAllAccountsWithError:error];
}
```

---

### Phase 3: Consolidate Legacy Methods (Medium Risk)

**Goal**: Remove duplicate legacy methods, update callers

**Analysis of Legacy Methods**:

| Legacy Method | Current Equivalent | Action |
|---------------|-------------------|--------|
| `createSessionForIdentifier:password:handle:did:error:` | `loginWithHandle:password:error:` | Delegate |
| `refreshSessionWithRefreshToken:error:` | `refreshAccessToken:error:` | Delegate |
| `describeRepo:error:` | (composite) | Keep as convenience |
| `getRepoDataForDid:error:` | `getRepoContents:since:error:` | Delegate |
| `getRepoHeadForDid:error:` | `getRepoRoot:error:` | Delegate |
| `createRecordForDid:...` | `putRecord:...` | Delegate |
| `getRecordForDid:...` | `getRecord:...` | Delegate |
| `listRecordsForDid:...` | `listRecords:...` | Delegate |
| `deleteRecordForDid:...` | `deleteRecord:...` | Delegate |
| `putRecordForDid:...` | `putRecord:...` | Delegate |
| `uploadBlob:mimeType:did:error:` | `uploadBlob:forDid:mimeType:error:` | Delegate |
| `getBlobWithCID:did:error:` | (in blob service) | Delegate |
| `listBlobsForDID:...` | (in blob service) | Delegate |
| `deleteBlobWithCID:...` | (in blob service) | Delegate |

**Migration Strategy**:

1. **Add deprecation warnings** (compile-time):
   ```objc
   - (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                                password:(NSString *)password
                                                 handle:(NSString *)handle
                                                    did:(NSString *)did
                                                  error:(NSError **)error
       __attribute__((deprecated("Use loginWithIdentifier:password:error: instead")));
   ```text

2. **Update internal callers** - grep for legacy method usage
3. **Update tests** - migrate to new APIs
4. **Document migration** in CHANGELOG

---

### Phase 4: Create PDSApplication Facade (Low Risk)

**Goal**: Introduce new entry point that composes controllers

**New Files**:
- `ATProtoPDS/Sources/App/PDSApplication.h/m`

**Interface**:

```objc
// PDSApplication.h
@interface PDSApplication : NSObject

#pragma mark - Lifecycle
+ (instancetype)sharedApplication;
- (instancetype)initWithConfiguration:(PDSConfiguration *)config;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;

#pragma mark - Controllers (for XRPC handlers)
@property (nonatomic, strong, readonly) id<PDSAccountService> accountService;
@property (nonatomic, strong, readonly) PDSRecordService *recordService;
@property (nonatomic, strong, readonly) PDSBlobService *blobService;
@property (nonatomic, strong, readonly) PDSRepositoryService *repositoryService;
@property (nonatomic, strong, readonly) id<PDSAdminController> adminController;

#pragma mark - Infrastructure
@property (nonatomic, strong, readonly) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong, readonly) PDSDatabasePool *userDatabasePool;
@property (nonatomic, strong, readonly) JWTMinter *jwtMinter;

#pragma mark - Backward Compatibility
@property (nonatomic, strong, readonly) PDSController *legacyController;

@end
```

**Implementation Strategy**:

```objc
// PDSApplication.m
@implementation PDSApplication

+ (instancetype)sharedApplication {
    static PDSApplication *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSApplication alloc] initWithConfiguration:[PDSConfiguration sharedConfiguration]];
    });
    return shared;
}

- (instancetype)initWithConfiguration:(PDSConfiguration *)config {
    self = [super init];
    if (self) {
        // Initialize database pools
        _serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:config.dataDirectory ...];
        _userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:config.dataDirectory ...];
        
        // Initialize services (DI-style)
        _accountService = [[PDSAccountService alloc] initWithDatabasePool:_userDatabasePool];
        _recordService = [[PDSRecordService alloc] initWithDatabasePool:_userDatabasePool];
        _blobService = [[PDSBlobService alloc] initWithDatabasePool:_userDatabasePool storage:...];
        _repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:_userDatabasePool];
        
        // Initialize controllers
        _adminController = [[PDSAdminController alloc] initWithServiceDatabases:_serviceDatabases
                                                                 accountService:_accountService];
        
        // Backward compatibility - wrap everything in legacy controller
        _legacyController = [[PDSController alloc] initWithApplication:self];
    }
    return self;
}

@end
```

---

### Phase 5: Update PDSController to Delegate (Medium Risk)

**Goal**: Convert `PDSController` to thin facade over `PDSApplication`

**Changes to PDSController**:

```objc
// PDSController.h - Add new initializer
- (instancetype)initWithApplication:(PDSApplication *)application;

// PDSController.m
@implementation PDSController {
    PDSApplication *_application;  // New: backing application
    // Remove all service ivars - delegate to application
}

- (instancetype)initWithApplication:(PDSApplication *)application {
    self = [super init];
    if (self) {
        _application = application;
    }
    return self;
}

// All methods delegate to application's services
- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                        password:(NSString *)password
                                         handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                           error:(NSError **)error {
    return [_application.accountService createAccountForEmail:email
                                                     password:password
                                                       handle:handle
                                                          did:did
                                                        error:error];
}

// etc.
```

---

### Phase 6: Migrate XRPC Handlers (High Risk - Careful)

**Goal**: Update `XrpcMethodRegistry` to use services directly

**Current State**:
```objc
// XrpcMethodRegistry.m
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher 
                           controller:(PDSController *)controller {
    // All handlers take PDSController
}
```

**Target State**:
```objc
// XrpcMethodRegistry.m
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher 
                          application:(PDSApplication *)application {
    // Handlers take specific services
    [dispatcher registerMethod:@"com.atproto.server.createAccount" 
                       handler:^(NSDictionary *params, HttpResponse *response) {
        // Use application.accountService directly
    }];
}
```

**Migration**:
1. Add new method `registerMethodsWithApplication:`
2. Update individual handlers one at a time
3. Keep old method for backward compatibility during transition
4. Remove old method once all handlers migrated

---

### Phase 7: Remove Utility Methods (Low Risk)

**Goal**: Extract utility methods to appropriate locations

**Methods to Extract**:

| Method | New Location | Reason |
|--------|--------------|--------|
| `base32Encode:` | `CID` class | Already has base32 methods |
| `iso8601Formatter()` | `NSDateFormatter+ATProto` category | Reusable |
| `lexiconSearchPathsForDirectory:` | `ATProtoLexiconRegistry` | Belongs with lexicons |
| `defaultDataDirectory` | `PDSConfiguration` | Configuration concern |

---

## File Structure After Refactor

```

ATProtoPDS/Sources/
├── App/
│   ├── PDSApplication.h/m           # NEW: Main entry point
│   ├── PDSController.h/m            # MODIFIED: Thin facade (deprecated)
│   ├── PDSConfiguration.h/m         # EXISTING
│   ├── Services/
│   │   ├── PDSAccountService.h/m    # EXISTING
│   │   ├── PDSBlobService.h/m       # EXISTING
│   │   ├── PDSRecordService.h/m     # EXISTING
│   │   └── PDSRepositoryService.h/m # EXISTING
│   └── ...
├── Admin/
│   ├── PDSAdminController.h/m       # NEW: Admin operations
│   ├── PDSModerationService.h/m     # NEW: Moderation (future)
│   └── PDSLabelingService.h/m       # NEW: Labeling (future)
├── Network/
│   ├── PDSHttpServerBuilder.h/m     # NEW: Server configuration
│   ├── PDSServerConfiguration.h/m   # NEW: Server settings
│   ├── HttpServer.h/m               # EXISTING
│   └── ...
└── Core/
    ├── PDSServiceContainer.h/m      # EXISTING
    ├── NSDateFormatter+ATProto.h/m  # NEW: Date utilities
    └── ...
```

---

## Test Migration Strategy

### Existing Tests to Update

| Test File | Changes Needed |
|-----------|----------------|
| `PDSControllerTests.m` | Add tests for delegation behavior |
| `PDSIntegrationTests.m` | Update to use `PDSApplication` |
| `PDSAccountServiceTests.m` | No changes (already isolated) |
| `PDSRecordServiceTests.m` | No changes (already isolated) |
| `PDSBlobServiceTests.m` | No changes (already isolated) |
| `XrpcMethodRegistryTests.m` | Add tests for new registration |

### New Tests to Create

| Test File | Purpose |
|-----------|---------|
| `PDSApplicationTests.m` | Test new entry point |
| `PDSAdminControllerTests.m` | Test admin operations |
| `PDSHttpServerBuilderTests.m` | Test server configuration |

---

## Rollback Strategy

Each phase is designed to be independently reversible:

1. **Phase 1-2**: New files can be deleted, imports removed
2. **Phase 3**: Deprecation warnings can be removed
3. **Phase 4**: `PDSApplication` can be removed, revert to `PDSController.sharedController`
4. **Phase 5-6**: Revert `PDSController` and `XrpcMethodRegistry` changes
5. **Phase 7**: Restore utility methods to `PDSController`

---

## Success Criteria

### Quantitative

- [ ] `PDSController.m` reduced from ~800 to <200 lines
- [ ] All 168 existing tests pass
- [ ] No increase in test execution time (>10%)
- [ ] Code coverage maintained or improved

### Qualitative

- [ ] Each class has single responsibility
- [ ] New components are independently testable
- [ ] Legacy API continues to work (deprecation warnings only)
- [ ] Clear migration path documented

---

## Timeline Estimate

| Phase | Effort | Risk | Dependencies |
|-------|--------|------|--------------|
| Phase 1: Extract HTTP Server Setup | 2-3 hours | Low | None |
| Phase 2: Create Admin Controller | 3-4 hours | Medium | None |
| Phase 3: Consolidate Legacy Methods | 2-3 hours | Medium | Phase 2 |
| Phase 4: Create PDSApplication | 4-5 hours | Low | Phases 1-2 |
| Phase 5: Update PDSController | 3-4 hours | Medium | Phase 4 |
| Phase 6: Migrate XRPC Handlers | 4-6 hours | High | Phase 5 |
| Phase 7: Remove Utility Methods | 1-2 hours | Low | Phase 5 |

**Total Estimate**: 20-27 hours (3-4 days of focused work)

---

## Open Questions

1. **Should `PDSController.sharedController` be deprecated?**
   - Recommendation: Yes, favor `PDSApplication.sharedApplication`

2. **Should legacy methods be removed in a future version?**
   - Recommendation: Yes, after 2 minor versions with deprecation warnings

3. **Should services use protocols for all public interfaces?**
   - Recommendation: Yes, enables better testing and future flexibility

4. **Should `PDSServiceContainer` be enhanced or replaced?**
   - Recommendation: Enhance with typed resolution for protocols

---

## Appendix: Method Inventory

### PDSController Methods (Current)

```objc
// Lifecycle (keep in PDSApplication)
+ sharedController
- initWithDirectory:serviceMaxSize:userDatabaseSize:
- startServerWithError:
- stopServer

// Account (delegate to PDSAccountService)
- createAccountForEmail:password:handle:did:error:
- getAccountForDid:error:
- loginWithHandle:password:error:
- refreshAccessToken:error:
- deleteAccount:password:error:
- createSessionForIdentifier:password:handle:did:error:  // LEGACY
- refreshSessionWithRefreshToken:error:                   // LEGACY

// Repository (delegate to PDSRepositoryService)
- getRepoRoot:error:
- getRepoContents:since:error:
- updateRepo:commit:error:
- describeRepo:error:                                     // LEGACY (composite)
- getRepoDataForDid:error:                                // LEGACY
- getRepoHeadForDid:error:                                // LEGACY

// Record (delegate to PDSRecordService)
- getRecord:forDid:error:
- listRecords:forDid:limit:cursor:error:
- putRecord:rkey:value:forDid:validationMode:error:
- deleteRecord:rkey:forDid:error:
- createRecordForDid:collection:record:validationMode:error:  // LEGACY
- getRecordForDid:collection:rkey:error:                       // LEGACY
- listRecordsForDid:collection:limit:cursor:error:             // LEGACY
- deleteRecordForDid:collection:rkey:error:                    // LEGACY
 - getRepoStatsForDid:error:
 - putRecordForDid:collection:rkey:record:validationMode:error: // LEGACY

 // Blob (delegate to PDSBlobService)
 - getBlob:forDid:error:
 - uploadBlob:forDid:mimeType:error:
 - uploadBlob:mimeType:did:error:                          // LEGACY
 - getBlobWithCID:did:error:                               // LEGACY
 - listBlobsForDID:limit:cursor:error:                     // LEGACY
 - deleteBlobWithCID:did:error:                            // LEGACY

 // Write (keep as convenience)
 - applyWrites:repo:validate:swapCommit:error:

 // Admin (move to PDSAdminController)
 - getAllAccountsWithError:
 - takeDownAccount:reason:error:
 - reinstateAccount:error:
 - isAccountTakedownActive:error:

 // Moderation (move to PDSAdminController)
 - moderateAccount:error:
 - moderateRecord:error:

 // Labeling (move to PDSAdminController)
 - createLabel:error:
 - getLabels:error:

 // Health (move to PDSHealthService or keep)
 - getHealthCheck
 - getMetrics
 - serviceDatabaseWithError:
 ```text

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation
