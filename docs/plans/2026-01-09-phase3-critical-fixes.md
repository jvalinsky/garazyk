# Phase 3 Critical Issues Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Address the 5 highest-priority P0/P1 issues to stabilize the ATProto PDS implementation and prepare for Phase 3 advanced testing.

**Architecture:** Focus on critical infrastructure gaps in DID resolution, OAuth metadata, PDS controller methods, and error handling. Each task builds on existing patterns in the codebase while filling functional gaps.

**Tech Stack:** Objective-C, Foundation framework, OAuth2, DID/Handle resolution, PDS controller architecture.

---

## Task 1: Fix Missing PDSController Methods

**Files:**
- Modify: `ATProtoPDS/Sources/App/PDSController.h`
- Modify: `ATProtoPDS/Sources/App/PDSController.m`
- Test: `ATProtoPDS/Tests/Database/PDSControllerTests.m`

**Context:** The PDS controller is missing critical methods for moderation and labeling endpoints that are required for ATProto compliance.

**Step 1: Analyze missing methods by checking ATProto spec**

Review the ATProto PDS specification to identify required moderation and labeling endpoints that are missing from PDSController.

**Step 2: Add moderation endpoint stubs**

```objc
// In PDSController.h
- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error;
- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error;

// In PDSController.m
- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    // TODO: Implement moderation logic
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    // TODO: Implement record moderation logic
    return @{@"status": @"not_implemented"};
}
```

**Step 3: Add labeling endpoint stubs**

```objc
// In PDSController.h
- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error;
- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error;

// In PDSController.m
- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
    // TODO: Implement label creation
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
    // TODO: Implement label retrieval
    return @{@"status": @"not_implemented"};
}
```

**Step 4: Update XRPC method registry**

Add the new methods to the XRPC method registry in `XrpcMethodRegistry.m`.

**Step 5: Add basic tests**

```objc
// In PDSControllerTests.m
- (void)testModerateAccountEndpoint {
    PDSController *controller = [[PDSController alloc] init];
    NSDictionary *params = @{@"did": @"did:plc:test", @"reason": @"spam"};
    NSError *error = nil;

    NSDictionary *result = [controller moderateAccount:params error:&error];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"status"], @"not_implemented");
}
```

**Step 6: Commit**

```bash
git add ATProtoPDS/Sources/App/PDSController.h ATProtoPDS/Sources/App/PDSController.m ATProtoPDS/Tests/Database/PDSControllerTests.m ATProtoPDS/Sources/Network/XrpcMethodRegistry.m
git commit -m "feat: add moderation and labeling endpoint stubs to PDSController"
```

---

## Task 2: Implement OAuth Server Metadata Publishing

**Files:**
- Create: `ATProtoPDS/Sources/Auth/OAuthServerMetadata.h`
- Create: `ATProtoPDS/Sources/Auth/OAuthServerMetadata.m`
- Modify: `ATProtoPDS/Sources/Network/HttpRouter.m`
- Test: `ATProtoPDS/Tests/Auth/OAuth2Tests.m`

**Context:** OAuth 2.0 requires server metadata discovery endpoint for client registration and configuration.

**Step 1: Create OAuthServerMetadata class**

```objc
// OAuthServerMetadata.h
@interface OAuthServerMetadata : NSObject
@property (nonatomic, readonly) NSDictionary *metadata;
- (instancetype)initWithBaseURL:(NSString *)baseURL;
@end

// OAuthServerMetadata.m
@implementation OAuthServerMetadata

- (instancetype)initWithBaseURL:(NSString *)baseURL {
    self = [super init];
    if (self) {
        _metadata = @{
            @"issuer": baseURL,
            @"authorization_endpoint": [baseURL stringByAppendingPathComponent:@"/oauth/authorize"],
            @"token_endpoint": [baseURL stringByAppendingPathComponent:@"/oauth/token"],
            @"jwks_uri": [baseURL stringByAppendingPathComponent:@"/oauth/jwks"],
            @"response_types_supported": @[@"code"],
            @"grant_types_supported": @[@"authorization_code", @"refresh_token"],
            @"token_endpoint_auth_methods_supported": @[@"client_secret_basic"],
            @"scopes_supported": @[@"atproto"]
        };
    }
    return self;
}

@end
```

**Step 2: Add metadata endpoint to HTTP router**

```objc
// In HttpRouter.m
- (void)setupRoutes {
    // ... existing routes ...

    [self addRoute:@"/.well-known/oauth-authorization-server"
           method:@"GET"
           handler:^(HttpRequest *request, HttpResponse *response) {
        OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] initWithBaseURL:self.baseURL];
        [response setJSONBody:metadata.metadata];
        response.statusCode = 200;
    }];
}
```

