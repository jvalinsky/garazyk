# XRPC Dispatch

## Overview

XRPC (ATProto RPC) dispatch is the routing mechanism that directs incoming HTTP requests to the appropriate handler based on the NSID (Namespace Identifier). The dispatcher is the central hub that receives all XRPC requests and routes them to domain-specific method handlers.

## Architecture

```
┌──────────────────────────────────────────┐
│   HTTP Request                           │
│  POST /xrpc/com.atproto.repo.createRecord
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   HttpServer                             │
│  (Route matching)                        │
└────────────────┬─────────────────────────┘
                 │
┌────────────────▼─────────────────────────┐
│   XRPC Dispatcher                        │
│  - Parse NSID from path                  │
│  - Look up handler                       │
│  - Verify authentication                 │
│  - Call handler                          │
└────────────────┬─────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────────┐  ┌──▼──────────────┐
│ Domain Handler   │  │ Auth Verification
│ (e.g., Repo)     │  │ (JWT/DPoP)
└──────────────────┘  └──────────────────┘
        │
        └────────┬────────┘
                 │
        ┌────────▼────────────┐
        │ Service Layer       │
        │ (Business Logic)    │
        └─────────────────────┘
```

## NSID Format

NSIDs (Namespace Identifiers) follow a hierarchical format:

```
com.atproto.repo.createRecord
│    │      │    │
│    │      │    └─ Method name
│    │      └─────── Namespace
│    └────────────── Domain
└─────────────────── Reverse domain
```

Common NSID prefixes:

| Prefix | Purpose |
|--------|---------|
| `com.atproto.server.*` | Account and server operations |
| `com.atproto.repo.*` | Record CRUD operations |
| `com.atproto.sync.*` | Repository synchronization |
| `com.atproto.identity.*` | DID and handle resolution |
| `com.atproto.admin.*` | Administrative operations |
| `com.atproto.label.*` | Labeling operations |
| `app.bsky.*` | Bluesky-specific operations |

## Request Flow

### 1. HTTP Request Reception

```
POST /xrpc/com.atproto.repo.createRecord HTTP/1.1
Host: pds.example.com
Authorization: Bearer <token>
Content-Type: application/json

{
  "repo": "did:plc:user123",
  "collection": "app.bsky.feed.post",
  "record": { "text": "Hello!" }
}
```

### 2. Route Matching

The HTTP server matches the path `/xrpc/*` and routes to the XRPC dispatcher.

### 3. NSID Extraction

The dispatcher extracts the NSID from the path:

```
/xrpc/com.atproto.repo.createRecord
      └─ NSID: com.atproto.repo.createRecord
```

### 4. Handler Lookup

The dispatcher looks up the handler for the NSID in the method registry:

```objc
XrpcHandler handler = [registry handlerForNSID:@"com.atproto.repo.createRecord"];
```

### 5. Authentication Verification

If the endpoint requires authentication, the dispatcher verifies the Authorization header:

```objc
NSString *authHeader = [request headerForName:@"Authorization"];
NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                              jwtMinter:jwtMinter
                                        adminController:adminController
                                                request:request];
```

### 6. Handler Invocation

The dispatcher calls the handler with the request and response:

```objc
handler(request, response);
```

### 7. Response Serialization

The handler populates the response with:
- HTTP status code
- Response headers
- Response body (JSON or binary)

### 8. HTTP Response Transmission

The HTTP server sends the response back to the client.

## Handler Registration

Handlers are registered with the dispatcher during initialization:

```objc
[dispatcher registerHandler:^(HttpRequest *request, HttpResponse *response) {
    // Handle request
} forNSID:@"com.atproto.repo.createRecord"];
```

## Error Handling

### Authentication Errors

If authentication fails:

```
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{
  "error": "AuthRequired",
  "message": "Authentication required"
}
```

### Not Found Errors

If the NSID is not registered:

```
HTTP/1.1 404 Not Found
Content-Type: application/json

{
  "error": "MethodNotFound",
  "message": "Method not found: com.atproto.repo.unknownMethod"
}
```

### Validation Errors

If the request is invalid:

```
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "InvalidRequest",
  "message": "Missing required parameter: repo"
}
```

## Common Patterns

### Implementing a Simple Handler

