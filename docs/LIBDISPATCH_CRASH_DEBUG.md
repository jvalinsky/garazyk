---
title: libdispatch SIGILL Crash Debugging Session
---

# libdispatch SIGILL Crash Debugging Session

**Date**: 2026-02-21  
**System**: Ubuntu 24.04, x86_64  
**libdispatch**: swift-corelibs-libdispatch `swift-DEVELOPMENT-SNAPSHOT-2026-02-19-a` from `/usr/local/lib/libdispatch.so`  
**ObjC Runtime**: GNUstep libobjc2 with ARC  
**Affected binaries**: `kaszlak` (PDS server), `campagnola` (PLC server)  

## Symptom

Both servers crash with `SIGILL` (Illegal instruction) after handling their first HTTP request. The crash happens consistently, every time, killing the process. systemd auto-restarts it (`Restart=on-failure`), but the next request kills it again — making every other request fail with a 502.

```

dmesg output (consistent across all crashes):
traps: -qos.overcommit[PID] trap invalid opcode ip:XXXX sp:XXXX error:0 in libdispatch.so[5c700,BASE+52000]
```

The crash offset is always `+0x3D700` from the libdispatch base address.

---

## Timeline

### 21:06 UTC — Problem identified

CSS not loading on `https://crimson-comet.exe.xyz:8000/` because the PDS crashes after serving the HTML, and CSS/JS requests hit during the restart window → 502.

### 21:08 UTC — Initial investigation

Confirmed all CSS/JS endpoints return valid data when the server is up:
```bash
curl -s http://localhost:2583/css/system.css  # Works, returns CSS
curl -s http://localhost:2583/               # Works, returns HTML
# ...then server crashes, next request fails
```

Checked `dmesg`:
```

traps: -qos.overcommit[68131] trap invalid opcode ip:7faa1d2e1700 sp:7faa127f9100 error:0 in libdispatch.so[5c700,7faa1d2a4000+52000]
```

Offset: `0x7faa1d2e1700 - 0x7faa1d2a4000 = 0x3D700`

Checked history — crashes predate all code changes (going back to 20:09 UTC).

## 21:17 UTC — Workaround: nginx static file serving

**Decision**: Serve all static assets (CSS, JS, HTML, fonts) directly from nginx, bypassing the crashing PDS/PLC entirely. Only proxy dynamic API calls (`/xrpc/`, `/api/`, etc.) to the backend.

**Result**: ✅ CSS loads reliably. The page renders fully styled. But API calls still fail intermittently when they hit the crash window.

### 21:35 UTC — Reduced RestartSec

Changed `RestartSec=5` → `RestartSec=1` in both `pds.service` and `plc.service` to minimize the crash/restart window.

**Result**: Marginal improvement — shorter downtime between crashes but still every-other-request fails.

### 21:37 UTC — Hypothesis 1: NULL dispatch objects from weak self

Looking at `HttpServer.m` `dispatchRequest:onConnection:` method:

```objc
dispatch_async(dispatch_get_global_queue(...), ^{
    dispatch_semaphore_wait(weakSelf.concurrencySemaphore, DISPATCH_TIME_FOREVER);
    
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) {
        dispatch_semaphore_signal(weakSelf.concurrencySemaphore); // BUG: weakSelf is nil!
        dispatch_group_leave(weakSelf.taskGroup);                 // BUG: weakSelf is nil!
        return;
    }
    ...
});
```

On Linux, `PDS_DISPATCH_QUEUE_STRONG` is `assign` (not `strong`), so dispatch objects are NOT ARC-managed. If `weakSelf` is nil, messaging it returns nil/NULL, and `dispatch_semaphore_signal(NULL)` / `dispatch_group_leave(NULL)` would crash in libdispatch.

**Fix attempt**: Removed the nil-path dispatch calls entirely (just `return` if strongSelf is nil).

**Result**: ❌ Still crashes. The nil-self path wasn't being hit — the server object is alive during normal operation.

### 21:40 UTC — Hypothesis 2: Dangling dispatch objects (assign property)

Since dispatch objects are `assign` on Linux, they could be freed while async blocks still hold references via `strongSelf.concurrencySemaphore` etc.

