---
name: debugging-objc-crashes
description: Systematic macOS Objective-C crash diagnosis using crash logs, lldb, signal patterns, memory debugging, and common ARC/concurrency crash fixes.
---

# Debugging Objective-C Crashes on macOS

## Purpose

Systematic approach to debugging crashes in Objective-C applications on macOS, using crash logs, lldb, and common patterns.

## When to Use

- Process crashes unexpectedly
- See SIGBUS, SIGSEGV, SIGABRT signals
- Application terminates without visible error
- Need to diagnose alignment faults, null dereferences, or memory issues

## Workflow

### Phase 1: Check Crash Logs

macOS crash logs are automatically written to:
```
~/Library/Logs/DiagnosticReports/<app>-<date>.ips
```

```bash
# List recent crashes
ls -la ~/Library/Logs/DiagnosticReports/<app>*.ips

# Read latest crash (JSON format)
cat "$(ls -t ~/Library/Logs/DiagnosticReports/<app>*.ips | head -1)"
```

### Phase 2: Parse Key Crash Information

From the `.ips` file, extract:

1. **Exception type**: Look for `"exception"` key
   - `EXC_BAD_ACCESS` - Memory access violation (wild pointer, deallocated object)
   - `SIGBUS` (Bus error) - Alignment fault or invalid memory access
   - `SIGSEGV` - Segmentation fault (null pointer, invalid address)
   - `SIGABRT` - Abort (assertion failure, NSException)

2. **Crash location**: Look for `"faultingThread"` and `"frames"` array
   - First frame is the crash point
   - Symbol name shows the method: `-[ClassName methodName:]`
   - `symbolLocation` gives offset within method

3. **Stack trace**: The `"frames"` array shows call hierarchy
   - Work backwards from crash point to understand cause

### Phase 3: Common Crash Patterns

#### EXC_ARM_DA_ALIGN (Alignment Fault)
**Symptom**: `EXC_ARM_DA_ALIGN` on ARM64
**Cause**: Accessing misaligned memory, often from:
- Messaging a deallocated weak reference
- Accessing invalid pointer as object
- Calling method on garbage memory

**Fix**: Capture weak delegates strongly before using:
```objc
// WRONG - delegate could be deallocated between check and use
dispatch_async(dispatch_get_main_queue(), ^{
    [self.delegate someMethod];  // Crash here!
});

// CORRECT - capture strongly, check nil
id<MyDelegate> delegate = self.delegate;  // Strong capture
dispatch_async(dispatch_get_main_queue(), ^{
    if (delegate) {
        [delegate someMethod];
    }
});
```

#### EXC_BAD_ACCESS (Signal 11)
**Symptom**: Segfault at address 0x0
**Cause**: Nil pointer dereference
**Fix**: Add nil checks before accessing properties/calling methods

**Symptom**: Segfault at random address
**Cause**: Wild pointer, use-after-free
**Fix**: Enable zombie objects for debugging, use strong references

#### Weak Delegate in Block
**Pattern**: Crashes in dispatch_async/dispatch_after blocks
**Root cause**: Weak reference becomes nil during block execution
**Fix**: Always capture weak delegates strongly before block:

```objc
// For properties
@property (nonatomic, weak) id<MyDelegate> delegate;

// Wrong
dispatch_async(queue, ^{
    [self.delegate doSomething];  // May crash
});

// Correct
id<MyDelegate> delegate = self.delegate;
dispatch_async(queue, ^{
    if (delegate) {
        [delegate doSomething];
    }
});

// For value capture in blocks
int64_t seq = self.currentSeq;  // Capture value
dispatch_async(queue, ^{
    [delegate didReceiveSeq:seq];  // Use captured value
});
```

### Phase 4: Running Under lldb

For live debugging (when crash is reproducible):

```bash
# Start under debugger
lldb ./build/bin/myapp

# In lldb, run with arguments
(lldb) run serve --port 2584 --upstream localhost:2583

# Wait for crash, then inspect
(lldb) bt        # Backtrace
(lldb) frame var # Local variables
(lldb) po self   # Print object
(lldb) continue # Continue if paused

# Set breakpoints
(lldb) b -[ClassName methodName:]
(lldb) b file.m:123

# Run with environment
(lldb) env MallocStackLogging=1
(lldb) run
```

### Phase 5: Environment Variables for Debug

```bash
# Enable zombie objects (catches use-after-free)
NSZombieEnabled=1 ./build/bin/myapp

# Enable malloc stack logging
MallocStackLogging=1 ./build/bin/myapp

# Enable guard malloc
GuardMalloc=1 ./build/bin/myapp
```

## Example Debugging Session

### Issue: Relay crashes with SIGBUS

1. **Found crash logs**:
   ```bash
   ls ~/Library/Logs/DiagnosticReports/zuk*.ips
   ```

2. **Parsed exception**:
   ```
   "exception": {"type":"EXC_BAD_ACCESS","signal":"SIGBUS","subtype":"EXC_ARM_DA_ALIGN"}
   ```

3. **Found crash location**:
   ```
   "symbol":"-[RelayUpstreamManager relayClient:didReceiveCursor:]"
   ```

4. **Analyzed stack**:
   ```
   firehoseSubscription:didCloseWithError: ->
   dispatch_async block ->
   relayClient:didReceiveCursor: (CRASH)
   ```

5. **Root cause**: Weak delegate property accessed in async block without strong capture

6. **Fix applied**:
   ```objc
   // Before
   dispatch_async(dispatch_get_main_queue(), ^{
       [self.delegate relayClient:self didReceiveCursor:self.currentSeq];
   });

   // After
   id<RelayClientDelegate> delegate = self.delegate;
   int64_t seq = self.currentSeq;
   dispatch_async(dispatch_get_main_queue(), ^{
       if (delegate) {
           [delegate relayClient:self didReceiveCursor:seq];
       }
   });
   ```

## Quick Reference

| Signal | Meaning | Common Cause |
|--------|---------|--------------|
| SIGBUS | Bus error | Alignment fault, bad pointer |
| SIGSEGV | Segfault | Null deref, invalid memory |
| SIGABRT | Abort | Assertion, NSException |
| SIGILL | Illegal instruction | Stack corruption, bad PC |

## Tools

- `~/Library/Logs/DiagnosticReports/` - Crash logs
- `lldb` - LLVM debugger
- `atos` - Symbolicate addresses
- `dwarfdump` - Debug info inspection
- Console.app - View crash reports graphically
