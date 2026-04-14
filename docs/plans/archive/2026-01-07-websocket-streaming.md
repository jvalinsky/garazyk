---
title: WebSocket Event Streaming Implementation Plan
---

# WebSocket Event Streaming Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement com.atproto.sync.subscribeRepos WebSocket endpoint that streams real-time repository events to clients.

**Architecture:** Create WebSocket server infrastructure integrated with existing PDS controller. Implement event streaming using cursor-based pagination, backfill support, and multiple event types (commit, sync, identity, account, info). Use Objective-C with Foundation networking framework.

**Tech Stack:** Objective-C, Foundation framework, WebSocket protocol, ATProto lexicon types.

## Implementation Overview

The subscribeRepos endpoint provides a WebSocket stream of repository events including:
- `#commit` - Repository state updates with CAR file blocks
- `#sync` - Synchronization events  
- `#identity` - Identity changes
- `#account` - Account status changes
- `#info` - Informational/error messages

Events are streamed with sequence numbers for cursor-based resumption.

---

### Task 1: Create Sync Directory Structure

**Files:**
- Create: `Garazyk/Garazyk/Sync/WebSocketServer.h`
- Create: `Garazyk/Garazyk/Sync/WebSocketServer.m`
- Create: `Garazyk/Garazyk/Sync/WebSocketConnection.h`
- Create: `Garazyk/Garazyk/Sync/WebSocketConnection.m`
- Create: `Garazyk/Garazyk/Sync/EventFormatter.h`
- Create: `Garazyk/Garazyk/Sync/EventFormatter.m`
- Create: `Garazyk/Garazyk/Sync/Firehose.h`
- Create: `Garazyk/Garazyk/Sync/Firehose.m`
- Create: `Garazyk/Garazyk/Sync/RelayClient.h`
- Create: `Garazyk/Garazyk/Sync/RelayClient.m`

**Step 1: Create Sync directory**

```bash
mkdir -p streaming-worktree/Garazyk/Garazyk/Sync
```

**Step 2: Create basic header files with interfaces**

Create WebSocketServer.h with basic WebSocket server interface.

**Step 3: Create basic implementation stubs**

Create .m files with minimal implementations.

**Step 4: Update Makefile**

Add Sync source files to SYNC_SRC variable.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/Sync/ Garazyk/Makefile
git commit -m "feat: create Sync directory structure for WebSocket streaming"
```

---

### Task 2: Implement WebSocket Connection Handling

**Files:**
- Modify: `Garazyk/Garazyk/Sync/WebSocketConnection.h`
- Modify: `Garazyk/Garazyk/Sync/WebSocketConnection.m`

**Step 1: Define WebSocketConnection interface**

```objc
@interface WebSocketConnection : NSObject

@property (nonatomic, readonly) NSString *connectionId;
@property (nonatomic, readonly) NSDictionary *queryParams;

- (instancetype)initWithConnection:(id)connection queryParams:(NSDictionary *)params;
- (void)sendMessage:(NSDictionary *)message;
- (void)close;

@end
```

**Step 2: Implement basic WebSocket connection wrapper**

Implement message sending and connection lifecycle.

**Step 3: Add connection state management**

Track connection open/close states and handle cleanup.

**Step 4: Commit**

```bash
git add Garazyk/Garazyk/Sync/WebSocketConnection.*
git commit -m "feat: implement WebSocket connection handling"
```

---

### Task 3: Implement Event Formatting

**Files:**
- Modify: `Garazyk/Garazyk/Sync/EventFormatter.h`
- Modify: `Garazyk/Garazyk/Sync/EventFormatter.m`

**Step 1: Define event formatter interface**

Methods for formatting different event types (commit, sync, identity, account, info).

**Step 2: Implement commit event formatting**

Format repository commit events with CAR blocks and metadata.

**Step 3: Implement info event formatting**

Format informational messages like OutdatedCursor.

**Step 4: Add sequence numbering**

Ensure events include proper sequence numbers.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/Sync/EventFormatter.*
git commit -m "feat: implement event formatting for subscribeRepos"
```

---

### Task 4: Implement Firehose Event Streaming

**Files:**
- Modify: `Garazyk/Garazyk/Sync/Firehose.h`
- Modify: `Garazyk/Garazyk/Sync/Firehose.m`

**Step 1: Define Firehose interface**

Methods for managing event subscriptions and streaming.

**Step 2: Implement cursor handling**

Support cursor-based pagination and backfill limits.

**Step 3: Add event buffering**

Implement buffering for  streaming.

**Step 4: Handle connection lifecycle**

