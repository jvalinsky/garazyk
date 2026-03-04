---
title: "Tutorial 5: Firehose"
---

# Tutorial 5: Firehose

## Overview

In this tutorial, you'll implement the Firehose—the real-time event streaming system that powers the AT Protocol's decentralized social network. The Firehose (formally known as `com.atproto.sync.subscribeRepos`) is how Personal Data Servers broadcast repository changes to the network, enabling features like real-time feeds, notifications, and data synchronization.

By the end of this tutorial, you'll have a working WebSocket-based event streaming system that broadcasts repository commits, handles slow consumers gracefully, and supports cursor-based replay for reliable synchronization.

### What You'll Build

A production-ready Firehose implementation that:
- Upgrades HTTP connections to WebSocket protocol
- Streams repository commit events in real-time
- Encodes events in DAG-CBOR format with CAR blocks
- Detects and handles backpressure from slow consumers
- Supports cursor-based replay for missed events
- Monitors connection health and metrics

This is the most complex tutorial in the series, combining networking, concurrency, protocol encoding, and production reliability patterns. The Firehose is mission-critical infrastructure—if it fails, the entire AT Protocol network loses synchronization.

**Learning Objectives:**
- Understand WebSocket protocol upgrade from HTTP
- Implement bidirectional WebSocket communication
- Broadcast events to multiple concurrent subscribers
- Handle backpressure and flow control
- Implement cursor-based event replay
- Monitor and debug real-time streaming systems

**Estimated Time:** 90-120 minutes

## Prerequisites

Before starting this tutorial, you should have:

- **Completed Tutorials:**
  - [Tutorial 1: Hello PDS](tutorial-1-hello-pds) — HTTP server basics
  - [Tutorial 2: Accounts](tutorial-2-accounts) — Account management
  - [Tutorial 3: Records](tutorial-3-records) — Repository operations
  - [Tutorial 4: Authentication](tutorial-4-auth) — JWT and OAuth

- **Knowledge:**
  - Understanding of WebSocket protocol (handshake, frames, opcodes)
  - Familiarity with concurrent programming (dispatch queues, thread safety)
  - Understanding of backpressure and flow control concepts
  - Basic knowledge of binary protocols and framing

- **Background Reading:**
  - [Firehose Overview](../08-sync-firehose/firehose-overview) — Architecture and design
  - [Commit Broadcasting](../08-sync-firehose/commit-broadcasting) — Event flow
  - [Backpressure](../08-sync-firehose/backpressure) — Flow control strategies
  - [WebSocket Server](../08-sync-firehose/websocket-server) — Implementation details

- **Tools:**
  - `websocat` for WebSocket testing (`brew install websocat`)
  - `curl` for HTTP testing
  - Understanding of network debugging tools

## Architecture Overview

The Firehose is a sophisticated real-time streaming system that sits at the heart of AT Protocol's data synchronization. Understanding its architecture is crucial before diving into implementation.

### System Components

The Firehose consists of four main components working together:

1. **WebSocket Server** — Handles protocol upgrade from HTTP to WebSocket, manages connection lifecycle, and implements the WebSocket framing protocol (RFC 6455)

2. **SubscribeRepos Handler** — The orchestrator that manages active subscriptions, broadcasts events to all connected clients, and enforces backpressure policies

3. **Event Formatter** — Encodes repository commit events into DAG-CBOR format with embedded CAR blocks, following the AT Protocol event schema

4. **Backpressure Handler** — Monitors each connection's send queue and terminates slow consumers before they can impact server performance

### Data Flow

Here's how a repository change flows through the system:

```objc
Record Created → Repository Service → Commit Created → MST Updated
                                           ↓
                                    Firehose Handler
                                           ↓
                        ┌──────────────────┼──────────────────┐
                        ↓                  ↓                  ↓
                  Connection 1       Connection 2       Connection 3
                  (Fast consumer)    (Normal)           (Slow - dropped)
```objc

When a record is created, updated, or deleted:
1. The Repository Service creates a new commit
2. The commit is passed to the Firehose Handler
3. The handler encodes the event with all necessary blocks
4. The event is broadcast to all active WebSocket connections
5. Slow consumers are detected and disconnected

### Why WebSocket?

The Firehose uses WebSocket instead of HTTP polling or Server-Sent Events (SSE) for several critical reasons:

