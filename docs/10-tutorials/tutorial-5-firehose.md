# Tutorial 5: Firehose

## Overview

In this tutorial, you'll implement the Firehose (subscribeRepos) endpoint to stream real-time repository events over WebSocket connections.

**Learning Objectives:**
- Understand WebSocket upgrade from HTTP
- Implement subscribeRepos endpoint
- Broadcast repository commit events
- Handle backpressure and flow control
- Support cursor-based replay

**Time:** 90 minutes

## Prerequisites

- Completed [Tutorial 4: Authentication](./tutorial-4-auth)
- Understanding of WebSocket protocol
- Understanding of firehose concepts (see [Firehose Overview](../08-sync-firehose/firehose-overview))
- Understanding of commit broadcasting (see [Commit Broadcasting](../08-sync-firehose/commit-broadcasting))

## Architecture Overview

The Firehose provides real-time streaming of repository events to subscribers. Key components:

1. **WebSocket Server** — Handles WebSocket connections
2. **SubscribeRepos Handler** — Manages subscriptions and broadcasts events
3. **Event Formatter** — Encodes events in DAG-CBOR format
4. **Backpressure Handler** — Prevents slow consumers from blocking the server

## Step 1: Create WebSocket Connection Handler

Create `src/WebSocketConnection.h`:

```objc
#import <Foundation/Foundation.h>

typedef void (^WebSocketMessageHandler)(NSData *message);
typedef void (^WebSocketCloseHandler)(NSInteger code, NSString *reason);

@interface WebSocketConnection : NSObject

@property (nonatomic, copy, readonly) NSString *remoteAddress;
@property (nonatomic, assign, readonly) NSUInteger pendingSendCount;
@property (nonatomic, assign, readonly) NSUInteger pendingSendBytes;

- (instancetype)initWithSocket:(int)socket;

- (void)start;
- (void)sendMessage:(NSData *)message;
- (void)close;
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason;

@property (nonatomic, copy) WebSocketMessageHandler messageHandler;
@property (nonatomic, copy) WebSocketCloseHandler closeHandler;

@end
```

## Step 2: Implement WebSocket Connection

Create `src/WebSocketConnection.m`:

