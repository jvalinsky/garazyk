---
title: "XRPC Service Implementation Guide"
---

# XRPC Service Implementation Guide

> **Status:** Reference Document
> **Generated:** 2026-04-15

---

## Architecture Overview

This project uses a **Service Layer + XRPC Handler Pack** pattern:

```
XrpcMethodRegistry.m (orchestrator - registers all method packs)
    ↓
Xrpc[Namespace]Pack.m (handler packs - register XRPC methods)
    ↓
Service classes (business logic - database operations)
    ↓
Database/Repository layer (persistence)
```

---

## Step-by-Step: Implementing a New XRPC Service

### Step 1: Create Service Class (Business Logic)

**Location:** `Garazyk/Sources/Services/PDS/` or `Garazyk/Sources/AppView/Services/`

**Pattern:** Follow `PDSAccountService.h`:
1. Define protocol first (`@protocol PDSXxxService <NSObject>`)
2. Then concrete implementation (`@interface PDSXxxService : NSObject`)
3. Use dependency injection in initializers
4. Properties expose database, repositories, other services

**Example Structure:**
```objc
/*!
 @file PDSChatService.h
 @abstract Chat/direct message service layer.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;
@class ActorService;

@protocol PDSChatService <NSObject>

- (nullable NSDictionary *)getConvo:(NSString *)convoId forDid:(NSString *)did error:(NSError **)error;
- (nullable NSArray *)listConvosForDid:(NSString *)did limit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;
// ... other methods

@end

@interface PDSChatService : NSObject <PDSChatService>

@property (nonatomic, strong, readonly) PDSDatabase *database;
@property (nonatomic, strong, nullable) ActorService *actorService;

- (instancetype)initWithDatabase:(PDSDatabase *)database;
- (instancetype)initWithDatabase:(PDSDatabase *)database actorService:(nullable ActorService *)actorService;

@end

NS_ASSUME_NONNULL_END
```

---

### Step 2: Create XRPC Handler Pack

**Location:** `Garazyk/Sources/Network/Xrpc[Namespace]Pack.m`

**Pattern:** Follow `XrpcAppBskyNotificationPack.m`:

```objc
#import "Network/Xrpc[Namespace]Pack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Services/SomeService.h"
#import "Debug/PDSLogger.h"

@implementation Xrpc[Namespace]Pack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              appViewDatabase:(PDSDatabase *)appViewDatabase
                    jwtMinter:(JWTMinter *)jwtMinter
              adminController:(id<PDSAdminController>)adminController {
    
    // Instantiate service with dependencies
    SomeService *svc = [[SomeService alloc] initWithDatabase:appViewDatabase];
    
    // Register endpoint
    [dispatcher registerMethod:@"app.bsky.namespace.someEndpoint" 
                       handler:^(HttpRequest *request, HttpResponse *response) {
        
        // 1. Check authentication
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        
        // 2. Extract DID from auth
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;
        
        // 3. Parse input
        NSDictionary *body = request.jsonBody;
        if (!body || ![body isKindOfClass:[NSDictionary class]]) {
            [XrpcErrorHelper setValidationError:response message:@"Missing request body"];
            return;
        }
        
        // 4. Validate required fields
        NSString *requiredParam = body[@"someParam"];
        if (!requiredParam || ![requiredParam isKindOfClass:[NSString class]]) {
            [XrpcErrorHelper setValidationError:response message:@"someParam is required"];
            return;
        }
        
        // 5. Call service
        NSError *error = nil;
        NSDictionary *result = [svc doSomethingForActor:actorDID param:requiredParam error:&error];
        if (!result) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Operation failed"];
            return;
        }
        
        // 6. Return success
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    PDS_LOG_INFO(@"Registered app.bsky.namespace.* endpoints");
}

@end
```

---

### Step 3: Register in XrpcMethodRegistry

**Location:** `Garazyk/Sources/Network/XrpcMethodRegistry.m`

Add the registration call where other packs are registered (around line 537):

```objc
// In the registerMethodsWithDispatcher:application: method
[Xrpc[Namespace]Pack registerWithDispatcher:dispatcher
                           appViewDatabase:appViewDatabase
                                 jwtMinter:jwtMinter
                           adminController:adminController];
```

---

### Step 4: Add Typed Registration Helpers (Optional)

**Location:** `Garazyk/Sources/Network/XrpcHandler.m`

Add convenience methods for typed registration:

```objc
- (void)registerAppBskyNamespaceSomeEndpoint:(XrpcMethodHandler)handler {
    [self registerMethod:@"app.bsky.namespace.someEndpoint" handler:handler];
}
```

---

## File Structure Template

```
Garazyk/Sources/
├── Services/
│   └── PDS/
│       ├── PDSChatService.h      (protocol + interface)
│       └── PDSChatService.m       (implementation)
├── Network/
│   ├── XrpcChatBskyConvoPack.h    (handler header)
│   └── XrpcChatBskyConvoPack.m    (XRPC handlers)
└── Network/
    └── XrpcMethodRegistry.m       (add registration)
```

---

## Testing

1. Add test class to `Garazyk/Tests/test_main.m`:
   ```objc
   @"XrpcChatBskyConvoPackTests",
   ```

2. Register in test setup:
   ```objc
   [XrpcMethodRegistry registerMethodsWithDispatcher:self.dispatcher 
                                         controller:self.controller];
   ```

3. Test authentication, validation, success, and error cases

---

## Related Plans

- [2026-04-10-chat-conversation-support.md](./2026-04-10-chat-conversation-support.md) - Chat/DM implementation
- [2026-04-10-video-processing-pipeline.md](./2026-04-10-video-processing-pipeline.md) - Video processing