**Bidirectional Communication**: While the Firehose primarily streams server-to-client, WebSocket's bidirectional nature allows clients to send control messages (like cursor updates) without establishing new connections.

**Low Latency**: WebSocket maintains a persistent connection, eliminating the overhead of HTTP request/response cycles. Events can be delivered in milliseconds.

**Efficient Framing**: WebSocket's binary framing protocol is more efficient than HTTP chunked encoding, reducing bandwidth and CPU overhead.

**Backpressure Visibility**: WebSocket's send buffer provides visibility into client consumption rates, enabling the server to detect and handle slow consumers.

### Event Sequence Numbers

Every event has a monotonically increasing sequence number (cursor). This enables:
- **Reliable Replay**: Clients can resume from their last received event
- **Gap Detection**: Clients can detect if they've missed events
- **Ordering Guarantees**: Events are delivered in the order they occurred

### Production Considerations

In production, the Firehose must handle:
- **Thousands of concurrent connections** (typical PDS: 100-1000, relay: 10,000+)
- **High event rates** (busy PDS: 10-100 events/second)
- **Slow consumers** (mobile clients on poor networks)
- **Connection churn** (clients connecting/disconnecting frequently)
- **Event persistence** (storing events for replay)

This tutorial implements all the core patterns you'll need for production deployment.

## Step 1: Create WebSocket Connection Handler

The WebSocket connection handler is the foundation of our Firehose. It manages the lifecycle of a single WebSocket connection, handling the low-level protocol details so the Firehose handler can focus on business logic.

### Understanding WebSocket Connections

WebSocket is a protocol that provides full-duplex communication channels over a single TCP connection. Unlike HTTP's request-response model, WebSocket enables true bidirectional communication where both client and server can send messages at any time without waiting for a response.

A WebSocket connection goes through several phases:

1. **HTTP Upgrade**: Client sends HTTP request with `Upgrade: websocket` header
2. **Handshake**: Server responds with 101 Switching Protocols
3. **Frame Exchange**: Binary or text frames flow bidirectionally
4. **Close Handshake**: Either party initiates graceful shutdown

**Why WebSocket for the Firehose?**

The Firehose uses WebSocket instead of alternatives like HTTP polling or Server-Sent Events (SSE) for several critical reasons:

- **Low Latency**: Persistent connection eliminates HTTP request/response overhead. Events can be delivered in milliseconds instead of seconds.
- **Bidirectional**: While primarily server-to-client, WebSocket allows clients to send control messages (cursor updates, subscription filters) without establishing new connections.
- **Efficient Framing**: Binary framing protocol is more efficient than HTTP chunked encoding, reducing bandwidth by 30-50% for small messages.
- **Backpressure Visibility**: WebSocket's send buffer provides visibility into client consumption rates, enabling the server to detect slow consumers before they impact performance.
- **Connection Persistence**: Single long-lived connection is more efficient than thousands of short-lived HTTP requests.

**WebSocket vs HTTP Polling:**

```objc
HTTP Polling (inefficient):
Client → Server: GET /events?since=100
Server → Client: 200 OK []
[wait 1 second]
Client → Server: GET /events?since=100
Server → Client: 200 OK []
[wait 1 second]
Client → Server: GET /events?since=100
Server → Client: 200 OK [event101, event102]

WebSocket (efficient):
Client → Server: Upgrade to WebSocket
Server → Client: 101 Switching Protocols
[connection stays open]
Server → Client: event101
Server → Client: event102
[instant delivery, no polling overhead]
```objc

Our `WebSocketConnection` class encapsulates all of this, providing a clean interface for sending messages and receiving callbacks.

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
```objc

### Interface Design Decisions

**Block-based callbacks** (`WebSocketMessageHandler`, `WebSocketCloseHandler`) provide a clean, modern API. The connection notifies its owner when messages arrive or the connection closes, without requiring delegation protocols.

**Backpressure metrics** (`pendingSendCount`, `pendingSendBytes`) expose the connection's send queue state. This is critical for detecting slow consumers—if these numbers grow unbounded, the client can't keep up.

**Remote address tracking** helps with logging and debugging. When investigating connection issues, knowing which client is affected is essential.

**Separate start method** allows initialization and configuration before beginning I/O operations. This prevents race conditions where messages arrive before handlers are set.

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
```objc