**Fix attempt**: Capture dispatch objects as local variables with explicit `dispatch_retain`/`dispatch_release`:

```objc
dispatch_semaphore_t semaphore = self.concurrencySemaphore;
dispatch_group_t group = self.taskGroup;
dispatch_queue_t serverQ = self.serverQueue;
dispatch_retain(semaphore);
dispatch_retain(group);
dispatch_retain(serverQ);
// ... use captured locals in block, dispatch_release in all paths
```

Verified `dispatch_retain`/`dispatch_release` work correctly on this libdispatch build:
```bash
# Test program: create, retain, release, release — no crash
clang -o /tmp/test_dispatch test.m -ldispatch
/tmp/test_dispatch  # "created, retained, released, final release" — OK
```

**Result**: ❌ Still crashes at same offset `+0x3D700`. The dispatch objects weren't being freed prematurely — the server object stays alive.

## 21:42 UTC — Core dump analysis

Enabled core dumps and caught one:
```bash
ulimit -c unlimited
sudo sysctl kernel.core_pattern=/tmp/core.%e.%p
./build-linux/bin/kaszlak serve ...
curl http://localhost:2583/
# Crash → core dump at /tmp/core.-qos.overcommit.71085
```

GDB analysis:
```

Program terminated with signal SIGILL, Illegal instruction.
#0  dispatch_group_leave () from /usr/local/lib/libdispatch.so
#1  __41_i_HttpServer__readRequestFromConnection__block_invoke
    at HttpServer.m:378
#2  -[PDSNetworkConnectionLinux processReadRequests:error:]
    at PDSNetworkTransportLinux.m:462
#3  -[PDSNetworkConnectionLinux handleRead]
    at PDSNetworkTransportLinux.m:388
#4  __42_i_PDSNetworkConnectionLinux__setupSources_block_invoke
    at PDSNetworkTransportLinux.m:366
#5  _dispatch_client_callout () from libdispatch.so
#6  _dispatch_continuation_pop () from libdispatch.so
#7  _dispatch_source_latch_and_call () from libdispatch.so
...
```

**Key finding**: The crash is `dispatch_group_leave()` called inside the `readRequestFromConnection` completion block. `dispatch_group_leave` with an already-zero count triggers `__builtin_trap()` (UD2 instruction) inside libdispatch → SIGILL.

The crash is NOT from the `dispatchRequest` path I was fixing earlier. It's from the **read completion** path.

## 21:43 UTC — Root cause analysis

The `readRequestFromConnection` method:
1. Calls `dispatch_group_enter(group)`
2. Starts a `receiveWithMinimumLength:completion:` async read
3. When data arrives, the completion block calls `handleReceivedData` then `dispatch_group_leave(group)`

The completion is called by `processReadRequests:error:` in `PDSNetworkTransportLinux.m`, which runs a **while loop** over all pending read requests. The flow:

1. `handleRead` receives EOF (`received == 0`) → calls `processReadRequests:YES error:nil`
2. `processReadRequests` loops, fires completion with `(data, isComplete=YES, nil)`
3. Completion calls `handleReceivedData` → dispatches the HTTP response → tries to set up a new read
4. But `handleReceivedData` → `readRequestFromConnection` returns early (pendingDispatchCount > 0)
5. Completion calls `dispatch_group_leave(group)` — **balanced** (one enter, one leave)
6. Back in `handleRead`, after `processReadRequests` returns, it calls `[self cancel]`
7. `cancel` may trigger dispatch source cancellation → more callbacks → potentially another `dispatch_group_leave`

OR: the `processReadRequests` while loop processes multiple pending reads (if >1 was queued), each calling `dispatch_group_leave` but only one `dispatch_group_enter` was done.

**The fundamental issue**: `dispatch_group_enter`/`leave` is used for individual socket reads, but the completion callback can fire in unexpected contexts (dispatch source callbacks, cancellation) where the group balance assumption breaks.

### 21:44 UTC — Fix attempt 3: Remove group from read path

The `taskGroup` is used for:
1. Waiting for all in-flight operations during server shutdown
2. Tracking concurrent request processing

