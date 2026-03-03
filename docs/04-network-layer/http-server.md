# HTTP Server

## Overview

The HTTP server is a custom implementation that:
- Listens on port 2583 (configurable)
- Handles HTTP/1.1 requests
- Supports WebSocket upgrades
- Routes requests to XRPC dispatcher
- Implements TLS termination (in production, behind nginx)

## Architecture

### Request Processing Pipeline

```
HTTP Request
    ↓
HttpServer (parse headers/body)
    ↓
Route Matching
    ↓
XRPC Dispatcher (if XRPC endpoint)
    ↓
Authentication (JWT/DPoP)
    ↓
Method Handler
    ↓
Service Layer
    ↓
Response Serialization
    ↓
HTTP Response
```

## Server Initialization

The HTTP server is initialized with a port and optional configuration:

```objc
// Create server instance
HttpServer *server = [HttpServer serverWithPort:2583];

// Start listening
NSError *error = nil;
[server startWithCompletion:^(NSError *startError) {
    if (startError) {
        NSLog(@"Failed to start server: %@", startError);
    } else {
        NSLog(@"Server started on port 2583");
    }
}];
```

**Implementation Details (from HttpServer.m):**

The server manages concurrent connections with a configurable limit:

```objc
static const NSUInteger kMaxConcurrentRequests = 64; // Limit concurrent threads
static const NSUInteger kHttpMaxHeaderBytes = 16 * 1024;
static const NSUInteger kHttpMaxBodyBytes = 50 * 1024 * 1024;
static const NSTimeInterval kHttpHeaderTimeout = 5.0;
```

Connection state tracking:

```objc
@interface HttpConnectionState : NSObject
@property(nonatomic, strong) Http1Parser *parser;
@property(nonatomic, strong) Http1PipelinePolicy *pipelinePolicy;
@property(nonatomic, assign) NSTimeInterval headerStartTime;
@property(nonatomic, assign) BOOL requestInFlight;
@property(nonatomic, strong) NSMutableArray<HttpQueuedResponse *> *outputQueue;
@property(nonatomic, assign) BOOL readingPaused;
@property(nonatomic, assign) NSUInteger outputQueueSize;
@property(nonatomic, strong) NSMutableArray<HttpRequest *> *pendingRequests;
@property(nonatomic, assign) BOOL sendingActive;
@property(nonatomic, assign) BOOL upgradedToWebSocket;
@end
```

## Route Registration

### Registering Routes

Routes are registered with the HTTP server using path patterns and handler blocks. The builder pattern is used to configure all routes:

**Implementation (from PDSHttpServerBuilder.m):**

```objc
- (BOOL)configureServer:(HttpServer *)server error:(NSError **)error {
    if (!server) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSHttpServerBuilderErrorDomain"
                                          code:1
                                      userInfo:@{
                                        NSLocalizedDescriptionKey : @"Server cannot be nil"
                                      }];
        }
        return NO;
    }

    // Register OAuth routes first (specific paths take precedence)
    if (self.enableOAuth) {
        [self registerOAuthRoutesWithServer:server];
    }

    // Register XRPC routes
    if (self.enableXrpc) {
        [self registerXrpcRoutesWithServer:server];
    }

    // Register Explore UI routes
    ExploreHandler *exploreHandler = nil;
    if (self.enableExploreUI) {
        exploreHandler = [self registerExploreRoutesWithServer:server];
    }

    // Register OAuth Demo routes
    if (self.enableOAuthDemo) {
        [self registerOAuthDemoRoutesWithServer:server];
    }

    // Register MST Viewer routes
    if (self.enableMSTViewer) {
        [self registerMSTViewerRoutesWithServer:server];
    }

    // Register NodeInfo routes
    if (self.enableNodeInfo) {
        [self registerNodeInfoRoutesWithServer:server];
    }

    return YES;
}
```

### Route Matching

Routes are matched using a trie-based pattern matching system that supports wildcards:

```objc
// Exact match
HttpRequestHandler handler = self.routes[path];
if (handler) return handler;

// Wildcard match
for (NSString *pattern in self.routes) {
    if ([pattern hasSuffix:@"*"]) {
        NSString *prefix = [pattern substringToIndex:pattern.length - 1];
        if ([path hasPrefix:prefix]) {
            return self.routes[pattern];
        }
    }
}

return nil;
```

## Request Handling

### Parsing Requests

HTTP/1.1 requests are parsed using a state machine parser that handles headers and body separately:

```objc
// In HttpRequest.m
+ (instancetype)parseFromData:(NSData *)data error:(NSError **)error {
    HttpRequest *request = [[HttpRequest alloc] init];
    
    // 1. Parse request line
    NSString *requestStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
    
    NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
    request.method = requestLine[0];
    request.path = requestLine[1];
    request.version = requestLine[2];
    
    // 2. Parse headers
    request.headers = [NSMutableDictionary dictionary];
    NSInteger i = 1;
    while (i < lines.count && ![lines[i] isEqualToString:@""]) {
        NSArray *parts = [lines[i] componentsSeparatedByString:@": "];
        if (parts.count == 2) {
            request.headers[parts[0]] = parts[1];
        }
        i++;
    }
    
    // 3. Parse body
    NSInteger bodyStart = [requestStr rangeOfString:@"\r\n\r\n"].location + 4;
    if (bodyStart < requestStr.length) {
        request.body = [requestStr substringFromIndex:bodyStart];
    }
    
    return request;
}
```

### Building Responses

Responses are serialized with status line, headers, and body:

```objc
// In HttpResponse.m
- (NSData *)serialize {
    NSMutableString *response = [NSMutableString string];
    
    // 1. Status line
    [response appendFormat:@"HTTP/1.1 %ld %@\r\n", 
        (long)self.statusCode, 
        [self statusMessageForCode:self.statusCode]];
    
    // 2. Headers
    [response appendFormat:@"Content-Type: %@\r\n", self.contentType ?: @"application/json"];
    [response appendFormat:@"Content-Length: %lu\r\n", (unsigned long)self.body.length];
    
    for (NSString *key in self.headers) {
        [response appendFormat:@"%@: %@\r\n", key, self.headers[key]];
    }
    
    // 3. Empty line
    [response appendString:@"\r\n"];
    
    // 4. Body
    NSMutableData *data = [[response dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [data appendData:self.body];
    
    return data;
}
```

## WebSocket Support

### WebSocket Upgrade

The HTTP server supports upgrading connections to WebSocket for real-time communication (used by the firehose):

```objc
// In HttpServer.m
- (BOOL)upgradeToWebSocket:(HttpRequest *)request 
                  response:(HttpResponse *)response
                     error:(NSError **)error {
    // 1. Verify upgrade headers
    if (![[request.headers[@"Upgrade"] lowercaseString] isEqualToString:@"websocket"]) {
        *error = [NSError errorWithDomain:@"HTTP" code:1 
            userInfo:@{NSLocalizedDescriptionKey: @"Invalid upgrade header"}];
        return NO;
    }
    
    // 2. Generate Sec-WebSocket-Accept
    NSString *key = request.headers[@"Sec-WebSocket-Key"];
    NSString *magic = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    NSString *combined = [NSString stringWithFormat:@"%@%@", key, magic];
    
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1([combined UTF8String], (CC_LONG)[combined length], hash);
    
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA1_DIGEST_LENGTH];
    NSString *accept = [self base64Encode:hashData];
    
    // 3. Send upgrade response
    response.statusCode = 101;
    response.headers[@"Upgrade"] = @"websocket";
    response.headers[@"Connection"] = @"Upgrade";
    response.headers[@"Sec-WebSocket-Accept"] = accept;
    
    return YES;
}
```

### WebSocket Frame Handling

Once upgraded, frames are parsed and handled according to the WebSocket protocol:

```objc
// In WebSocketConnection.m
- (void)handleFrame:(NSData *)frameData {
    // 1. Parse frame header
    uint8_t *bytes = (uint8_t *)frameData.bytes;
    BOOL fin = (bytes[0] & 0x80) != 0;
    uint8_t opcode = bytes[0] & 0x0F;
    BOOL masked = (bytes[1] & 0x80) != 0;
    
    // 2. Extract payload length
    uint64_t payloadLength = bytes[1] & 0x7F;
    NSUInteger offset = 2;
    
    if (payloadLength == 126) {
        payloadLength = (bytes[offset] << 8) | bytes[offset + 1];
        offset += 2;
    } else if (payloadLength == 127) {
        payloadLength = 0;
        for (int i = 0; i < 8; i++) {
            payloadLength = (payloadLength << 8) | bytes[offset + i];
        }
        offset += 8;
    }
    
    // 3. Extract mask key (if masked)
    uint8_t maskKey[4] = {0};
    if (masked) {
        memcpy(maskKey, &bytes[offset], 4);
        offset += 4;
    }
    
    // 4. Extract payload
    NSData *payload = [frameData subdataWithRange:NSMakeRange(offset, payloadLength)];
    
    // 5. Unmask payload (if masked)
    if (masked) {
        NSMutableData *unmasked = [payload mutableCopy];
        uint8_t *unmaskedBytes = (uint8_t *)unmasked.mutableBytes;
        for (NSUInteger i = 0; i < payloadLength; i++) {
            unmaskedBytes[i] ^= maskKey[i % 4];
        }
        payload = unmasked;
    }
    
    // 6. Handle based on opcode
    switch (opcode) {
        case 0x1:  // Text frame
            [self handleTextFrame:payload];
            break;
        case 0x2:  // Binary frame
            [self handleBinaryFrame:payload];
            break;
        case 0x8:  // Close frame
            [self handleCloseFrame];
            break;
        case 0x9:  // Ping frame
            [self handlePingFrame:payload];
            break;
    }
}
```

## Error Handling

### HTTP Error Responses

```objc
// In HttpServer.m
- (void)sendErrorResponse:(HttpResponse *)response 
                 statusCode:(NSInteger)statusCode
                    message:(NSString *)message {
    response.statusCode = statusCode;
    response.contentType = @"application/json";
    
    NSDictionary *error = @{
        @"error": [self errorCodeForStatus:statusCode],
        @"message": message
    };
    
    response.body = [NSJSONSerialization dataWithJSONObject:error options:0 error:nil];
}
```

### Common Error Codes

| Status | Code | Message |
|--------|------|---------|
| 400 | BadRequest | Invalid request format |
| 401 | Unauthorized | Authentication required |
| 403 | Forbidden | Permission denied |
| 404 | NotFound | Resource not found |
| 409 | Conflict | Resource already exists |
| 500 | InternalServerError | Server error |

## Performance Optimization

### Connection Pooling

```objc
// Reuse connections for keep-alive
response.headers[@"Connection"] = @"keep-alive";
response.headers[@"Keep-Alive"] = @"timeout=60, max=100";
```

### Compression

```objc
// Gzip response body if client supports it
if ([request.headers[@"Accept-Encoding"] containsString:@"gzip"]) {
    NSData *compressed = [self gzipCompress:response.body];
    response.body = compressed;
    response.headers[@"Content-Encoding"] = @"gzip";
}
```

### Caching

```objc
// Set cache headers for static content
response.headers[@"Cache-Control"] = @"public, max-age=3600";
response.headers[@"ETag"] = [self calculateETag:response.body];
```

## See Also

**Basic Topics:**
- [XRPC Dispatch](./xrpc-dispatch.md) — XRPC routing
- [Method Registry](./method-registry.md) — Method registration
- [Authentication](../06-authentication/jwt-tokens.md) — Authentication details

**Advanced Topics:**
- [Rate Limiting](./rate-limiting.md) — Request rate control
- [DoS Protection](./dos-protection.md) — Attack mitigation
- [Request Throttling](./request-throttling.md) — Traffic management
- [Input Validation](./input-validation.md) — Request validation