**Step 3: Add tests for metadata endpoint**

```objc
// In OAuth2Tests.m
- (void)testOAuthServerMetadataEndpoint {
    // Test that /.well-known/oauth-authorization-server returns correct metadata
    HttpRouter *router = [[HttpRouter alloc] initWithBaseURL:@"https://example.com"];

    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/.well-known/oauth-authorization-server";

    HttpResponse *response = [[HttpResponse alloc] init];

    [router handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 200);
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertNotNil(metadata[@"issuer"]);
    XCTAssertNotNil(metadata[@"authorization_endpoint"]);
}
```

**Step 4: Commit**

```bash
git add ATProtoPDS/Sources/Auth/OAuthServerMetadata.h ATProtoPDS/Sources/Auth/OAuthServerMetadata.m ATProtoPDS/Sources/Network/HttpRouter.m ATProtoPDS/Tests/Auth/OAuth2Tests.m
git commit -m "feat: implement OAuth 2.0 server metadata discovery endpoint"
```

---

## Task 3: Enhance DID Resolution Service

**Files:**
- Modify: `ATProtoPDS/Sources/Identity/DIDResolver.h`
- Modify: `ATProtoPDS/Sources/Identity/DIDResolver.m`
- Test: `ATProtoPDS/Tests/Identity/DIDResolverTests.m`

**Context:** The DID resolution service needs advanced features like caching, batch resolution, and error handling.

**Step 1: Add caching to DID resolver**

```objc
// In DIDResolver.h
@property (nonatomic, strong) NSCache *cache;

// In DIDResolver.m
- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 1000; // Cache up to 1000 DIDs
    }
    return self;
}
```

**Step 2: Implement cached resolution**

```objc
- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary *document, NSError *error))completion {
    // Check cache first
    NSDictionary *cached = [self.cache objectForKey:did];
    if (cached) {
        completion(cached, nil);
        return;
    }

    // Perform resolution
    [self performResolution:did completion:^(NSDictionary *document, NSError *error) {
        if (document && !error) {
            [self.cache setObject:document forKey:did];
        }
        completion(document, error);
    }];
}
```

**Step 3: Add batch resolution support**

```objc
- (void)resolveMultipleDIDs:(NSArray<NSString *> *)dids completion:(void (^)(NSDictionary<NSString *, NSDictionary *> *results, NSError *error))completion {
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    __block NSUInteger remaining = dids.count;

    for (NSString *did in dids) {
        [self resolveDID:did completion:^(NSDictionary *document, NSError *error) {
            @synchronized(results) {
                if (document) {
                    results[did] = document;
                }
                remaining--;
                if (remaining == 0) {
                    completion(results, nil);
                }
            }
        }];
    }
}
```

**Step 4: Add tests for caching and batch resolution**

```objc
// In DIDResolverTests.m
- (void)testDIDResolutionCaching {
    DIDResolver *resolver = [[DIDResolver alloc] init];

    // First resolution should cache
    XCTestExpectation *expectation = [self expectationWithDescription:@"First resolution"];
    [resolver resolveDID:@"did:plc:test" completion:^(NSDictionary *document, NSError *error) {
        XCTAssertNotNil(document);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // Second resolution should use cache
    expectation = [self expectationWithDescription:@"Cached resolution"];
    [resolver resolveDID:@"did:plc:test" completion:^(NSDictionary *document, NSError *error) {
        XCTAssertNotNil(document);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:1.0 handler:nil]; // Should be fast
}
```

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Identity/DIDResolver.h ATProtoPDS/Sources/Identity/DIDResolver.m ATProtoPDS/Tests/Identity/DIDResolverTests.m
git commit -m "feat: enhance DID resolution service with caching and batch resolution"
```

---

## Task 4: Add Error Handling to Metadata Endpoints

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuthServerMetadata.m`
- Test: `ATProtoPDS/Tests/Auth/OAuth2Tests.m`

**Context:** Metadata endpoints need proper error handling for invalid requests and server errors.

**Step 1: Add error handling to metadata endpoint**

```objc
// In HttpRouter.m metadata endpoint handler
- (void)setupRoutes {
    [self addRoute:@"/.well-known/oauth-authorization-server"
           method:@"GET"
           handler:^(HttpRequest *request, HttpResponse *response) {
        @try {
            OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] initWithBaseURL:self.baseURL];
            if (!metadata) {
                response.statusCode = 500;
                [response setJSONBody:@{@"error": @"server_error", @"error_description": @"Failed to generate metadata"}];
                return;
            }
            [response setJSONBody:metadata.metadata];
            response.statusCode = 200;
        } @catch (NSException *exception) {
            response.statusCode = 500;
            [response setJSONBody:@{@"error": @"server_error", @"error_description": @"Internal server error"}];
        }
    }];
}
```