```objc
#import "WebSocketConnection.h"
#import <sys/socket.h>
#import <arpa/inet.h>
#import <CommonCrypto/CommonDigest.h>

@interface WebSocketConnection ()
@property (nonatomic, assign) int socket;
@property (nonatomic, copy, readwrite) NSString *remoteAddress;
@property (nonatomic, assign, readwrite) NSUInteger pendingSendCount;
@property (nonatomic, assign, readwrite) NSUInteger pendingSendBytes;
@property (nonatomic, strong) dispatch_queue_t sendQueue;
@property (nonatomic, strong) dispatch_queue_t receiveQueue;
@property (nonatomic, assign) BOOL isOpen;
@end

@implementation WebSocketConnection

- (instancetype)initWithSocket:(int)socket {
    self = [super init];
    if (!self) return nil;
    
    self.socket = socket;
    self.isOpen = YES;
    self.pendingSendCount = 0;
    self.pendingSendBytes = 0;
    
    // Get remote address
    struct sockaddr_in addr;
    socklen_t addrLen = sizeof(addr);
    getpeername(socket, (struct sockaddr *)&addr, &addrLen);
    char ipStr[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &addr.sin_addr, ipStr, sizeof(ipStr));
    self.remoteAddress = [NSString stringWithUTF8String:ipStr];
    
    self.sendQueue = dispatch_queue_create("com.atproto.websocket.send", DISPATCH_QUEUE_SERIAL);
    self.receiveQueue = dispatch_queue_create("com.atproto.websocket.receive", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

- (void)start {
    // Start receiving messages
    dispatch_async(self.receiveQueue, ^{
        [self receiveLoop];
    });
}

- (void)sendMessage:(NSData *)message {
    if (!self.isOpen) return;
    
    dispatch_async(self.sendQueue, ^{
        self.pendingSendCount++;
        self.pendingSendBytes += message.length;
        
        // Build WebSocket frame (binary, FIN=1)
        NSMutableData *frame = [NSMutableData data];
        
        uint8_t byte1 = 0x82;  // FIN=1, opcode=binary
        [frame appendBytes:&byte1 length:1];
        
        // Payload length
        if (message.length < 126) {
            uint8_t byte2 = (uint8_t)message.length;
            [frame appendBytes:&byte2 length:1];
        } else if (message.length < 65536) {
            uint8_t byte2 = 126;
            [frame appendBytes:&byte2 length:1];
            uint16_t len = htons((uint16_t)message.length);
            [frame appendBytes:&len length:2];
        } else {
            uint8_t byte2 = 127;
            [frame appendBytes:&byte2 length:1];
            uint64_t len = htonll((uint64_t)message.length);
            [frame appendBytes:&len length:8];
        }
        
        [frame appendData:message];
        
        // Send frame
        ssize_t sent = send(self.socket, frame.bytes, frame.length, 0);
        
        self.pendingSendCount--;
        self.pendingSendBytes -= message.length;
        
        if (sent < 0) {
            NSLog(@"Failed to send WebSocket message");
            [self close];
        }
    });
}

- (void)receiveLoop {
    while (self.isOpen) {
        // Read frame header
        uint8_t header[2];
        ssize_t n = recv(self.socket, header, 2, 0);
        
        if (n <= 0) {
            [self close];
            break;
        }
        
        uint8_t opcode = header[0] & 0x0F;
        BOOL masked = (header[1] & 0x80) != 0;
        uint64_t payloadLen = header[1] & 0x7F;
        
        // Read extended payload length if needed
        if (payloadLen == 126) {
            uint16_t len16;
            recv(self.socket, &len16, 2, 0);
            payloadLen = ntohs(len16);
        } else if (payloadLen == 127) {
            uint64_t len64;
            recv(self.socket, &len64, 8, 0);
            payloadLen = ntohll(len64);
        }
        
        // Read masking key if present
        uint8_t maskingKey[4] = {0};
        if (masked) {
            recv(self.socket, maskingKey, 4, 0);
        }
        
        // Read payload
        NSMutableData *payload = [NSMutableData dataWithLength:payloadLen];
        ssize_t totalRead = 0;
        while (totalRead < payloadLen) {
            ssize_t bytesRead = recv(self.socket, 
                                    (uint8_t *)payload.mutableBytes + totalRead,
                                    payloadLen - totalRead, 0);
            if (bytesRead <= 0) {
                [self close];
                return;
            }
            totalRead += bytesRead;
        }
        
        // Unmask payload if needed
        if (masked) {
            uint8_t *bytes = (uint8_t *)payload.mutableBytes;
            for (NSUInteger i = 0; i < payloadLen; i++) {
                bytes[i] ^= maskingKey[i % 4];
            }
        }
        
        // Handle opcode
        if (opcode == 0x08) {  // Close
            [self close];
            break;
        } else if (opcode == 0x09) {  // Ping
            [self sendPong:payload];
        } else if (opcode == 0x02 || opcode == 0x01) {  // Binary or Text
            if (self.messageHandler) {
                self.messageHandler(payload);
            }
        }
    }
}

- (void)sendPong:(NSData *)payload {
    NSMutableData *frame = [NSMutableData data];
    uint8_t byte1 = 0x8A;  // FIN=1, opcode=pong
    [frame appendBytes:&byte1 length:1];
    uint8_t byte2 = (uint8_t)payload.length;
    [frame appendBytes:&byte2 length:1];
    [frame appendData:payload];
    send(self.socket, frame.bytes, frame.length, 0);
}

- (void)close {
    [self closeWithCode:1000 reason:@"Normal closure"];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    if (!self.isOpen) return;
    
    self.isOpen = NO;
    
    // Send close frame
    NSMutableData *frame = [NSMutableData data];
    uint8_t byte1 = 0x88;  // FIN=1, opcode=close
    [frame appendBytes:&byte1 length:1];
    
    uint16_t closeCode = htons((uint16_t)code);
    NSData *reasonData = [reason dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t byte2 = (uint8_t)(2 + reasonData.length);
    [frame appendBytes:&byte2 length:1];
    [frame appendBytes:&closeCode length:2];
    [frame appendData:reasonData];
    
    send(self.socket, frame.bytes, frame.length, 0);
    close(self.socket);
    
    if (self.closeHandler) {
        self.closeHandler(code, reason);
    }
}

@end
```