```objc
[dispatcher registerHandler:^(HttpRequest *request, HttpResponse *response) {
    // 1. Extract authentication
    NSString *authHeader = [request headerForName:@"Authorization"];
    NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                  jwtMinter:jwtMinter
                                            adminController:adminController
                                                    request:request];
    
    if (!did) {
        [XrpcErrorHelper setAuthenticationError:response];
        return;
    }
    
    // 2. Parse request body
    NSError *parseError = nil;
    NSDictionary *params = [NSJSONSerialization JSONObjectWithData:request.body
                                                            options:0
                                                              error:&parseError];
    
    if (!params) {
        [XrpcErrorHelper setValidationError:response message:@"Invalid JSON"];
        return;
    }
    
    // 3. Validate parameters
    NSString *repo = params[@"repo"];
    if (!repo) {
        [XrpcErrorHelper setValidationError:response message:@"Missing repo parameter"];
        return;
    }
    
    // 4. Call service layer
    NSError *serviceError = nil;
    NSDictionary *result = [recordService createRecord:repo
                                            collection:params[@"collection"]
                                                 value:params[@"record"]
                                                 error:&serviceError];
    
    if (!result) {
        [XrpcErrorHelper setInternalServerError:response message:serviceError.localizedDescription];
        return;
    }
    
    // 5. Serialize response
    NSData *responseData = [NSJSONSerialization dataWithJSONObject:result
                                                           options:0
                                                             error:nil];
    
    response.statusCode = 200;
    response.body = responseData;
    [response setHeaderValue:@"application/json" forName:@"Content-Type"];
    
} forNSID:@"com.atproto.repo.createRecord"];
```

### Handling Optional Authentication

Some endpoints allow both authenticated and unauthenticated access:

```objc
[dispatcher registerHandler:^(HttpRequest *request, HttpResponse *response) {
    // 1. Try to extract authentication (optional)
    NSString *authHeader = [request headerForName:@"Authorization"];
    NSString *did = nil;
    
    if (authHeader) {
        did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                            jwtMinter:jwtMinter
                                      adminController:adminController
                                              request:request];
    }
    
    // 2. Proceed with or without authentication
    NSError *error = nil;
    NSDictionary *result = [recordService getRecord:params[@"uri"]
                                          forDid:did
                                           error:&error];
    
    // ... serialize response
    
} forNSID:@"com.atproto.repo.getRecord"];
```

### Handling Different HTTP Methods

```objc
[dispatcher registerHandler:^(HttpRequest *request, HttpResponse *response) {
    if ([request.method isEqualToString:@"GET"]) {
        // Handle GET
    } else if ([request.method isEqualToString:@"POST"]) {
        // Handle POST
    } else {
        [XrpcErrorHelper setMethodNotAllowedError:response
                                    allowedMethod:@"GET, POST"];
    }
} forNSID:@"com.atproto.repo.listRecords"];
```

## Performance Considerations

### Handler Lookup

Handler lookup is O(1) using a hash table:

```objc
@property (nonatomic, strong) NSMutableDictionary<NSString *, XrpcHandler> *handlers;
```

### Request Parsing

Request parsing is done once and cached:

```objc
@property (nonatomic, strong, nullable) NSDictionary *parsedBody;
```

### Response Buffering

Responses are buffered before transmission to allow setting headers:

```objc
@property (nonatomic, strong) NSMutableData *body;
```

## Best Practices

1. **Handler Organization**
   - Group related handlers by domain
   - Use domain-specific handler classes
   - Delegate to service layer

2. **Error Handling**
   - Always set appropriate HTTP status codes
   - Use standardized error codes
   - Include helpful error messages

3. **Authentication**
   - Verify authentication early
   - Use XrpcAuthHelper for consistency
   - Handle DPoP nonce challenges

4. **Validation**
   - Validate all required parameters
   - Check parameter types
   - Provide clear validation errors

5. **Performance**
   - Minimize handler complexity
   - Delegate to service layer
   - Use async operations for long-running tasks

## See Also

- [Method Registry](./method-registry.md)
- [Domain Methods](./domain-methods.md)
- [Auth Helpers](./auth-helpers.md)
- [Error Handling](./error-handling.md)
- [HTTP Server](./http-server.md)