The individual socket reads don't need group tracking — they're triggered by dispatch sources (which have their own lifecycle). Only `dispatchRequest` needs the group for concurrency management.

**Fix**: Remove `dispatch_group_enter`/`leave` from `readRequestFromConnection` entirely. The read completion just processes data and dispatches if needed — no group involvement.

```objc
// Before: 
dispatch_group_enter(self.taskGroup);
[connection receiveWithMinimumLength:1 maximumLength:UINT32_MAX completion:^(...){
    ...
    dispatch_group_leave(group);
}];

// After:
[connection receiveWithMinimumLength:1 maximumLength:UINT32_MAX completion:^(...){
    ...
    // No group involvement
}];
```

**Result**: ❌ Still crashes at same location. The crash pattern `200 000 000 000 000 200 000 000 000 000` persists.

**Analysis**: This was surprising. Even without the group_enter/leave in our code, the crash still happens in `dispatch_group_leave` at the same libdispatch offset. This means either:
1. The old binary wasn't properly deployed (checked — it was rebuilt and restarted)
2. There's ANOTHER dispatch_group_leave somewhere in the call chain
3. The symbol `dispatch_group_leave` in the backtrace is misleading (the crash address +0x3D700 maps to `dispatch_get_specific` in objdump, not `dispatch_group_leave`)

### Current status (21:44 UTC)

The crash persists. The `+0x3D700` offset in libdispatch is hit consistently after every request.

## What we know for certain

1. **The crash is in libdispatch**, specifically in a GCD overcommit worker thread
2. **It happens after every HTTP request** — the request completes successfully (status 200 logged) then the process dies
3. **The crash offset is always `+0x3D700`** from the libdispatch base
4. **Core dump confirms**: `dispatch_group_leave()` called from `readRequestFromConnection` completion block → called from `processReadRequests` → called from `handleRead` dispatch source callback
5. **The libdispatch version** is a very recent dev snapshot (`swift-DEVELOPMENT-SNAPSHOT-2026-02-19-a`)
6. **dispatch_retain/release work correctly** in isolation
7. **The `assign` property storage** for dispatch objects on Linux (vs `strong` on macOS) is a contributing factor to lifetime management complexity

## Hypotheses still to investigate

1. **Double dispatch_group_leave**: `processReadRequests` while loop may fire the completion callback multiple times for a single `dispatch_group_enter`. Need to add logging/assertions to count enter/leave calls.

2. **Dispatch source cancellation handler**: After `handleRead` calls `processReadRequests`, it calls `[self cancel]` which cancels the dispatch source. The cancellation handler might trigger another code path that also leaves the group.

3. **libobjc2 + libdispatch ARC interaction**: On Linux with GNUstep's libobjc2, blocks captured by dispatch may have different lifetime semantics. The block might be freed while libdispatch is still executing it.

4. **libdispatch build issue**: The `swift-DEVELOPMENT-SNAPSHOT-2026-02-19-a` is a bleeding-edge build. There might be a known bug. Worth checking:
   - https://github.com/apple/swift-corelibs-libdispatch/issues
   - Whether building with an older tag (e.g., `swift-5.10-RELEASE`) fixes the issue

5. **NWConnection / socket lifecycle**: The Linux network transport (`PDSNetworkTransportLinux.m`) uses raw sockets with dispatch sources. If the dispatch source fires after the connection object is deallocated, the callback hits freed memory.

## Workaround in place

Nginx serves all static files (HTML, CSS, JS, fonts) directly. Only API calls proxy to the PDS/PLC backends. Combined with `RestartSec=1`, this means:
- Page always loads with full styling
- API calls succeed ~50% of the time (first request after restart works, subsequent fail until next restart)
- The JS UI should be updated to retry failed API calls

## Files modified during debugging

- `ATProtoPDS/Sources/Network/HttpServer.m` — dispatch_group changes (3 iterations)
- `/etc/systemd/system/pds.service` — RestartSec=5→1
- `/etc/systemd/system/plc.service` — RestartSec=5→1
- `/etc/nginx/sites-enabled/garazyk.xyz` — static file serving + proxy config