### Understanding the Implementation

This WebSocket implementation handles the complete RFC 6455 protocol. Let's break down the key components:

**Initialization and Address Resolution**

```objc
getpeername(socket, (struct sockaddr *)&addr, &addrLen);
inet_ntop(AF_INET, &addr.sin_addr, ipStr, sizeof(ipStr));
```objc

We extract the remote IP address immediately for logging and debugging. `getpeername()` retrieves the peer's address from the connected socket, and `inet_ntop()` converts it to human-readable form.

**Concurrent I/O with Dispatch Queues**

```objc
self.sendQueue = dispatch_queue_create("com.atproto.websocket.send", DISPATCH_QUEUE_SERIAL);
self.receiveQueue = dispatch_queue_create("com.atproto.websocket.receive", DISPATCH_QUEUE_SERIAL);
```objc

We use separate serial queues for sending and receiving. This provides:
- **Thread safety**: Only one operation at a time per queue
- **Non-blocking**: Send operations don't block receives
- **Backpressure tracking**: Send queue depth indicates client consumption rate

**WebSocket Frame Construction**

The `sendMessage:` method builds RFC 6455-compliant frames:

```objc
uint8_t byte1 = 0x82;  // FIN=1, opcode=binary
```objc

Byte 1 encodes:
- `FIN=1` (bit 7): This is the final fragment
- `RSV1-3=0` (bits 6-4): Reserved, must be 0
- `opcode=0x02` (bits 3-0): Binary frame

```objc
if (message.length < 126) {
    uint8_t byte2 = (uint8_t)message.length;
} else if (message.length < 65536) {
    uint8_t byte2 = 126;
    uint16_t len = htons((uint16_t)message.length);
} else {
    uint8_t byte2 = 127;
    uint64_t len = htonll((uint64_t)message.length);
}
```objc

Byte 2 encodes payload length with three formats:
- **0-125**: Length fits in 7 bits
- **126**: Next 2 bytes contain 16-bit length
- **127**: Next 8 bytes contain 64-bit length

This variable-length encoding minimizes overhead for small messages while supporting large payloads.

**Backpressure Tracking**

```objc
self.pendingSendCount++;
self.pendingSendBytes += message.length;
// ... send ...
self.pendingSendCount--;
self.pendingSendBytes -= message.length;
```objc

We track both the number of pending sends and total bytes. This dual metric helps detect:
- **Many small messages**: High count, low bytes (client processing slowly)
- **Few large messages**: Low count, high bytes (network congestion)

**Receive Loop and Frame Parsing**

The `receiveLoop` method runs continuously on the receive queue, parsing incoming frames:

```objc
uint8_t opcode = header[0] & 0x0F;
BOOL masked = (header[1] & 0x80) != 0;
uint64_t payloadLen = header[1] & 0x7F;
```objc

We extract:
- **Opcode**: Frame type (text, binary, close, ping, pong)
- **Mask bit**: Client-to-server frames must be masked (RFC 6455 requirement)
- **Payload length**: Initial length value (may be extended)

**Masking/Unmasking**

```objc
if (masked) {
    uint8_t *bytes = (uint8_t *)payload.mutableBytes;
    for (NSUInteger i = 0; i < payloadLen; i++) {
        bytes[i] ^= maskingKey[i % 4];
    }
}
```objc

Client-to-server frames are XOR-masked with a 4-byte key. This prevents cache poisoning attacks on intermediary proxies. We unmask by XORing each byte with the corresponding key byte (cycling through the 4-byte key).

**Opcode Handling**

```objc
if (opcode == 0x08) {  // Close
    [self close];
} else if (opcode == 0x09) {  // Ping
    [self sendPong:payload];
} else if (opcode == 0x02 || opcode == 0x01) {  // Binary or Text
    if (self.messageHandler) {
        self.messageHandler(payload);
    }
}
```objc

We handle three opcodes:
- **0x08 (Close)**: Initiate graceful shutdown
- **0x09 (Ping)**: Respond with Pong to keep connection alive
- **0x02/0x01 (Binary/Text)**: Deliver to message handler

**Graceful Shutdown**

```objc
- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    // Send close frame with code and reason
    uint16_t closeCode = htons((uint16_t)code);
    // ...
    send(self.socket, frame.bytes, frame.length, 0);
    close(self.socket);
}
```objc