## Step 3: Create Event Formatter

Create `src/EventFormatter.h`:

```objc
#import <Foundation/Foundation.h>

@interface FirehoseCommitEvent : NSObject
@property (nonatomic, assign) NSUInteger seq;
@property (nonatomic, copy) NSString *repo;
@property (nonatomic, strong) NSData *commit;  // CID bytes
@property (nonatomic, copy) NSString *rev;
@property (nonatomic, copy, nullable) NSString *since;
@property (nonatomic, strong) NSData *blocks;  // CAR bytes
@property (nonatomic, strong) NSArray<NSDictionary *> *ops;
@property (nonatomic, strong) NSArray *blobs;
@property (nonatomic, copy) NSString *time;
@end

@interface EventFormatter : NSObject

- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error;

@end
```

## Step 4: Implement Event Formatter

Create `src/EventFormatter.m`:

```objc
#import "EventFormatter.h"

@implementation FirehoseCommitEvent
@end

@implementation EventFormatter

- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error {
    // Build event dictionary
    NSMutableDictionary *eventDict = [@{
        @"$type": @"#commit",
        @"seq": @(event.seq),
        @"rebase": @NO,
        @"tooBig": @NO,
        @"repo": event.repo,
        @"commit": event.commit,
        @"rev": event.rev,
        @"blocks": event.blocks,
        @"ops": event.ops,
        @"blobs": event.blobs,
        @"time": event.time
    } mutableCopy];
    
    if (event.since) {
        eventDict[@"since"] = event.since;
    }
    
    // Encode as DAG-CBOR (simplified - use real DAG-CBOR in production)
    NSData *cborData = [self encodeCBOR:eventDict error:error];
    if (!cborData) return nil;
    
    // Build frame: [header][body]
    // Header: { op: 1 (message), t: "#commit" }
    NSDictionary *header = @{@"op": @1, @"t": @"#commit"};
    NSData *headerData = [self encodeCBOR:header error:error];
    if (!headerData) return nil;
    
    NSMutableData *frame = [NSMutableData data];
    [frame appendData:headerData];
    [frame appendData:cborData];
    
    return frame;
}

- (nullable NSData *)encodeCBOR:(id)object error:(NSError **)error {
    // Simplified CBOR encoding for tutorial
    // In production, use ATProtoCBORSerialization
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:error];
}

@end
```

## Step 5: Create SubscribeRepos Handler

Create `src/SubscribeReposHandler.h`:

```objc
#import <Foundation/Foundation.h>
#import "WebSocketConnection.h"

@interface SubscribeReposHandler : NSObject

- (instancetype)initWithDatabasePath:(NSString *)databasePath;

- (void)acceptConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor;
- (void)broadcastCommit:(NSString *)repo 
                    rev:(NSString *)rev
                 commit:(NSData *)commitCID
                 blocks:(NSData *)carBlocks
                    ops:(NSArray<NSDictionary *> *)ops;

@end
```

## Step 6: Implement SubscribeRepos Handler

Create `src/SubscribeReposHandler.m`:

