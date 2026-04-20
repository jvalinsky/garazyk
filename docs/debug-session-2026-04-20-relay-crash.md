# Debug Session: Relay Crash (SIGBUS Alignment Fault)

**Date**: 2026-04-20
**Issue**: Relay server (zuk) crashing with SIGBUS alignment fault
**Root Cause**: Weak delegate properties accessed in async blocks without strong capture

## Summary

The relay server would start successfully, connect to upstream PDS, but then crash within seconds. The crash only manifested on ARM64 macOS due to alignment requirements that don't exist on x86_64 or simulator architectures.

## Discovery Process

### Phase 1: Observed Behavior

Relay started successfully, logged connection to upstream:
```
[INFO] RelayUpstreamManager: Client connected to localhost:2583
[INFO] Relay: Connected to upstream localhost:2583
```

Then crashed silently - no error logs, process just disappeared.

### Phase 2: Crash Log Analysis

Found crash logs at:
```
~/Library/Logs/DiagnosticReports/zuk-2026-04-20-*.ips
```

Key findings from crash log:

```json
{
  "exception": {
    "type": "EXC_BAD_ACCESS",
    "signal": "SIGBUS",
    "subtype": "EXC_ARM_DA_ALIGN"
  },
  "faultingThread": 0,
  "frames": [
    {"symbol": "-[RelayUpstreamManager relayClient:didReceiveCursor:]"},
    {"symbol": "__54-[RelayClient firehoseSubscription:didCloseWithError:]_block_invoke"},
    {"symbol": "_dispatch_call_block_and_release"}
  ]
}
```

**Critical insight**: `EXC_ARM_DA_ALIGN` is an alignment fault on ARM64. This typically indicates accessing memory through an invalid pointer - often a deallocated object.

### Phase 3: Root Cause Analysis

Stack trace showed:
1. `firehoseSubscription:didCloseWithError:` called when WebSocket closes
2. Dispatches async block to main queue
3. Block calls `[self.delegate relayClient:self didReceiveCursor:...]`
4. Crash occurs because `self.delegate` was accessed weakly

The problem pattern:

```objc
// RelayClient.h
@property (nonatomic, weak, nullable) id<RelayClientDelegate> delegate;

// RelayClient.m - WRONG
- (void)firehoseSubscription:(FirehoseSubscription *)subscription didCloseWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate relayClient:self didReceiveCursor:self.currentSeq];  // CRASH!
    });
}
```

Why it crashes:
1. `self.delegate` is a weak property
2. The async block captures `self.delegate` weakly
3. Between block creation and execution, the delegate (RelayUpstreamManager) can be deallocated
4. When the block tries to message the deallocated object → alignment fault

### Phase 4: Similar Patterns Found

Found the same pattern in multiple places:

**RelayClient.m** - 6 instances:
- `notifyDisconnectionWithError:`
- `firehoseSubscriptionDidConnect:`
- `firehoseSubscription:didReceiveCommitEvent:`
- `firehoseSubscription:didReceiveIdentityEvent:`
- `firehoseSubscription:didReceiveErrorEvent:`
- `firehoseSubscription:didCloseWithError:`

**RelayUpstreamManager.m** - 6 instances:
- `relayClient:didReceiveCommitEvent:`
- `relayClient:didReceiveIdentityEvent:`
- `relayClient:didReceiveErrorEvent:`
- `relayClientDidConnect:`
- `relayClient:didDisconnectWithError:`
- `relayClient:didReceiveCursor:`

## The Fix

### Pattern A: Delegate in Dispatch Async Block

**Before (crashes)**:
```objc
dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate relayClient:self didReceiveCursor:self.currentSeq];
});
```

**After (safe)**:
```objc
id<RelayClientDelegate> delegate = self.delegate;  // Strong capture
int64_t seq = self.currentSeq;  // Capture value
dispatch_async(dispatch_get_main_queue(), ^{
    if (delegate) {
        [delegate relayClient:self didReceiveCursor:seq];
    }
});
```

### Pattern B: Direct Delegate Call

**Before (can crash)**:
```objc
- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    NSString *url = [self urlForClient:client];
    if (url) {
        [self.delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}
```

**After (safe)**:
```objc
- (void)relayClient:(RelayClient *)client didReceiveCommitEvent:(FirehoseCommitEvent *)event {
    NSString *url = [self urlForClient:client];
    id<RelayUpstreamManagerDelegate> delegate = self.delegate;  // Strong capture
    if (url && delegate) {
        [delegate upstreamManager:self didReceiveEvent:event fromUpstream:url];
    }
}
```

### Pattern C: Block Capturing Self Properties

**Before (unsafe)**:
```objc
dispatch_async(_managerQueue, ^{
    [self.connectedUpstreams addObject:url];
    self.reconnectAttempts[url] = @0;
});
```

**After (safe)**:
```objc
NSMutableSet *connectedUpstreams = self.connectedUpstreams;
NSMutableDictionary *reconnectAttempts = self.reconnectAttempts;
dispatch_async(_managerQueue, ^{
    [connectedUpstreams addObject:url];
    reconnectAttempts[url] = @0;
});
```

## Why This Matters

### ARM64 Alignment Requirements

On ARM64, accessing memory with incorrect alignment causes a hardware exception. When messaging a deallocated (or garbage) object pointer:

1. The runtime tries to access the object's isa pointer
2. If the pointer points to garbage memory, the access may be misaligned
3. CPU raises SIGBUS with `EXC_ARM_DA_ALIGN`

On x86_64, misaligned accesses are handled in hardware (with performance penalty), so this crash might not reproduce.

### Weak References in Blocks

Weak references in ObjC blocks are a common footgun:

```objc
@property (nonatomic, weak) id<MyDelegate> delegate;

// In a method:
dispatch_async(queue, ^{
    [self.delegate doSomething];  // DANGEROUS
});
```

The block captures the expression `self.delegate`, not the current value. Each evaluation of `self.delegate` performs a weak read that can return nil if the object was deallocated. But if deallocation happens between the weak read and the method call, you can crash.

## Files Modified

| File | Changes |
|------|---------|
| `Garazyk/Sources/Sync/Relay/RelayClient.m` | 6 delegate calls fixed with strong capture |
| `Garazyk/Sources/Sync/Relay/RelayUpstreamManager.m` | 6 delegate calls fixed, property captures added |

## Testing

After fix, relay survives all test scenarios:
- Health endpoint returns 200
- Admin endpoint returns proper auth errors
- Relay stays running for extended periods
- No crash logs generated

## Lessons Learned

1. **Always capture weak delegates strongly** before using in async contexts
2. **Check macOS crash logs** in `~/Library/Logs/DiagnosticReports/` for silent crashes
3. **SIGBUS on ARM64** often means use-after-free or messaging deallocated object
4. **Symbol offsets** in crash logs help locate exact instruction within method

## References

- [Working with Blocks](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/WorkingWithBlocks/WorkingWithBlocks.html)
- [Objective-C Weak References](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#arc-weak-references)
- [Understanding Crash Reports](https://developer.apple.com/documentation/xcode/understanding-the exception-types-in-a-crash-report)

## Related Documentation

- [[system/garazyk/gotchas.md]] - Project-specific debugging patterns
- [[.agents/skills/debugging-objc-crashes/SKILL.md]] - General debugging workflow