WebSocket close frames include a status code (1000 = normal, 1008 = policy violation) and optional reason string. This helps clients understand why the connection closed.

### Why This Matters

This WebSocket implementation provides the foundation for reliable, high-performance event streaming. The careful attention to:
- **Protocol compliance** ensures interoperability with all WebSocket clients
- **Backpressure visibility** enables the Firehose to detect slow consumers
- **Concurrent I/O** prevents blocking and maximizes throughput
- **Graceful shutdown** maintains connection hygiene

In production, you might use a library like `libwebsockets` or `SocketRocket`, but understanding the protocol details helps you debug issues and optimize performance.

## Step 3: Create Event Formatter

The Event Formatter is responsible for encoding repository commit events into the wire format expected by Firehose clients. This involves DAG-CBOR encoding and embedding CAR blocks—two of the most important data formats in the AT Protocol.

### Understanding Event Encoding

Firehose events follow a specific structure defined by the AT Protocol. Understanding this structure is crucial for implementing reliable event streaming.

**The Three-Layer Event Structure:**

1. **Frame Header**: Contains operation type and event type (`#commit`, `#identity`, `#account`)
2. **Event Body**: DAG-CBOR encoded event with all necessary data
3. **Embedded Blocks**: CAR-encoded blocks containing the actual commit and record data

This layered encoding enables efficient streaming while maintaining cryptographic verifiability. Clients can verify commits without fetching additional data.

**Why This Layered Approach?**

The three-layer structure serves multiple purposes:

- **Efficient Filtering**: Clients can parse the header without decoding the full body, enabling fast filtering by event type
- **Cryptographic Verification**: Embedded CAR blocks contain all data needed to verify the commit's signature and hash chain
- **Bandwidth Optimization**: Small events (text posts) include all data inline, while large events (images) use the `tooBig` flag
- **Protocol Evolution**: The header can be extended with new fields without breaking existing clients

**Event Flow Through the System:**

```objc
Repository Change
    ↓
Create Commit (MST update, sign with private key)
    ↓
Build CAR Blocks (commit object + changed records)
    ↓
Encode as DAG-CBOR (canonical binary format)
    ↓
Wrap in Frame Header (operation type + event type)
    ↓
Send via WebSocket (binary frame)
    ↓
Client Receives and Verifies (check signature, verify hashes)
```objc

Each step in this flow is critical for maintaining the integrity and verifiability of the AT Protocol's data model.

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
```objc

### Event Structure Explained

**Sequence Number (`seq`)**: Monotonically increasing cursor. Clients use this to resume from disconnections. In production, this must be persisted to survive server restarts.

**Repository DID (`repo`)**: Identifies which user's repository changed. Format: `did:plc:abc123` or `did:web:example.com`.

**Commit CID (`commit`)**: Content-addressed identifier of the commit object. This is the cryptographic hash that makes the commit verifiable.

**Revision (`rev`)**: The TID (timestamp identifier) of this commit. Format: `3jzfcijpj2z2a` (base32-sortable).

**Since (`since`)**: Optional. The previous revision, enabling clients to detect forks or rollbacks.

**Blocks (`blocks`)**: CAR-encoded blocks containing the commit object and any referenced records. This is the actual data payload.

**Operations (`ops`)**: Array describing what changed: `create`, `update`, or `delete` operations with paths and CIDs.

**Blobs (`blobs`)**: Array of blob CIDs if any blobs were added in this commit.

**Timestamp (`time`)**: RFC 3339 timestamp of when the commit occurred.

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
```objc

### Understanding Event Encoding

This implementation demonstrates the Firehose event format, though it uses simplified CBOR encoding for tutorial purposes. Let's examine the key concepts:

**Event Dictionary Structure**

```objc
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
```objc

The `$type` field identifies this as a commit event. Other event types include:
- `#identity`: DID document updates
- `#account`: Account status changes (suspended, deleted)
- `#handle`: Handle changes

**Rebase and TooBig Flags**

```objc
@"rebase": @NO,
@"tooBig": @NO,
```objc

- **rebase**: Indicates the commit history was rewritten (rare, usually due to data corruption recovery)
- **tooBig**: Indicates the commit was too large to include all blocks inline. Clients must fetch blocks separately via `com.atproto.sync.getRepo`.

