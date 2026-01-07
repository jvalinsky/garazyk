# ATProto PDS Objective-C Codebase Organization Plan

## Executive Summary

This document outlines a comprehensive plan to organize the ATProto PDS codebase following Objective-C/macOS best practices. Based on research from Microsoft's objc-guide, BottleRocket's iOS Project Standards, and established Cocoa patterns, we present a modern, maintainable structure.

---

## Current State Analysis

### Existing Structure (Good Points)

```
ATProtoPDS/ATProtoPDS/
├── Admin/           # Admin APIs
├── Auth/            # OAuth2, JWT, Session
├── Blob/            # Storage & validation
├── Database/        # PDSDatabase, Schema
├── Network/         # HTTP, XRPC, Rate limiting
├── Repository/      # MST, CAR, CBOR
├── Sync/            # WebSocket, Firehose
├── Tools/pds-cli/   # CLI tools
└── Core types:      # CID, DID, TID
```

### Metrics
- **68 .m implementation files**
- **47 .h header files**
- **14 modules**
- **42/42 passing tests**

### Issues Identified

1. **No clear separation of public vs private headers**
2. **Test files mixed with implementation files**
3. **No Private/Package/Protected header conventions**
4. **Flat structure within modules**
5. **Missing consistent naming conventions**
6. **Build artifacts in source tree** (build/, *.o files)
7. **Data files mixed with source** (data/, blobs/)
8. **No formal module organization**

---

## Best Practices Applied

### 1. Header Factoring (Microsoft objc-guide)

Use category-based header organization:

```
Class.h           - Public API (minimal)
Class+Private.h   - Internal API (testing only)
Class+Protected.h - Subclass API
Class+Package.h   - Module-internal API
```

### 2. Directory Structure (BottleRocket Standards)

```
Project/
├── Sources/
│   ├── App/           # App entry point
│   ├── Features/      # Feature modules
│   ├── Core/          # Shared utilities
│   ├── Models/        # Data models
│   ├── Services/      # Business logic
│   ├── Networking/    # API layer
│   └── UI/            # Views & controllers
├── Resources/
│   ├── Assets/
│   └── Localizations/
├── Tests/
└── Supporting/
```

### 3. File Naming Conventions

- **Public headers:** `ClassName.h`
- **Private headers:** `ClassName+Private.h`
- **Test files:** `ClassNameTests.m`
- **Test headers:** `ClassNameTests.h`

---

## Proposed New Structure

### High-Level Organization