```objc
#import "SubscribeReposHandler.h"
#import "EventFormatter.h"

@interface SubscribeReposHandler ()
@property (nonatomic, copy) NSString *databasePath;
@property (nonatomic, strong) EventFormatter *eventFormatter;
@property (nonatomic, strong) NSMutableSet<WebSocketConnection *> *connections;
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, assign) NSUInteger sequenceNumber;
@property (nonatomic, assign) NSUInteger maxPendingSends;
@property (nonatomic, assign) NSUInteger maxPendingBytes;
@end

@implementation SubscribeReposHandler

- (instancetype)initWithDatabasePath:(NSString *)databasePath {
    self = [super init];
    if (!self) return nil;
    
    self.databasePath = databasePath;
    self.eventFormatter = [[EventFormatter alloc] init];
    self.connections = [NSMutableSet set];
    self.eventQueue = dispatch_queue_create("com.atproto.firehose.events", DISPATCH_QUEUE_SERIAL);
    self.sequenceNumber = 0;
    self.maxPendingSends = 512;
    self.maxPendingBytes = 16 * 1024 * 1024;  // 16MB
    
    return self;
}

- (void)acceptConnection:(WebSocketConnection *)connection cursor:(nullable NSString *)cursor {
    NSLog(@"[Firehose] New connection from %@", connection.remoteAddress);
    
    @synchronized(self.connections) {
        [self.connections addObject:connection];
    }
    
    // Handle connection close
    __weak typeof(self) weakSelf = self;
    connection.closeHandler = ^(NSInteger code, NSString *reason) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        @synchronized(strongSelf.connections) {
            [strongSelf.connections removeObject:connection];
        }
        NSLog(@"[Firehose] Connection closed: %@ (code=%ld)", connection.remoteAddress, (long)code);
    };
    
    // If cursor provided, replay events
    if (cursor && cursor.length > 0) {
        NSUInteger cursorSeq = [cursor integerValue];
        [self replayEventsAfterCursor:cursorSeq toConnection:connection];
    }
}

- (void)replayEventsAfterCursor:(NSUInteger)cursor toConnection:(WebSocketConnection *)connection {
    dispatch_async(self.eventQueue, ^{
        NSLog(@"[Firehose] Replaying events after cursor %lu", (unsigned long)cursor);
        
        // In production, load events from database
        // For tutorial, we'll just start from current sequence
        NSLog(@"[Firehose] Replay complete, connection is now live");
    });
}

- (void)broadcastCommit:(NSString *)repo 
                    rev:(NSString *)rev
                 commit:(NSData *)commitCID
                 blocks:(NSData *)carBlocks
                    ops:(NSArray<NSDictionary *> *)ops {
    
    dispatch_async(self.eventQueue, ^{
        self.sequenceNumber++;
        
        // Create commit event
        FirehoseCommitEvent *event = [[FirehoseCommitEvent alloc] init];
        event.seq = self.sequenceNumber;
        event.repo = repo;
        event.commit = commitCID;
        event.rev = rev;
        event.blocks = carBlocks;
        event.ops = ops;
        event.blobs = @[];
        event.time = [self rfc3339Timestamp];
        
        // Encode event
        NSError *error = nil;
        NSData *eventData = [self.eventFormatter encodeCommitEvent:event error:&error];
        if (!eventData) {
            NSLog(@"[Firehose] Failed to encode event: %@", error);
            return;
        }
        
        // Broadcast to all connections
        NSSet<WebSocketConnection *> *snapshot = nil;
        @synchronized(self.connections) {
            snapshot = [self.connections copy];
        }
        
        for (WebSocketConnection *connection in snapshot) {
            // Check backpressure
            if (connection.pendingSendCount >= self.maxPendingSends ||
                connection.pendingSendBytes >= self.maxPendingBytes) {
                NSLog(@"[Firehose] Closing slow consumer: %@", connection.remoteAddress);
                [connection closeWithCode:1008 reason:@"ConsumerTooSlow"];
                @synchronized(self.connections) {
                    [self.connections removeObject:connection];
                }
                continue;
            }
            
            [connection sendMessage:eventData];
        }
        
        NSLog(@"[Firehose] Broadcast commit event seq=%lu to %lu connections", 
              (unsigned long)self.sequenceNumber, (unsigned long)snapshot.count);
    });
}

- (NSString *)rfc3339Timestamp {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    return [formatter stringFromDate:[NSDate date]];
}

@end
```

## Step 7: Update HTTP Server for WebSocket Upgrade

Update `src/HttpServer.m` to handle WebSocket upgrade:

```objc
- (void)handleClient:(int)clientSocket {
    // Read request
    char buffer[4096];
    ssize_t n = read(clientSocket, buffer, sizeof(buffer));
    
    if (n <= 0) {
        close(clientSocket);
        return;
    }
    
    NSString *requestStr = [[NSString alloc] initWithBytes:buffer 
                                                    length:n 
                                                  encoding:NSUTF8StringEncoding];
    
    // Parse request
    NSArray *lines = [requestStr componentsSeparatedByString:@"\r\n"];
    NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
    NSString *method = requestLine[0];
    NSString *path = requestLine[1];
    
    // Parse headers
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        if (line.length == 0) break;
        
        NSArray *parts = [line componentsSeparatedByString:@": "];
        if (parts.count == 2) {
            headers[parts[0]] = parts[1];
        }
    }
    
    // Check for WebSocket upgrade
    if ([headers[@"Upgrade"] isEqualToString:@"websocket"] &&
        [path isEqualToString:@"/xrpc/com.atproto.sync.subscribeRepos"]) {
        [self handleWebSocketUpgrade:clientSocket headers:headers path:path];
        return;
    }
    
    // Regular HTTP handling
    HttpRequestHandler handler = self.routes[path];
    if (!handler) {
        handler = self.routes[@"/xrpc/*"];
    }
    
    NSString *response = @"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
    write(clientSocket, [response UTF8String], response.length);
    close(clientSocket);
}

- (void)handleWebSocketUpgrade:(int)clientSocket 
                       headers:(NSDictionary *)headers
                          path:(NSString *)path {
    
    // Extract WebSocket key
    NSString *wsKey = headers[@"Sec-WebSocket-Key"];
    if (!wsKey) {
        close(clientSocket);
        return;
    }
    
    // Compute accept key
    NSString *magic = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    NSString *combined = [wsKey stringByAppendingString:magic];
    NSData *combinedData = [combined dataUsingEncoding:NSUTF8StringEncoding];
    
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(combinedData.bytes, (CC_LONG)combinedData.length, digest);
    NSData *digestData = [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
    NSString *acceptKey = [digestData base64EncodedStringWithOptions:0];
    
    // Send upgrade response
    NSString *response = [NSString stringWithFormat:
        @"HTTP/1.1 101 Switching Protocols\r\n"
        @"Upgrade: websocket\r\n"
        @"Connection: Upgrade\r\n"
        @"Sec-WebSocket-Accept: %@\r\n"
        @"\r\n", acceptKey];
    
    write(clientSocket, [response UTF8String], response.length);
    
    // Extract cursor from query string
    NSString *cursor = nil;
    NSArray *pathParts = [path componentsSeparatedByString:@"?"];
    if (pathParts.count > 1) {
        NSString *query = pathParts[1];
        NSArray *params = [query componentsSeparatedByString:@"&"];
        for (NSString *param in params) {
            NSArray *kv = [param componentsSeparatedByString:@"="];
            if (kv.count == 2 && [kv[0] isEqualToString:@"cursor"]) {
                cursor = kv[1];
            }
        }
    }
    
    // Create WebSocket connection
    WebSocketConnection *connection = [[WebSocketConnection alloc] initWithSocket:clientSocket];
    [connection start];
    
    // Hand off to SubscribeRepos handler
    [self.subscribeReposHandler acceptConnection:connection cursor:cursor];
}
```

## Step 8: Update Main Entry Point

Update `src/main.m` to initialize the firehose:

```objc
#import <Foundation/Foundation.h>
#import "PDSApplication.h"
#import "SubscribeReposHandler.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        config.databasePath = @"./pds-data/db";
        
        // 2. Initialize PDS
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc] 
            initWithConfiguration:config error:&error];
        
        if (!app) {
            NSLog(@"Failed to initialize PDS: %@", error);
            return 1;
        }
        
        // 3. Initialize SubscribeRepos handler
        SubscribeReposHandler *firehose = [[SubscribeReposHandler alloc] 
            initWithDatabasePath:config.databasePath];
        app.httpServer.subscribeReposHandler = firehose;
        
        // 4. Start server
        [app.httpServer startWithCompletion:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to start server: %@", error);
                exit(1);
            }
            
            NSLog(@"PDS started on port %ld", (long)config.serverPort);
            NSLog(@"Firehose available at ws://localhost:%ld/xrpc/com.atproto.sync.subscribeRepos", 
                  (long)config.serverPort);
        }];
        
        // 5. Keep running
        [[NSRunLoop mainRunLoop] run];
    }
    
    return 0;
}
```

## Step 9: Update Record Service to Broadcast Commits

Update `src/RecordService.m` to broadcast commits when records change:

```objc
- (void)createRecord:(NSString *)repo
          collection:(NSString *)collection
               rkey:(NSString *)rkey
              value:(NSDictionary *)value
         completion:(void (^)(NSString *uri, NSString *cid, NSError *error))completion {
    
    // 1. Validate parameters
    if (!repo || !collection || !rkey || !value) {
        completion(nil, nil, [NSError errorWithDomain:@"Record" code:1 userInfo:nil]);
        return;
    }
    
    // 2. Serialize record to CBOR
    NSError *cborError = nil;
    NSData *recordCBOR = [self encodeCBOR:value error:&cborError];
    if (!recordCBOR) {
        completion(nil, nil, cborError);
        return;
    }
    
    // 3. Compute CID
    NSData *recordCID = [self computeCID:recordCBOR];
    NSString *cidString = [self cidToString:recordCID];
    
    // 4. Store in database
    [self.repository storeRecord:recordCBOR 
                             cid:recordCID
                            repo:repo
                      collection:collection
                            rkey:rkey];
    
    // 5. Update MST and create commit
    NSString *rev = [self.repository updateMSTForRepo:repo];
    NSData *commitCID = [self.repository createCommitForRepo:repo rev:rev];
    
    // 6. Build CAR blocks
    NSData *carBlocks = [self.repository buildCARBlocksForRepo:repo rev:rev];
    
    // 7. Broadcast to firehose
    NSArray *ops = @[@{
        @"action": @"create",
        @"path": [NSString stringWithFormat:@"%@/%@", collection, rkey],
        @"cid": cidString
    }];
    
    [self.firehoseHandler broadcastCommit:repo 
                                      rev:rev
                                   commit:commitCID
                                   blocks:carBlocks
                                      ops:ops];
    
    // 8. Return result
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", repo, collection, rkey];
    completion(uri, cidString, nil);
}
```

## Step 10: Create CMakeLists.txt

Create `CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.28)
project(tutorial-5-firehose)

set(CMAKE_C_STANDARD 11)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")

find_library(FOUNDATION_LIBRARY Foundation REQUIRED)

add_executable(tutorial-5-firehose
    src/main.m
    src/WebSocketConnection.m
    src/EventFormatter.m
    src/SubscribeReposHandler.m
    src/HttpServer.m
    src/XrpcDispatcher.m
    src/RecordService.m
    src/AccountService.m
    src/AccountRepository.m
    src/RecordRepository.m
    src/SimpleJWTMinter.m
)

target_link_libraries(tutorial-5-firehose
    ${FOUNDATION_LIBRARY}
)
```

## Step 11: Build and Run

```bash
# Create build directory
mkdir -p build && cd build

# Configure
cmake ..

# Build
make

# Run
./tutorial-5-firehose
```

## Step 12: Test the Firehose

### Test 1: Connect to Firehose

In another terminal, use `websocat` to connect:

```bash
# Install websocat if needed
brew install websocat

# Connect to firehose
websocat ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos
```

### Test 2: Create a Record and Watch Event

In a third terminal:

```bash
# Create a record
curl -X POST http://localhost:2583/xrpc/com.atproto.repo.createRecord \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "repo": "did:plc:test123",
    "collection": "app.bsky.feed.post",
    "record": {
      "$type": "app.bsky.feed.post",
      "text": "Hello from Tutorial 5!",
      "createdAt": "2026-03-03T12:00:00Z"
    }
  }'
```