**Frame Structure**

```objc
NSDictionary *header = @{@"op": @1, @"t": @"#commit"};
NSData *headerData = [self encodeCBOR:header error:error];

NSMutableData *frame = [NSMutableData data];
[frame appendData:headerData];
[frame appendData:cborData];
```objc

Firehose frames consist of two CBOR-encoded parts:
1. **Header**: `{op: 1, t: "#commit"}` where `op: 1` means "message" (vs. `op: -1` for error)
2. **Body**: The actual event data

This two-part structure allows clients to parse the header without decoding the entire body, enabling efficient filtering.

**Production CBOR Encoding**

```objc
// Simplified CBOR encoding for tutorial
// In production, use ATProtoCBORSerialization
return [NSJSONSerialization dataWithJSONObject:object options:0 error:error];
```objc

This tutorial uses JSON as a stand-in for CBOR. In production, you must use proper DAG-CBOR encoding via `ATProtoCBORSerialization`. DAG-CBOR differs from standard CBOR in how it handles CIDs—they're encoded with a special tag (42) that preserves their content-addressing properties.

### Why DAG-CBOR?

DAG-CBOR (Directed Acyclic Graph CBOR) is used instead of JSON because:

1. **Binary Efficiency**: CBOR is more compact than JSON, reducing bandwidth
2. **Canonical Encoding**: DAG-CBOR has a single canonical representation, enabling cryptographic verification
3. **CID Support**: Native support for content-addressed identifiers
4. **Type Preservation**: Distinguishes between binary data and base64 strings

For example, a CID in JSON might be `"bafyreib2rxk3rh6kzwq"` (string), but in DAG-CBOR it's encoded as bytes with tag 42, preserving its binary nature and enabling efficient hashing.

### Event Size Considerations

Firehose events can range from a few hundred bytes (simple text post) to several megabytes (large image with metadata). The `tooBig` flag helps manage this:

```objc
const NSUInteger MAX_EVENT_SIZE = 1 * 1024 * 1024;  // 1MB

if (carBlocks.length > MAX_EVENT_SIZE) {
    event.tooBig = YES;
    event.blocks = [NSData data];  // Empty blocks
}
```objc

When an event is too big, clients must fetch the full repository state via `com.atproto.sync.getRepo` instead of relying on the inline blocks.

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
```objc

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
```objc

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
```objc

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
```objc

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
```objc

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
```objc

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
```objc

## Step 12: Test the Firehose

### Test 1: Connect to Firehose

In another terminal, use `websocat` to connect:

```bash
# Install websocat if needed
brew install websocat

# Connect to firehose
websocat ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos
```objc

## Test 2: Create a Record and Watch Event

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
```objc

You should see the commit event appear in the websocat terminal.

## Test 3: Test Cursor-Based Replay

```bash
# Connect with cursor
websocat "ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos?cursor=0"
```objc

This should replay all events from the beginning.

## Test 4: Test Backpressure

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
```objc

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
```objc

### Cursor-Based Replay

Clients can resume from a specific sequence:

```objc
if (cursor && cursor.length > 0) {
    NSUInteger cursorSeq = [cursor integerValue];
    [self replayEventsAfterCursor:cursorSeq toConnection:connection];
}
```objc

### Backpressure Handling

Monitor pending sends to detect slow consumers:

```objc
if (connection.pendingSendCount >= self.maxPendingSends ||
    connection.pendingSendBytes >= self.maxPendingBytes) {
    [connection closeWithCode:1008 reason:@"ConsumerTooSlow"];
}
```objc

### CAR Block Encoding

Events include CAR-encoded blocks:

```objc
event.blocks = carBlocks;  // CAR v1 format with commit + record blocks
```objc

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
```objc

### 2. Connection Limits

Limit concurrent connections:

```objc
if (self.connections.count >= self.maxConnections) {
    [connection closeWithCode:1008 reason:@"ServerFull"];
    return;
}
```objc

### 3. Rate Limiting

Limit events per connection:

```objc
if (connection.eventsPerSecond > self.maxEventsPerSecond) {
    [connection closeWithCode:1008 reason:@"RateLimitExceeded"];
}
```objc

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
```objc

## Next Steps