```
ATProtoPDS/
├── Sources/
│   ├── App/
│   │   ├── AppDelegate.h/m
│   │   ├── main.m
│   │   └── PDSController.h/m
│   │
│   ├── Core/              # Foundation layer
│   │   ├── CID.h/m
│   │   ├── CID+Private.h
│   │   ├── DID.h/m
│   │   ├── DID+Private.h
│   │   ├── TID.h/m
│   │   ├── Constants.h
│   │   └── PDSDefines.h
│   │
│   ├── Identity/          # Identity resolution
│   │   ├── HandleResolver.h/m
│   │   ├── HandleResolver+Private.h
│   │   ├── DIDDocument.h/m
│   │   └── DID+Validation.h
│   │
│   ├── Auth/              # Authentication
│   │   ├── OAuth2.h/m
│   │   ├── OAuth2+Private.h
│   │   ├── Session.h/m
│   │   ├── JWT.h/m
│   │   ├── DPoPUtil.h/m
│   │   ├── KeyManager.h/m
│   │   ├── PKCEUtil.h/m
│   │   ├── Secp256k1.h/m
│   │   ├── OAuthSession.h/m
│   │   ├── OAuthServerMetadata.h/m
│   │   └── AuthConstants.h
│   │
│   ├── Repository/        # Data repository
│   │   ├── MST.h/m
│   │   ├── MST+Private.h
│   │   ├── MSTPersistence.h/m
│   │   ├── CAR.h/m
│   │   ├── CAR+Private.h
│   │   ├── CBOR.h/m
│   │   ├── RepoCommit.h/m
│   │   └── RepositoryRecord.h/m
│   │
│   ├── Blob/              # Blob storage
│   │   ├── BlobStorage.h/m
│   │   ├── BlobStorage+Private.h
│   │   ├── MimeTypeValidator.h/m
│   │   ├── BlobHandle.h/m
│   │   └── BlobReference.h/m
│   │
│   ├── Database/          # Data persistence
│   │   ├── PDSDatabase.h/m
│   │   ├── PDSDatabase+Private.h
│   │   ├── Schema.h/m
│   │   ├── AccountRecord.h/m
│   │   ├── RepoRecord.h/m
│   │   └── DatabaseMigration.h/m
│   │
│   ├── Network/           # HTTP & XRPC
│   │   ├── HttpServer.h/m
│   │   ├── HttpServer+Private.h
│   │   ├── HttpRequest.h/m
│   │   ├── HttpResponse.h/m
│   │   ├── XrpcHandler.h/m
│   │   ├── XrpcHandler+Private.h
│   │   ├── XrpcMethodRegistry.h/m
│   │   ├── RateLimiter.h/m
│   │   └── NetworkConstants.h
│   │
│   ├── Sync/              # Event streaming
│   │   ├── WebSocketServer.h/m
│   │   ├── WebSocketConnection.h/m
│   │   ├── Firehose.h/m
│   │   ├── RelayClient.h/m
│   │   ├── SubscribeReposHandler.h/m
│   │   ├── SyncEngine.h/m
│   │   └── EventFormatter.h/m
│   │
│   ├── Admin/             # Admin APIs
│   │   ├── AdminService.h/m
│   │   ├── AdminMiddleware.h/m
│   │   ├── PDSAdminAuth.h/m
│   │   ├── PDSAdminHandler.h/m
│   │   ├── ModerationService.h/m
│   │   └── LabelDefs.h
│   │
│   ├── Federation/        # Cross-server
│   │   ├── FederationClient.h/m
│   │   ├── PDSDiscovery.h/m
│   │   └── RemoteRepoFetch.h/m
│   │
│   ├── AppView/           # App services
│   │   ├── ActorService.h/m
│   │   ├── FeedService.h/m
│   │   ├── NotificationService.h/m
│   │   └── GraphService.h/m
│   │
│   ├── Metrics/           # Telemetry
│   │   ├── PDSMetrics.h/m
│   │   └── MetricsCollector.h/m
│   │
│   ├── CLI/               # Command line
│   │   ├── Tools/pds-cli/
│   │   ├── PDSCLI.h
│   │   ├── PDSCLIDispatcher.h/m
│   │   ├── PDSCLIServeCommand.h/m
│   │   ├── PDSCLIAccountCommand.h/m
│   │   └── PDSCLIDefinitions.h
│   │
│   └── Utils/             # Utilities
│       ├── PDSLogger.h/m
│       ├── PDSError.h
│       └── PDSResult.h
│
├── Tests/
│   ├── Core/
│   │   ├── CIDTests.h/m
│   │   ├── DIDTests.h/m
│   │   ├── TIDTests.h/m
│   │   └── TestUtilities.h/m
│   │
│   ├── Identity/
│   │   └── HandleResolverTests.h/m
│   │
│   ├── Auth/
│   │   ├── SessionTests.h/m
│   │   ├── OAuth2Tests.h/m
│   │   └── JWTTests.h/m
│   │
│   ├── Repository/
│   │   ├── MSTTests.h/m
│   │   └── CARTests.h/m
│   │
│   ├── Blob/
│   │   └── MimeTypeValidatorTests.h/m
│   │
│   ├── Database/
│   │   ├── PDSDatabaseTests.h/m
│   │   └── SchemaTests.h/m
│   │
│   ├── Network/
│   │   ├── XrpcHandlerTests.h/m
│   │   └── RateLimiterTests.h/m
│   │
│   └── Integration/
│       ├── EndToEndTests.h/m
│       └── PDSIntegrationTests.h/m
│
├── Resources/
│   ├── Assets/
│   ├── Config/
│   │   ├── config.yaml
│   │   └── server.crt
│   └── Localizations/
│
├── Supporting/
│   ├── docs/
│   ├── scripts/
│   └── build/
│
└── ATProtoPDS.xcodeproj/
```

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

1. **Create new directory structure**
2. **Move Core module** (CID, DID, TID)
3. **Create Private/Package/Protected headers**
4. **Set up TestUtilities**