Manage subscription lifecycle and cleanup.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/Sync/Firehose.*
git commit -m "feat: implement firehose event streaming logic"
```

---

### Task 5: Create WebSocket Server

**Files:**
- Modify: `Garazyk/Garazyk/Sync/WebSocketServer.h`
- Modify: `Garazyk/Garazyk/Sync/WebSocketServer.m`

**Step 1: Define WebSocket server interface**

Methods for starting server, handling connections, and routing to endpoints.

**Step 2: Implement WebSocket upgrade handling**

Handle HTTP to WebSocket protocol upgrade.

**Step 3: Add endpoint routing**

Route `/xrpc/com.atproto.sync.subscribeRepos` to firehose handler.

**Step 4: Integrate with PDS controller**

Connect to existing PDSController for event data.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/Sync/WebSocketServer.*
git commit -m "feat: create WebSocket server with subscribeRepos endpoint"
```

---

### Task 6: Create Missing Network Infrastructure

**Files:**
- Create: `Garazyk/Garazyk/Network/HttpServer.h`
- Create: `Garazyk/Garazyk/Network/HttpServer.m`
- Create: `Garazyk/Garazyk/Network/HttpRequest.h`
- Create: `Garazyk/Garazyk/Network/HttpRequest.m`
- Create: `Garazyk/Garazyk/Network/HttpResponse.h`
- Create: `Garazyk/Garazyk/Network/HttpResponse.m`

**Step 1: Implement HTTP server foundation**

Basic HTTP server using Foundation networking.

**Step 2: Create HTTP request/response wrappers**

Classes to handle HTTP protocol details.

**Step 3: Add WebSocket integration points**

Hooks for WebSocket upgrade handling.

**Step 4: Commit**

```bash
git add Garazyk/Garazyk/Network/Http*.*
git commit -m "feat: create HTTP server infrastructure for WebSocket support"
```

---

### Task 7: Create Server Main Entry Point

**Files:**
- Create: `Garazyk/Garazyk/server_main.m`

**Step 1: Implement main function**

Initialize PDS controller, HTTP server, and WebSocket server.

**Step 2: Set up XRPC routing**

Register existing XRPC method handlers.

**Step 3: Start servers**

Launch HTTP and WebSocket servers on configured ports.

**Step 4: Add graceful shutdown**

Handle SIGTERM/SIGINT for clean shutdown.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/server_main.m
git commit -m "feat: create server main entry point with WebSocket integration"
```

---

### Task 8: Integrate with PDS Controller

**Files:**
- Modify: `Garazyk/Garazyk/PDSController.h`
- Modify: `Garazyk/Garazyk/PDSController.m`

**Step 1: Add event sequencing to PDS controller**

Add sequence number tracking for repository events.

**Step 2: Implement event subscription interface**

Methods for firehose to subscribe to repository changes.

**Step 3: Add backfill support**

Support retrieving historical events for cursor-based resumption.

**Step 4: Update startServer method**

Initialize WebSocket server alongside HTTP server.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/PDSController.*
git commit -m "feat: integrate event sequencing and WebSocket support into PDS controller"
```

---

### Task 9: Add Event Persistence and Sequencing

**Files:**
- Create: `Garazyk/Garazyk/Sync/EventSequencer.h`
- Create: `Garazyk/Garazyk/Sync/EventSequencer.m`

**Step 1: Define event sequencer interface**

Methods for assigning sequence numbers and storing events.

**Step 2: Implement sequence number generation**

Monotonically increasing sequence numbers.

**Step 3: Add event storage**

Persist events for backfill and cursor support.

**Step 4: Implement cursor validation**

Check cursor validity and handle future cursors.

**Step 5: Commit**

```bash
git add Garazyk/Garazyk/Sync/EventSequencer.*
git commit -m "feat: add event sequencing and persistence for cursor support"
```

---

### Task 10: Add Testing Infrastructure

**Files:**
- Create: `streaming-worktree/test_subscribe_repos.sh`

**Step 1: Create basic connectivity test**

Test that WebSocket server starts and accepts connections.

**Step 2: Add subscribeRepos endpoint test**

Test that subscribeRepos endpoint accepts WebSocket connections.

**Step 3: Test cursor parameter handling**

Verify cursor parameter is parsed correctly.

**Step 4: Add to test suite**

Update Makefile test targets.

**Step 5: Commit**

```bash
git add test_subscribe_repos.sh
git commit -m "feat: add basic testing for WebSocket subscribeRepos endpoint"
```

---

### Task 11: Documentation and Integration

**Files:**
- Create: `streaming-worktree/docs/websocket_streaming.md`

**Step 1: Document WebSocket endpoint**

Describe subscribeRepos endpoint usage and parameters.

**Step 2: Document event types**

Explain each event type and their payloads.

**Step 3: Add usage examples**

Show how to connect and consume the stream.

**Step 4: Update README**

Reference the new WebSocket streaming capability.

**Step 5: Commit**

```bash
git add docs/websocket_streaming.md
git commit -m "docs: document WebSocket streaming and subscribeRepos endpoint"
```

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation</content>
<parameter name="filePath">streaming-worktree/docs/plans/2026-01-07-websocket-streaming.md