- **[Tutorial 6: Production Deployment](tutorial-6-deployment)** — Deploy to production
- **[Firehose Overview](../08-sync-firehose/firehose-overview)** — Deep dive into firehose
- **[Backpressure](../08-sync-firehose/backpressure)** — Advanced backpressure handling

## Understanding Real-Time Sync Concepts

Before diving into troubleshooting, let's explore the deeper concepts that make the Firehose work reliably in production.

### Event Ordering and Causality

The Firehose guarantees that events are delivered in the order they were committed. This is crucial for maintaining consistency across the network.

**Sequence Numbers as Logical Clocks:**

```objc
self.sequenceNumber++;  // Monotonically increasing
event.seq = self.sequenceNumber;
```objc

Each event gets a sequence number that acts as a logical clock. This enables:

- **Total Ordering**: All clients see events in the same order
- **Gap Detection**: If client receives seq=105 after seq=103, it knows it missed seq=104
- **Causality Tracking**: If event A caused event B, A's sequence number is always less than B's

**Why Not Use Timestamps?**

Timestamps seem like a natural choice for ordering, but they have critical flaws:

```objc
// BAD: Using timestamps for ordering
event.timestamp = [[NSDate date] timeIntervalSince1970];

// Problems:
// 1. Clock skew: Server clocks can drift or be adjusted
// 2. Precision: Two events in same millisecond have ambiguous order
// 3. Timezone issues: UTC vs local time confusion
// 4. No gap detection: Missing timestamp doesn't indicate missing event
```objc

Sequence numbers avoid all these issues by providing a single, authoritative source of ordering.

### Backpressure and Flow Control

Backpressure is the mechanism that prevents fast producers from overwhelming slow consumers. Understanding it is essential for building reliable streaming systems.

**The Backpressure Problem:**

```objc
Server (fast producer):     1000 events/second
Client (slow consumer):     10 events/second
Result without backpressure: Server's send buffer grows unbounded → OOM crash
```objc

**Our Solution:**

```objc
if (connection.pendingSendCount >= self.maxPendingSends ||
    connection.pendingSendBytes >= self.maxPendingBytes) {
    [connection closeWithCode:1008 reason:@"ConsumerTooSlow"];
}
```objc

We monitor two metrics:

1. **Pending Send Count**: Number of messages waiting to be sent
   - High count with low bytes = Client processing slowly (CPU-bound)
   - Threshold: 512 messages

2. **Pending Send Bytes**: Total bytes waiting to be sent
   - High bytes with low count = Network congestion (bandwidth-bound)
   - Threshold: 16MB

**Why Close Instead of Throttle?**

You might wonder: why close the connection instead of slowing down the server?

```objc
// Alternative approach (BAD):
if (connection.isSlow) {
    sleep(1);  // Wait for client to catch up
}

// Problems:
// 1. Blocks event queue → all clients suffer
// 2. Slow client holds server resources hostage
// 3. No incentive for client to optimize
```objc

Closing the connection:
- Protects server resources
- Allows fast clients to continue unaffected
- Signals to client that it needs to optimize or upgrade hardware
- Client can reconnect with cursor and catch up at its own pace

**Graceful Degradation:**

Clients should handle disconnections gracefully:

```python
# Client-side pseudocode
while True:
    try:
        connect_to_firehose(cursor=last_cursor)
        for event in stream:
            process(event)
            last_cursor = event.seq
    except ConsumerTooSlow:
        # Optimize processing or upgrade hardware
        optimize_event_processing()
        time.sleep(5)  # Brief backoff
        # Reconnect and resume from cursor
```objc

## Cursor-Based Replay and Reliability

Cursors enable reliable synchronization even in the face of network failures, server restarts, and client crashes.

**The Cursor Contract:**

```objc
// Server promises:
// 1. Events are numbered sequentially starting from 1
// 2. Sequence numbers never decrease or skip
// 3. Events are persisted before broadcasting
// 4. Cursor N means "replay from event N+1 onwards"

if (cursor && cursor.length > 0) {
    NSUInteger cursorSeq = [cursor integerValue];
    [self replayEventsAfterCursor:cursorSeq toConnection:connection];
}
```objc

**Replay Scenarios:**

1. **Normal Reconnection** (cursor=1000, current=1005):
   - Replay events 1001-1005
   - Client is now caught up

2. **Long Disconnection** (cursor=100, current=10000):
   - Too many events to replay efficiently
   - Close with "TooFarBehind" error
   - Client must do full sync via `com.atproto.sync.getRepo`