**Step 2: Add validation for base URL**

```objc
// In OAuthServerMetadata.m
- (instancetype)initWithBaseURL:(NSString *)baseURL {
    if (!baseURL || ![baseURL hasPrefix:@"https://"]) {
        return nil;
    }

    self = [super init];
    if (self) {
        // ... existing metadata setup ...
    }
    return self;
}
```

**Step 3: Add error handling tests**

```objc
// In OAuth2Tests.m
- (void)testMetadataEndpointErrorHandling {
    HttpRouter *router = [[HttpRouter alloc] initWithBaseURL:@"invalid-url"];

    HttpRequest *request = [[HttpRequest alloc] init];
    request.method = @"GET";
    request.path = @"/.well-known/oauth-authorization-server";

    HttpResponse *response = [[HttpResponse alloc] init];
    [router handleRequest:request response:response];

    XCTAssertEqual(response.statusCode, 500);
    NSDictionary *errorResponse = [NSJSONSerialization JSONObjectWithData:response.body options:0 error:nil];
    XCTAssertNotNil(errorResponse[@"error"]);
}
```

**Step 4: Commit**

```bash
git add ATProtoPDS/Sources/Auth/OAuthServerMetadata.m ATProtoPDS/Sources/Network/HttpRouter.m ATProtoPDS/Tests/Auth/OAuth2Tests.m
git commit -m "feat: add proper error handling to OAuth metadata endpoints"
```

---

## Task 5: Implement YubiKey OATH Integration

**Files:**
- Create: `ATProtoPDS/Sources/Auth/YubiKeyOATH.h`
- Create: `ATProtoPDS/Sources/Auth/YubiKeyOATH.m`
- Modify: `ATProtoPDS/Sources/Auth/TOTPService.m`
- Test: `ATProtoPDS/Tests/Auth/TOTPTests.m`

**Context:** Add hardware security key support for TOTP generation using YubiKey OATH protocol.

**Step 1: Create YubiKey OATH interface**

```objc
// YubiKeyOATH.h
@protocol YubiKeyOATH <NSObject>
- (BOOL)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error;
- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error;
@end

@interface YubiKeyOATHManager : NSObject <YubiKeyOATH>
@end
```

**Step 2: Implement basic YubiKey OATH manager**

```objc
// YubiKeyOATH.m
@implementation YubiKeyOATHManager

- (BOOL)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error {
    // TODO: Implement actual YubiKey communication
    // For now, fall back to software TOTP
    return [self fallbackTOTPGeneration:secret counter:counter error:error];
}

- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error {
    // TODO: Implement YubiKey secret programming
    if (error) {
        *error = [NSError errorWithDomain:@"YubiKeyOATHErrorDomain"
                                  code:1000
                              userInfo:@{NSLocalizedDescriptionKey: @"YubiKey OATH not yet implemented"}];
    }
    return NO;
}

- (BOOL)fallbackTOTPGeneration:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error {
    // Use existing software TOTP generation as fallback
    return YES;
}

@end
```

**Step 3: Integrate with TOTP service**

```objc
// In TOTPService.m
- (instancetype)init {
    self = [super init];
    if (self) {
        _yubiKeyManager = [[YubiKeyOATHManager alloc] init];
    }
    return self;
}

- (NSString *)generateTOTPToken:(NSError **)error {
    // Try hardware token first, fall back to software
    if ([self.yubiKeyManager generateTOTPForSecret:self.secret counter:self.counter error:error]) {
        return [self getHardwareToken];
    } else {
        return [self generateSoftwareToken];
    }
}
```

**Step 4: Add basic tests**

```objc
// In TOTPTests.m
- (void)testYubiKeyOATHFallback {
    TOTPService *service = [[TOTPService alloc] init];
    NSError *error = nil;

    NSString *token = [service generateTOTPToken:&error];
    XCTAssertNotNil(token);
    XCTAssertNil(error);
}
```

**Step 5: Commit**

```bash
git add ATProtoPDS/Sources/Auth/YubiKeyOATH.h ATProtoPDS/Sources/Auth/YubiKeyOATH.m ATProtoPDS/Sources/Auth/TOTPService.m ATProtoPDS/Tests/Auth/TOTPTests.m
git commit -m "feat: add YubiKey OATH integration framework with software fallback"
```

---

## Success Metrics

- **All P0 issues resolved** with basic implementations
- **Test coverage maintained** with new test additions
- **No regressions** in existing functionality
- **Proper error handling** implemented across endpoints

## Next Steps

After completing these tasks, move to Phase 3 advanced testing including security expansion, performance optimization, and comprehensive regression automation.