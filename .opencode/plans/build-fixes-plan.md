# Build Fixes Plan - Detailed Execution

## Goal: Fix all build errors to make tests runnable

---

## Step 1: Fix XrpcAppBskyMethods.m

### Error 1a: Missing Header
**Fix:** Line 10 - Change import
```objc
#import "Database/PDSDatabasePool.h"  →  #import "Database/Pool/DatabasePool.h"
```

### Error 1b: Missing method `userDatabasePoolWithError:`
**Root Cause:** `PDSServiceDatabases` doesn't have this method. Code uses it to store drafts.

**Analysis:** 
- `PDSServiceDatabases` has: `servicePool`, `didCachePool`, `sequencerPool`
- It does NOT have: `userDatabasePool` or method `userDatabasePoolWithError:`
- The draft endpoints need a per-user database but API doesn't exist

**Fix Options:**
1. Add method to PDSServiceDatabases (correct)
2. Use existing pool (wrong semantics)
3. Remove functionality (defer)

**Recommended:** Add method to PDSServiceDatabases:
```objc
// In ServiceDatabases.h add:
- (PDSDatabasePool *)userDatabasePoolWithError:(NSError **)error;

// In ServiceDatabases.m add:
- (PDSDatabasePool *)userDatabasePoolWithError:(NSError **)error {
    return self.servicePool; // or create new pool
}
```

### Error 1c: Missing method `iso8601StringFromDate:`
**Root Cause:** Code uses `[NSDateFormatter iso8601StringFromDate:]` which is a class method that doesn't exist in NSDateFormatter.

**Fix:** The codebase uses a category method. Add import:
```objc
#import "Database/PDSDatabase.h"  // Has iso8601StringFromDate:
```

Then fix lines 2753, 2830 to use the correct call:
```objc
// Old: NSString *now = [NSDateFormatter iso8601StringFromDate:[NSDate date]];
// New: NSString *now = [self iso8601StringFromDate:[NSDate date]];
```

### Error 1d: Missing method `parseLimit:outLimit:`
**Root Cause:** Method doesn't exist anywhere in codebase.

**Fix:** This is a utility needed by draft endpoints. Add to PDSDatabase.h:
```objc
+ (void)parseLimit:(NSString *)limit outLimit:(NSUInteger *)outLimit;
+ (void)parseLimit:(NSString *)limit outLimit:(NSUInteger *)outLimit {
    // Parse limit parameter, default 50, max 100
}
```

---

## Step 2: Fix PLCSyncEngine.m

### Error 2: Variable in @interface
**Fix:** Move `dispatch_queue_t` vars from @interface to @implementation block.

**Current:**
```objc
@interface PLCSyncEngine ()
...
dispatch_queue_t _syncQueue;
dispatch_queue_t _validationQueue;
@property...
@end
```

**Expected:**
```objc
@interface PLCSyncEngine ()
@property...
@end

@implementation PLCSyncEngine {
    dispatch_queue_t _syncQueue;
    dispatch_queue_t _validationQueue;
}
```

**Note:** Keep all properties in @interface - only move the queue variables.

---

## Step 3: Fix RelayEventBuffer.m

### Error 3: Variable in @interface  
**Fix:** Move `dispatch_queue_t` from @interface to @implementation block.

**Current:** Line 17 has `dispatch_queue_t _bufferQueue;` in @interface

**Expected:**
```objc
@interface RelayEventBuffer ()
@property...
@end

@implementation RelayEventBuffer {
    dispatch_queue_t _bufferQueue;
}
```

---

## Files Summary

| File | Changes Required |
|------|-----------------|
| XrpcAppBskyMethods.m | 1. Fix import path 2. Call iso8601StringFromDate correctly |
| ServiceDatabases.h | Add `userDatabasePoolWithError:` method |
| ServiceDatabases.m | Implement `userDatabasePoolWithError:` |
| PDSDatabase.h/m | Add `parseLimit:outLimit:` method |
| PLCSyncEngine.m | Move queue vars to @implementation |
| RelayEventBuffer.m | Move queue var to @implementation |

---

## Execution Commands

```bash
# After all fixes:
xcodegen generate
xcodebuild -scheme AllTests build
./build/tests/AllTests
```

---

## Verification Steps

After each file fix, commit and verify build progresses:
1. Fix XrpcAppBskyMethods.m - should show remaining cascade errors
2. Add missing methods - should reduce errors  
3. Fix queue variable issues - should get closer to BUILD SUCCEEDED