3. **Future Cursor** (cursor=2000, current=1500):
   - Client's cursor is ahead of server
   - Possible causes: client connected to different server, server data loss
   - Start from current sequence, client will detect gap

**Persistent Event Storage:**

For production reliability, events must be persisted:

```sql
CREATE TABLE firehose_events (
    seq INTEGER PRIMARY KEY,
    type TEXT NOT NULL,           -- 'commit', 'identity', 'account'
    repo TEXT NOT NULL,            -- DID of affected repository
    data BLOB NOT NULL,            -- Encoded event
    created_at INTEGER NOT NULL,   -- Unix timestamp
    INDEX idx_created_at (created_at)
);

-- Retention policy: keep events for 7 days
DELETE FROM firehose_events 
WHERE created_at < unixepoch('now', '-7 days');
```objc

This enables:
- Server restart without losing events
- Replay for clients that were disconnected
- Debugging and auditing of event history
- Disaster recovery

### Connection Lifecycle Management

Understanding the complete lifecycle of a WebSocket connection helps debug issues and optimize performance.

**Phase 1: HTTP Upgrade (0-100ms)**

```objc
Client → Server: GET /xrpc/com.atproto.sync.subscribeRepos HTTP/1.1
                 Upgrade: websocket
                 Connection: Upgrade
                 Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
                 Sec-WebSocket-Version: 13

Server → Client: HTTP/1.1 101 Switching Protocols
                 Upgrade: websocket
                 Connection: Upgrade
                 Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```objc

The `Sec-WebSocket-Accept` is computed as:
```objc
NSString *magic = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
NSString *combined = [wsKey stringByAppendingString:magic];
NSData *sha1 = SHA1(combined);
NSString *acceptKey = Base64Encode(sha1);
```objc

This prevents accidental WebSocket connections from non-WebSocket clients.

**Phase 2: Active Streaming (minutes to hours)**

```objc
Server → Client: [Binary Frame: Event 1001]
Server → Client: [Binary Frame: Event 1002]
Client → Server: [Ping Frame]
Server → Client: [Pong Frame]
Server → Client: [Binary Frame: Event 1003]
...
```objc

During this phase:
- Server broadcasts events as they occur
- Client sends periodic pings to keep connection alive
- Server monitors send queue for backpressure
- Both parties handle network interruptions

**Phase 3: Graceful Shutdown (0-100ms)**

```objc
Server → Client: [Close Frame: code=1000, reason="Normal closure"]
Client → Server: [Close Frame: code=1000]
[TCP FIN/ACK handshake]
```objc

Close codes indicate why the connection ended:
- `1000`: Normal closure (client disconnected)
- `1001`: Going away (server shutting down)
- `1008`: Policy violation (ConsumerTooSlow, RateLimitExceeded)
- `1011`: Internal error (server crash)

**Connection Health Monitoring:**

```objc
@interface WebSocketConnection ()
@property (nonatomic, assign) NSTimeInterval lastPingTime;
@property (nonatomic, assign) NSTimeInterval lastPongTime;
@property (nonatomic, assign) NSUInteger bytesSent;
@property (nonatomic, assign) NSUInteger bytesReceived;
@end

- (BOOL)isHealthy {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval timeSinceLastPong = now - self.lastPongTime;
    
    // No pong in 60 seconds = dead connection
    if (timeSinceLastPong > 60.0) {
        return NO;
    }
    
    // Send rate too low = client not consuming
    if (self.pendingSendCount > self.maxPendingSends) {
        return NO;
    }
    
    return YES;
}
```objc

### Performance Optimization Strategies

Real-world Firehose deployments require careful optimization to handle thousands of concurrent connections.

**1. Zero-Copy Message Broadcasting:**

```objc
// BAD: Copy event data for each connection
for (WebSocketConnection *conn in self.connections) {
    NSData *eventCopy = [eventData copy];  // Unnecessary copy
    [conn sendMessage:eventCopy];
}

// GOOD: Share immutable event data
NSData *sharedEventData = eventData;  // Immutable, can be shared
for (WebSocketConnection *conn in self.connections) {
    [conn sendMessage:sharedEventData];  // No copy needed
}
```objc

This reduces memory allocations from O(N) to O(1) per event, where N is the number of connections.

