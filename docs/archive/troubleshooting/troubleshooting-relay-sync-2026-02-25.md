---
title: Troubleshooting Relay Sync Crash Loop
---

# Troubleshooting Relay Sync Crash Loop
**Date**: February 25, 2026
**Issue**: AT Protocol PDS server continuously crashing roughly 66-seconds after completing `requestCrawl` and `describeServer` via `com.atproto.sync.subscribeRepos` relay sync.

## Overview
During the resolution of a crash loop that appeared specifically when connecting bridging relays (e.g., `relay.fire.hose.cam`), several critical architectural bugs were identified across WebSocket lifecycle handling, cross-platform Apple/GNUstep threading differences, and component initialization. These errors culminated in stack overflow process terminations, silent connection state leaks, and dropped firehose commits. 

## Issue 1: Stack Overflow in WebSocket Connection Reads
### Discovery
The crash reliably occurred about ~66 seconds after the server acknowledged a new relay connection. The ~60+ second timing strongly indicated a network timeout happening in the background, which then directly caused the application to segfault. 
By inspecting `WebSocketConnection.m`, we analyzed the `-startReading` method, which utilizes GCD network bindings. We found that the code in the callback execution block of `receiveWithMinimumLength:` neglected to check the `isComplete` boolean flag before recursively invoking `[self startReading]` again.

When the relay connection closed due to timeout, the underlying stream EOF marked `isComplete=YES` but without an `error`. This immediately bypassed the `!error` guard and synchronously spawned nested blocks through `startReading` until the thread call stack overflowed, terminating the PDS server.

### Solution
Modified the `startReading` callback block to properly catch `isComplete` without error and securely transition the underlying `WebSocketConnectionState` without recursion.

## Issue 2: NSRunLoop Thread Locality for Heartbeats
### Discovery
Although the recursive loop was the direct cause of the stack overflow, the *catalyst* was an underlying heartbeat timeout that forced the relay to drop its connection after 60 seconds (hence the 66 second crash timing).
In `WebSocketConnection.m`, we noted the `startHeartbeat` routines scheduled `NSTimer` blocks for ping/pong exchanges. However, `NSTimer` relies on an explicitly active `NSRunLoop` for the thread that schedules it. Because the connection upgrade and data transmissions took place entirely over asynchronous GCD background worker threads (which do not have default runloops, especially in GNUstep environments), none of the heartbeat timers were being fired.

### Solution
Entirely removed `NSTimer` calls for the WebSocket lifecycle, migrating instead to GCD's internal `dispatch_source_t` timers (`dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, ...)`), which act transparently across background networking queues globally.

## Issue 3: Leaked HTTP Connections and Overwritten Handlers 
### Discovery
While auditing the WebSocket upgrade path in `HttpServer.m` and `WebSocketConnection.m`, it was evident that memory leakage would occur if a WebSocket unexpectedly terminated.
`WebSocketConnection.m`'s `startOnExistingTransport` simply hijacked the underlying `PDSNetworkConnection` state block doing: `self.connection.stateChangedHandler = ^(...)`.
This effectively orphaned the original cleanup handler block that `HttpServer` attached for managing the `activeConnections` array, leaking memory upon abrupt disconnection.

### Solution
Retained the original handler (`originalHandler = self.connection.stateChangedHandler`) and wrapped it inside the new block execution, ensuring `HttpServer` can tear down connections alongside `WebSocketConnection` gracefully.

## Issue 4: Null Database Pools Dropping Firehose Events
### Discovery
While tracking why the syncing service didn't serialize the data properly over WS, an inspection of `PDSCLIServeCommand.m` illuminated a bug where `SubscribeReposHandler` was initialized omitting the `PDSDatabasePool` configuration.
Consequently, when `SubscribeReposHandler` handled `handleRecordChange:` callbacks, `self.userDatabasePool` was null, failing the guard block handling the `PDSActorStore` data fetching and silently dropping all active repository state broadcasts!

### Solution
Updated `--serve` CLI wiring in `PDSCLIServeCommand.m` to correctly use `initWithServiceDatabases:userDatabasePool:` to bridge the active database pool configurations during runtime.

## Issue 5: ARC and Block GNUstep Limitations on Production Linux
### Discovery
Post-remediation of the logic flaws locally, CI/CD deploys to the remote `GNUstep/Ubuntu` VM failed during the `make` build inside the Docker container layout. 

1. **`NSDictionary` Enumerable Blocks**: Objective-C on Apple platforms is fairly lenient about the typed generics during `enumerateKeysAndObjectsUsingBlock:`. GNUstep, however, strictly mandated raw `id` parameters (`id key, id obj`). The existing codebase enforced `NSString *key, NSDictionary *session` in the block descriptor, which triggered a compiler error.
2. **`dispatch_source_t` Reference Types**: By definition, `dispatch_source_t` conforms as an `OS_dispatch_source` interface compliant for Automatic Reference Counting (`ARC`) via `<OS_object>` under Apple environments (`strong`). However, in Linux's open-source `libdispatch` bindings against `gnustep-libobjc2`, `dispatch_source_t` operates as a transparent C-struct pointer requiring the standard `assign` primitive.

### Solution
1. Rewrote the enumerator block types to `id` casting cleanly across platforms.
2. Applied the custom framework wrapper token `PDS_DISPATCH_QUEUE_STRONG` mapping macro into the `@property` fields to natively toggle ARC references as `strong` for macOS and `assign` for GNUstep seamlessly.
