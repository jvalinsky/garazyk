# XRPC Wiring Patterns

## Table of Contents

- [XrpcDispatcher](#xrpcdispatcher)
- [Route Pack Pattern](#route-pack-pattern)
- [XrpcMethodRegistry (PDS-style)](#xrpcmethodregistry-pds-style)
- [Handler Block Signature](#handler-block-signature)
- [Adding a New XRPC Method](#adding-a-new-xrpc-method)

## XrpcDispatcher

The `XrpcDispatcher` (singleton via `[XrpcDispatcher sharedDispatcher]`) routes XRPC requests to handlers by method NSID.

Key methods:
```objc
// Register a handler for a method NSID
- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler;

// Register with middleware chain
- (void)registerMethod:(NSString *)methodId
           middlewares:(nullable NSArray<id<XrpcMiddleware>> *)middlewares
               handler:(XrpcMethodHandler)handler;

// Check if already registered
- (BOOL)hasRegisteredMethod:(NSString *)methodId;

// Dispatch a request
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;
```

Properties for proxying:
```objc
@property (nonatomic, copy, nullable) NSURL *proxyURL;       // AppView proxy
@property (nonatomic, copy, nullable) NSString *upstreamDID;  // Service auth
@property (nonatomic, strong, nullable) JWTMinter *jwtMinter; // Token minting
```

## Route Pack Pattern

A route pack encapsulates XRPC method registration for a specific service domain.

### Header Template

```objc
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class HttpServer;
@class XrpcDispatcher;

NS_ASSUME_NONNULL_BEGIN

@interface <Name>XrpcRoutePack : NSObject

@property (nonatomic, strong, nullable) <DependencyType> *dependency;

- (instancetype)initWith<Dependency>:(<DependencyType> *)dependency;
- (instancetype)init NS_UNAVAILABLE;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
```

### Implementation Template

```objc
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "<Name>XrpcRoutePack.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation <Name>XrpcRoutePack

- (instancetype)initWith<Dependency>:(<DependencyType> *)dependency {
    self = [super init];
    if (self) {
        _dependency = dependency;
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server {
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];

    // Register XRPC methods
    [dispatcher registerMethod:@"com.atproto.<domain>.<method>"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        // Handle the request
    }];

    // Register HTTP routes (non-XRPC)
    [server addRoute:@"GET"
                path:@"/api/<name>/health"
             handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setBodyString:@"{\"status\":\"ok\"}"];
    }];

    // WebSocket route (if needed)
    [server addWebSocketRoute:@"/xrpc/com.atproto.<domain>.subscribe"
                       handler:^(HttpRequest *request, HttpResponse *response,
                                 id<PDSNetworkConnection> connection) {
        // Accept upgraded connection
    }];
}

@end
```

### Existing Route Packs

| Route Pack | Service | Registers |
|-----------|---------|-----------|
| `PDSHttpXrpcRoutePack` | PDS | `/xrpc/*` transport, subscribeRepos WebSocket |
| `RelayXrpcRoutePack` | Relay | `com.atproto.sync.*` methods |
| `AppViewXRpcRoutePack` | AppView | `app.bsky.*` + selected `com.atproto.*` |
| `AppViewAdminRoutePack` | AppView | `/admin/*` routes |

## XrpcMethodRegistry (PDS-style)

For PDS services that need the full method set, `XrpcMethodRegistry` delegates to domain modules:

```
XrpcMethodRegistry
├── XrpcServerMethods     → com.atproto.server.*
├── XrpcRepoMethods       → com.atproto.repo.*
├── XrpcSyncMethods       → com.atproto.sync.*
├── XrpcIdentityMethods   → com.atproto.identity.*
├── XrpcAdminMethods      → com.atproto.admin.*
├── XrpcLabelMethods      → com.atproto.label.*
└── XrpcAppBskyMethods    → app.bsky.*
```

Helper modules:
- `XrpcAuthHelper` — JWT and DPoP authentication
- `XrpcIdentityHelper` — Handle and DID resolution
- `XrpcErrorHelper` — Standardized error responses

To add a new domain module:
1. Create `Xrpc<Domain>Methods.{h,m}` in `Sources/Network/`
2. Add registration method to `XrpcDispatcher.h`
3. Call from `XrpcMethodRegistry` in the correct order

## Handler Block Signature

All XRPC handlers use the same block type:

```objc
typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);
```

Common patterns inside handlers:

```objc
// Parse query parameters
NSString *actor = request.queryParams[@"actor"];

// Parse JSON body
NSData *body = request.body;
NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];

// Set JSON response
response.statusCode = 200;
response.contentType = @"application/json";
[response setBodyString:[self jsonStringFromObject:result]];

// Error response
response.statusCode = 400;
response.contentType = @"application/json";
[response setBodyString:@"{\"error\":\"InvalidRequest\",\"message\":\"...\"}"];
```

## Adding a New XRPC Method

### Standalone Service (Route Pack)

1. Add the registration method to `XrpcDispatcher.h`:
   ```objc
   - (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler;
   ```

2. Implement in `XrpcDispatcher.m`:
   ```objc
   - (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler {
       [self registerMethod:@"com.atproto.label.queryLabels" handler:handler];
   }
   ```

3. Call from the route pack:
   ```objc
   [dispatcher registerComAtprotoLabelQueryLabels:^(HttpRequest *req, HttpResponse *resp) {
       // handler implementation
   }];
   ```

### PDS Service (XrpcMethodRegistry)

1. Create domain module `Xrpc<Domain>Methods.{h,m}`
2. Add convenience method to `XrpcDispatcher`
3. Register in `XrpcMethodRegistry` with DI from `PDSApplication`
4. Add to `ATProtoXRPC` static lib sources in CMake