**2. Batch Event Encoding:**

```objc
// BAD: Encode each event individually
for (Commit *commit in commits) {
    NSData *encoded = [self encodeCommit:commit];
    [self broadcast:encoded];
}

// GOOD: Batch encode when possible
NSArray *encodedEvents = [self batchEncodeCommits:commits];
for (NSData *encoded in encodedEvents) {
    [self broadcast:encoded];
}
```objc

Batch encoding amortizes CBOR encoding overhead across multiple events.

**3. Connection Pooling by Speed:**

```objc
// Separate fast and slow connections
@property (nonatomic, strong) NSMutableSet *fastConnections;
@property (nonatomic, strong) NSMutableSet *slowConnections;

- (void)categorizeConnection:(WebSocketConnection *)conn {
    if (conn.pendingSendCount < 10) {
        [self.fastConnections addObject:conn];
    } else {
        [self.slowConnections addObject:conn];
    }
}

// Broadcast to fast connections first
for (WebSocketConnection *conn in self.fastConnections) {
    [conn sendMessage:eventData];
}
// Then slow connections (may be dropped)
for (WebSocketConnection *conn in self.slowConnections) {
    if ([self shouldDropConnection:conn]) {
        [conn close];
    } else {
        [conn sendMessage:eventData];
    }
}
```objc

This ensures fast clients aren't delayed by slow clients.

**4. Event Compression:**

```objc
// Enable per-message deflate extension
- (void)enableCompression:(WebSocketConnection *)conn {
    // Negotiate during handshake
    // Sec-WebSocket-Extensions: permessage-deflate
    
    // Compress large events
    if (eventData.length > 1024) {
        NSData *compressed = [self compressData:eventData];
        [conn sendCompressedMessage:compressed];
    } else {
        [conn sendMessage:eventData];  // Small events not worth compressing
    }
}
```objc

Compression can reduce bandwidth by 60-80% for text-heavy events.

### Security Considerations

The Firehose is a public endpoint that must be protected against abuse.

**1. Rate Limiting:**

```objc
@interface ConnectionRateLimiter : NSObject
@property (nonatomic, assign) NSUInteger maxConnectionsPerIP;
@property (nonatomic, assign) NSUInteger maxEventsPerSecond;
@end

- (BOOL)shouldAcceptConnection:(NSString *)remoteIP {
    NSUInteger currentConnections = [self countConnectionsFromIP:remoteIP];
    if (currentConnections >= self.maxConnectionsPerIP) {
        NSLog(@"Rate limit: Too many connections from %@", remoteIP);
        return NO;
    }
    return YES;
}
```objc

**2. Authentication (Optional):**

While the Firehose is typically public, you can require authentication:

```objc
- (void)handleWebSocketUpgrade:(int)clientSocket headers:(NSDictionary *)headers {
    // Check for Authorization header
    NSString *authHeader = headers[@"Authorization"];
    if (authHeader) {
        NSString *token = [authHeader stringByReplacingOccurrencesOfString:@"Bearer " withString:@""];
        if (![self validateJWT:token]) {
            [self sendUnauthorizedResponse:clientSocket];
            close(clientSocket);
            return;
        }
    }
    
    // Proceed with upgrade
    [self completeWebSocketUpgrade:clientSocket headers:headers];
}
```objc

**3. DoS Protection:**

```objc
// Limit total concurrent connections
if (self.connections.count >= self.maxTotalConnections) {
    [connection closeWithCode:1008 reason:@"ServerFull"];
    return;
}

// Limit event replay size
const NSUInteger MAX_REPLAY_EVENTS = 10000;
if (eventsToReplay > MAX_REPLAY_EVENTS) {
    [connection closeWithCode:1008 reason:@"TooFarBehind"];
    return;
}

// Limit message size
const NSUInteger MAX_MESSAGE_SIZE = 10 * 1024 * 1024;  // 10MB
if (message.length > MAX_MESSAGE_SIZE) {
    [connection closeWithCode:1009 reason:@"MessageTooBig"];
    return;
}
```objc


## Summary

You've implemented real-time sync via WebSockets, allowing the rest of the network to stream the commits generated by your users.

## Next Steps

- **[Tutorial 6: Deployment](tutorial-6-deployment)** — Prepare the PDS for a live environment