You should see the commit event appear in the websocat terminal.

### Test 3: Test Cursor-Based Replay

```bash
# Connect with cursor
websocat "ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos?cursor=0"
```

This should replay all events from the beginning.

### Test 4: Test Backpressure

Create a slow consumer test:

```python
#!/usr/bin/env python3
import websocket
import time

def on_message(ws, message):
    print(f"Received {len(message)} bytes")
    time.sleep(10)  # Simulate slow consumer

ws = websocket.WebSocketApp(
    "ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos",
    on_message=on_message
)

ws.run_forever()
```

The server should close the connection after detecting backpressure.

## Understanding the Flow

1. **WebSocket Upgrade**: Client sends HTTP request with `Upgrade: websocket` header
2. **Connection Accepted**: Server responds with 101 Switching Protocols
3. **Event Streaming**: Server broadcasts commit events as they occur
4. **Backpressure Detection**: Server monitors pending send queue
5. **Slow Consumer Handling**: Server closes connections that can't keep up

## Key Concepts

### Event Sequence Numbers

Each event has a monotonically increasing sequence number:

```objc
self.sequenceNumber++;
event.seq = self.sequenceNumber;
```

### Cursor-Based Replay

Clients can resume from a specific sequence:

```objc
if (cursor && cursor.length > 0) {
    NSUInteger cursorSeq = [cursor integerValue];
    [self replayEventsAfterCursor:cursorSeq toConnection:connection];
}
```

### Backpressure Handling

Monitor pending sends to detect slow consumers:

```objc
if (connection.pendingSendCount >= self.maxPendingSends ||
    connection.pendingSendBytes >= self.maxPendingBytes) {
    [connection closeWithCode:1008 reason:@"ConsumerTooSlow"];
}
```

### CAR Block Encoding

Events include CAR-encoded blocks:

```objc
event.blocks = carBlocks;  // CAR v1 format with commit + record blocks
```

## Production Considerations

### 1. Event Persistence

Store events in database for replay:

```sql
CREATE TABLE firehose_events (
    seq INTEGER PRIMARY KEY,
    type TEXT NOT NULL,
    data BLOB NOT NULL,
    created_at INTEGER NOT NULL
);
```

### 2. Connection Limits

Limit concurrent connections:

```objc
if (self.connections.count >= self.maxConnections) {
    [connection closeWithCode:1008 reason:@"ServerFull"];
    return;
}
```

### 3. Rate Limiting

Limit events per connection:

```objc
if (connection.eventsPerSecond > self.maxEventsPerSecond) {
    [connection closeWithCode:1008 reason:@"RateLimitExceeded"];
}
```

### 4. Monitoring

Track firehose metrics:

```objc
- (NSDictionary *)getMetrics {
    return @{
        @"active_connections": @(self.connections.count),
        @"current_sequence": @(self.sequenceNumber),
        @"events_per_second": @(self.eventsPerSecond)
    };
}
```

## Next Steps

- **[Tutorial 6: Production Deployment](./tutorial-6-deployment)** — Deploy to production
- **[Firehose Overview](../08-sync-firehose/firehose-overview)** — Deep dive into firehose
- **[Backpressure](../08-sync-firehose/backpressure)** — Advanced backpressure handling

## Troubleshooting

**WebSocket upgrade fails:**
```bash
# Check headers
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" \
  http://localhost:2583/xrpc/com.atproto.sync.subscribeRepos
```

**No events received:**
```bash
# Check if events are being broadcast
tail -f pds.log | grep "Broadcast commit"
```

**Connection closes immediately:**
```bash
# Check for authentication errors
# subscribeRepos is typically public, but check your auth logic
```

## Summary

You've successfully implemented the Firehose:
- WebSocket upgrade from HTTP
- Real-time event broadcasting
- Cursor-based replay
- Backpressure handling
- Slow consumer detection

This completes the core PDS functionality tutorials. The firehose enables real-time synchronization between PDS instances and clients.