### Phase 2: Reorganization (Week 2-3)

1. **Move Auth module** with proper header factoring
2. **Move Repository module**
3. **Move Network module**
4. **Update Xcode project references**

### Phase 3: Completion (Week 4)

1. **Move remaining modules**
2. **Consolidate tests** into Tests/ directory
3. **Create supporting directories**
4. **Clean up build artifacts**

---

## Header Organization Convention

### Public Header (Class.h)
```objc
// Class.h
@interface ClassName : NSObject

@property (nonatomic, copy) NSString *publicProperty;
- (void)publicMethod;

@end
```

### Private Header (Class+Private.h)
```objc
// Class+Private.h
@interface ClassName ()

@property (nonatomic, strong) NSInternalInternal *internalState;
- (void)internalMethod;
+ (ClassName *)sharedInstance;

@end
```

### Protected Header (Class+Protected.h)
```objc
// Class+Protected.h
@interface ClassName (Protected)

- (void)subclassOnlyMethod;
- (void)configureForSubclass;

@end
```

### Implementation (Class.m)
```objc
// Class.m
#import "Class.h"
#import "Class+Private.h"

@implementation Class
// Implementation
@end
```

---

## File Naming Rules

| Type | Pattern | Example |
|------|---------|---------|
| Public header | `ClassName.h` | `Session.h` |
| Private header | `ClassName+Private.h` | `Session+Private.h` |
| Protected header | `ClassName+Protected.h` | `Session+Protected.h` |
| Package header | `ClassName+Package.h` | `Session+Package.h` |
| Test header | `ClassNameTests.h` | `SessionTests.h` |
| Test impl | `ClassNameTests.m` | `SessionTests.m` |

---

## Benefits of This Organization

1. **Clear API boundaries** - Public vs private clearly defined
2. **Better testability** - Private headers accessible to tests
3. **Improved maintainability** - Files organized by responsibility
4. **Follows industry standards** - Microsoft, BottleRocket patterns
5. **Easier onboarding** - New developers understand structure
6. **Safer refactoring** - Private APIs clearly marked

---

## Migration Steps

### Step 1: Create Directories
```bash
mkdir -p Sources/{App,Core,Identity,Auth,Repository,Blob,Database,Network,Sync,Admin,Federation,AppView,Metrics,CLI,Utils}
mkdir -p Tests/{Core,Identity,Auth,Repository,Blob,Database,Network,Integration}
mkdir -p Resources/{Assets,Config,Localizations}
mkdir -p Supporting/{docs,scripts}
```

### Step 2: Move Files (one module at a time)
```bash
# Example: Move Auth module
mkdir -p Sources/Auth
mv Auth/*.h Sources/Auth/
mv Auth/*.m Sources/Auth/
```

### Step 3: Create Header Categories
```bash
# Create private headers for testing
for file in Sources/Auth/*.h; do
    name=$(basename "$file" .h)
    echo "@interface $name ()" > "Sources/Auth/$name+Private.h"
    echo "@end" >> "Sources/Auth/$name+Private.h"
done
```

### Step 4: Update Xcode Project
- Add new groups matching directory structure
- Remove old groups
- Update file references

### Step 5: Update Imports
```objc
// Before
#import "Auth/Session.h"

// After (if using modules)
@import ATProtoPDS.Auth;
// Or
#import "Sources/Auth/Session.h"
```

---

## Files to Exclude from Repository

Add to `.gitignore`:
```
# Build artifacts
build/
*.o
*.dylib
*.a

# IDE
.xcuserstate
*.xcuserdatad
*.moved-aside

# Data files (generated at runtime)
data/
blobs/
*.db
*.db-shm
*.db-wal

# Generated docs
docs/html/
```

---

## Summary

This reorganization plan follows established Objective-C/macOS best practices:

1. **Separation of concerns** - Clear module boundaries
2. **Header factoring** - Public/Private/Package/Protected
3. **Test isolation** - Tests in dedicated directory
4. **Consistent naming** - Predictable file patterns
5. **Industry standards** - Microsoft, BottleRocket patterns

The result will be a maintainable, well-organized codebase that follows professional macOS development practices.
