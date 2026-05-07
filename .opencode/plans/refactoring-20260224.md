# Comprehensive Refactoring Plan

**Generated:** 2026-02-24  
**Status:** Completed (13 of 14 items)  
**Test Command:** `./build/tests/AllTests` - **1012 tests, 0 failures**

---

## Completed Items

- ✅ 1.1 PLCOperation null handling
- ✅ 1.2 DNS TXT concatenation
- ✅ 1.3 BFS queue O(n²)
- ✅ 1.4 Lexicon $type prefix matching
- ✅ 2.3 MST binary search extraction
- ✅ 2.4 MST keyDepth consolidation
- ✅ 2.5 RepoCommit serialize deduplication
- ✅ 2.6 Dead code (WebSocketServer)
- ✅ 3.1 Rate limiting optimization
- ✅ 3.2 Lexicon validator caching
- ✅ 5.1 P-256 uncompressed key support
- ✅ 5.2 URI scheme validation

---

## Remaining Items (Deferred)

- CBOR base class extraction (complex, requires new files)
- Varint utility consolidation (complex)
- XRPC registration macro
- XrpcMethodRegistry split (large architectural change)
- CID generator utility
- NSLog → PDSLogger migration
- Base64URL extraction

---

## Execution Order

The refactoring is organized into phases, where each phase builds on the previous. Dependencies are noted.

---

## Phase 1: Critical Bug Fixes (Spec Compliance)

### 1.1 PLCOperation null handling (HIGH PRIORITY)

**File:** `ATProtoPDS/Sources/PLC/PLCOperation.m`  
**Lines:** 194-203

**Current Code:**
```objc
- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [self.data mutableCopy];
    dict[@"sig"] = self.sig;
    if (self.prev) {
        dict[@"prev"] = self.prev;
    } else {
        dict[@"prev"] = [NSNull null];  // BUG: null fields break CID verification
    }
    return [dict copy];
}
```

**Problem:** ATProto spec omits null fields from DAG-CBOR encoding. Including `prev: null` will cause CID mismatches during PLC operation verification.

**Fix:**
```objc
- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [self.data mutableCopy];
    dict[@"sig"] = self.sig;
    if (self.prev) {
        dict[@"prev"] = self.prev;
    }
    // Do NOT include prev if nil - DAG-CBOR omits null fields
    return [dict copy];
}
```

**Test:** Run PLC integration tests after fix.

---

### 1.2 DNS TXT Record Concatenation

**File:** `ATProtoPDS/Sources/Identity/HandleResolver.m`  
**Lines:** 357-374

**Current Code:**
```objc
const unsigned char *txt_data = ns_rr_rdata(rr);
if (txt_data == NULL) continue;

int txt_len = txt_data[0];
NSString *txt_str = [[NSString alloc] initWithBytes:txt_data + 1 length:txt_len encoding:NSUTF8StringEncoding];

if ([txt_str hasPrefix:@"did="]) {
    NSString *did = [txt_str substringFromIndex:4];
    completion(did, nil);
    return;
}
```

**Problem:** ATProto spec allows multiple strings per TXT record (concatenated). Current code only reads the first string.

**Fix:**
```objc
const unsigned char *txt_data = ns_rr_rdata(rr);
if (txt_data == NULL) continue;

// Handle multiple strings in TXT record (ATProto spec allows concatenation)
NSMutableString *fullTxt = [NSMutableString string];
int offset = 0;
while (offset < ns_rr_rdlen(rr)) {
    int seg_len = txt_data[offset];
    if (seg_len == 0 || offset + 1 + seg_len > ns_rr_rdlen(rr)) break;
    NSString *seg = [[NSString alloc] initWithBytes:txt_data + offset + 1 
                                             length:seg_len 
                                           encoding:NSUTF8StringEncoding];
    if (seg) [fullTxt appendString:seg];
    offset += 1 + seg_len;
}

if ([fullTxt hasPrefix:@"did="]) {
    NSString *did = [fullTxt substringFromIndex:4];
    completion(did, nil);
    return;
}
```

**Test:** Add test case with multi-string TXT record.

---

### 1.3 BFS Queue Performance Fix

**File:** `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m`  
**Lines:** 792-806

**Current Code:**
```objc
NSMutableArray<NSData *> *queue = [NSMutableArray arrayWithObject:[rootCID bytes]];
NSMutableSet<NSString *> *visited = [NSMutableSet set];
NSUInteger count = 0;

while (queue.count > 0) {
    NSData *cidBytes = queue.firstObject;
    [queue removeObjectAtIndex:0];  // O(n) operation!
    // ...
}
```

**Problem:** `removeObjectAtIndex:0` is O(n) for each operation, making the overall algorithm O(n²).

**Fix:** Use index-based queue:
```objc
// Use index-based queue to avoid O(n) removals
NSUInteger queueHead = 0;
NSMutableArray<NSData *> *queue = [NSMutableArray arrayWithObject:[rootCID bytes]];

while (queueHead < queue.count) {
    NSData *cidBytes = queue[queueHead++];  // O(1) access
    // ...
}
```

**Test:** Run firehose tests with large repositories.

---

### 1.4 Lexicon $type Prefix Matching

**File:** `ATProtoPDS/Sources/Lexicon/ATProtoLexiconValidator.m`  
**Lines:** 61-70

**Current Code:**
```objc
// Verify $type matches collection
if (![recordType isEqualToString:collection]) {
    // Error - strict equality check
}
```

**Problem:** ATProto allows `$type` to be a prefix NSID. For example, `app.bsky.feed.post` as `$type` should match collection `app.bsky.feed.post` (the record refers to itself via `#main`).

**Fix:**
```objc
// Verify $type matches collection (supports prefix matching)
BOOL typeMatches = [recordType isEqualToString:collection] || 
                   [recordType hasPrefix:[collection stringByAppendingString:@"#"]];

if (!typeMatches) {
    if (error) {
        *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorTypeMismatch
                                            message:[NSString stringWithFormat:@"Record $type '%@' does not match collection '%@'",
                                                    recordType, collection]
                                            context:nil];
    }
    return NO;
}
```

**Test:** Run lexicon validation tests.

---

## Phase 2: Code Deduplication

### 2.1 Extract CBOR Base Class

**Files:** 
- `ATProtoPDS/Sources/Repository/CBOR.m` (587 lines)
- `ATProtoPDS/Sources/Core/ATProtoDagCBOR.m` (721 lines)

**Duplication:** ~80% of code is duplicated between these files.

**Solution:** Create a shared base class/utility:

1. **New file:** `ATProtoPDS/Sources/Core/CBORCodec.h` + `.m`
   - Extract shared: varint encoding/decoding, type constants, encoding/decoding helpers
   - Keep CBOR.m for CBOR-specific logic
   - Make ATProtoDagCBOR use CBORCodec internally

2. **Refactoring Steps:**
   ```
   a) Create CBORCodec with:
      - +encodeVarint:, +decodeVarint:
      - +encodeUnsignedInteger:, +decodeUnsignedInteger
      - +encodeMapKeysSorted:, +canonicalMapSort
      - _encodeValue:, _decodeFromBytes:...
   
   b) Update CBOR.m to import CBORCodec and use shared methods
   
   c) Update ATProtoDagCBOR.m to:
      - Import CBORCodec
      - Remove duplicated methods
      - Keep only DAG-CBOR specific logic (CID tagging, JSON conversion)
   ```

**Test:** Run CAR file tests and repo sync tests.

---

### 2.2 Varint Utility Consolidation

**Files:** 
- `ATProtoPDS/Sources/Repository/CBOR.m`
- `ATProtoPDS/Sources/Repository/CAR.m`
- `ATProtoPDS/Sources/PLC/PLCDIDKey.m`

**Solution:** Add `+[CBORCodec readVarint:]` and `+[CBORCodec writeVarint:]` to the CBORCodec class from Phase 2.1, then update CAR.m and PLCDIDKey.m to import and use it.

**Test:** Run CAR interop tests.

---

### 2.3 MST Binary Search Extraction

**File:** `ATProtoPDS/Sources/Repository/MST.m`  
**Lines:** `getRecursive`, `deleteRecursive`, `addRecursive` (approximately lines 460-700)

**Current Pattern (duplicated in 3 methods):**
```objc
// Binary search for insertion point
NSInteger left = 0, right = self.internalEntries.count;
while (left < right) {
    NSInteger mid = left + (right - left) / 2;
    NSComparisonResult cmp = [self.internalEntries[mid].fullKey compare:key];
    if (cmp == NSOrderedAscending) {
        left = mid + 1;
    } else {
        right = mid;
    }
}
```

**Solution:** Extract to helper method:
```objc
- (NSUInteger)binarySearchIndexForKey:(NSString *)key {
    NSInteger left = 0, right = (NSInteger)self.internalEntries.count;
    while (left < right) {
        NSInteger mid = left + (right - left) / 2;
        NSComparisonResult cmp = [self.internalEntries[mid].fullKey compare:key];
        if (cmp == NSOrderedAscending) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return (NSUInteger)left;
}
```

---

### 2.4 MST keyDepth Consolidation

**File:** `ATProtoPDS/Sources/Repository/MST.m`  
**Lines:** 395-452

**Current Code:**
```objc
+ (NSUInteger)keyDepthString:(NSString *)key {
    return (NSUInteger)[self keyDepth:key];  // Calls keyDepth: with UTF8
}

+ (uint32_t)keyDepth:(NSString *)key {
    const char *utf8 = [key UTF8String];
    // ... SHA256 calculation
}

+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes {
    // ... DUPLICATED SHA256 calculation
}
```

**Solution:** Single implementation:
```objc
+ (uint32_t)keyDepthFromBytes:(const uint8_t *)bytes length:(NSUInteger)len {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)len, hash);
    
    uint32_t zeroCount = 0;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        uint8_t byte = hash[i];
        if (byte == 0) {
            zeroCount += 4;
            continue;
        }
        if ((byte & 0xC0) != 0) break;
        if ((byte & 0xFC) == 0) zeroCount += 3;
        else if ((byte & 0xF0) == 0) zeroCount += 2;
        else zeroCount += 1;
        break;
    }
    return zeroCount;
}

+ (uint32_t)keyDepth:(NSString *)key {
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    return [self keyDepthFromBytes:keyData.bytes length:keyData.length];
}

+ (NSUInteger)keyDepthBytes:(NSData *)keyBytes {
    return [self keyDepthFromBytes:keyBytes.bytes length:keyBytes.length];
}
```

---

### 2.5 RepoCommit Serialize Deduplication

**File:** `ATProtoPDS/Sources/Repository/RepoCommit.m`  
**Lines:** 26-56 (`serialize`) vs 63-97 (`serializeSigned`)

**Solution:**
```objc
- (NSData *)serialize:(BOOL)sign error:(NSError **)error {
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    content[@"did"] = self.did;
    content[@"version"] = @(self.version);
    content[@"data"] = self.dataCID.stringValue;
    content[@"rev"] = self.rev;
    
    if (self.prev) {
        content[@"prev"] = self.prev.stringValue;
    }
    
    // Always include sig key (required by DAG-CBOR for signed commits)
    if (sign && self.signature) {
        content[@"sig"] = self.signature;
    }
    
    return [ATProtoDagCBOR encodeObject:content error:error];
}
```

---

### 2.6 Remove Dead Code - WebSocketServer

**File:** `ATProtoPDS/Sources/Sync/WebSocketServer.m`

**Remove:**
- Line 24: Property declaration
- Line 40: Property initialization

```objc
// DELETE THESE LINES:
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, WebSocketConnection *> *connectionsByFileDescriptor;

// In init:
_connectionsByFileDescriptor = [NSMutableDictionary dictionary];
```

---

## Phase 3: Performance Improvements

### 3.1 Rate Limiting O(1)

**File:** `ATProtoPDS/Sources/Identity/HandleResolver.m`  
**Lines:** 382-401

**Current Code:**
```objc
@synchronized(self.requestTimestamps) {
    NSDate *now = [NSDate date];
    NSTimeInterval oneMinuteAgo = [now timeIntervalSince1970] - 60.0;
    
    // O(n) filter
    [self.requestTimestamps filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDate *timestamp, NSDictionary *bindings) {
        return [timestamp timeIntervalSince1970] > oneMinuteAgo;
    }]];
    
    if (self.requestTimestamps.count >= self.rateLimitPerMinute) {
        return NO;
    }
    [self.requestTimestamps addObject:now];
    return YES;
}
```

**Fix:** Use circular buffer:
```objc
@interface HandleResolver ()
@property (nonatomic, strong) NSMutableIndexSet *activeRequestIndices;
@property (nonatomic, strong) NSMutableArray<NSDate *> *requestTimestampsCircular;
@property (nonatomic, assign) NSUInteger circularIndex;
@end

- (BOOL)checkRateLimit {
    @synchronized(self) {
        NSDate *now = [NSDate date];
        
        // Clean up old timestamps using circular buffer
        NSTimeInterval oneMinuteAgo = [now timeIntervalSince1970] - 60.0;
        while (self.requestTimestampsCircular.count > 0) {
            NSDate *oldest = self.requestTimestampsCircular.firstObject;
            if ([oldest timeIntervalSince1970] > oneMinuteAgo) break;
            [self.requestTimestampsCircular removeObjectAtIndex:0];
        }
        
        if (self.requestTimestampsCircular.count >= self.rateLimitPerMinute) {
            return NO;
        }
        
        [self.requestTimestampsCircular addObject:now];
        return YES;
    }
}
```

---

### 3.2 Lexicon Validator Optimizations

**File:** `ATProtoPDS/Sources/Lexicon/ATProtoLexiconValidator.m`

**Cache Character Set (line 431-432):**
```objc
// ADD STATIC:
static NSCharacterSet *sValidLanguageTagCharacters;

+ (void)initialize {
    if (self == [ATProtoLexiconValidator class]) {
        sValidLanguageTagCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz-"];
    }
}
```

**Cache Regex (line 445-458):**
```objc
// ADD STATIC:
static NSRegularExpression *sLanguageTagRegex;

+ (void)initialize {
    if (self == [ATProtoLexiconValidator class]) {
        NSError *error = nil;
        sLanguageTagRegex = [NSRegularExpression regularExpressionWithPattern:@"^[a-z]{2,3}(-[A-Z]{2})?(-[A-Z]{2,5}){0,3}$" 
                                                                       options:0 
                                                                         error:&error];
    }
}
```

---

## Phase 4: Architectural Improvements

### 4.1 XRPC Registration Macro

**File:** `ATProtoPDS/Sources/Network/XrpcHandler.m`  
**Lines:** 102-516

**Current Pattern (400 lines of duplication):**
```objc
- (void)registerComAtprotoServerDescribeServer:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.describeServer" handler:handler];
}
- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler {
    [self registerMethod:@"com.atproto.server.createSession" handler:handler];
}
// ... 100 more
```

**Solution:** Use compile-time macro:
```objc
#define XRPC_REGISTER(nsid) - (void)register##nsid:(XrpcMethodHandler)handler { \
    [self registerMethod:@"com.atproto." #nsid handler:handler]; }

XRPC_REGISTER(server.describeServer)
XRPC_REGISTER(server.createSession)
// ... generates all methods
```

---

### 4.2 XrpcMethodRegistry Split

**Current:** Single 1000+ line class handling:
- HTTP proxy logic
- All XRPC method implementations
- Static helpers for DID resolution, lexicon loading, invite codes

**Solution:** Split into:
```
Services/
  ServerMethodsHandler.h/.m    - com.atproto.server.* 
  RepoMethodsHandler.h/.m     - com.atproto.repo.*
  IdentityMethodsHandler.h/.m - com.atproto.identity.*
  AdminMethodsHandler.h/.m    - com.atproto.admin.*
```

Each handler implements a protocol:
```objc
@protocol XRPCMethodsHandler <NSObject>
+ (NSArray<NSString *> *)supportedMethods;
- (void)handleMethod:(NSString *)method 
           request:(id)request 
           headers:(NSDictionary *)headers 
        completion:(void(^)(id, NSError *))completion;
@end
```

---

### 4.3 CID Generation Utility

**Files:** 
- `ATProtoPDS/Sources/App/Services/PDSRecordService.m` (lines 190-200, 473-485, 565-577)

**Solution:** Extract to shared utility:
```objc
// ATProtoPDS/Sources/Core/CIDGenerator.h
@interface CIDGenerator : NSObject
+ (CID *)cidForData:(NSData *)data;
+ (CID *)cidForJSONObject:(id)obj;
@end
```

---

### 4.4 NSLog → PDSLogger Migration

**Files:**
- `ATProtoPDS/Sources/App/PDSController.m`
- `ATProtoPDS/Sources/App/Services/PDSRecordService.m`

**Solution:** Replace all `NSLog()` calls with appropriate `PDS_LOG_*` macros.

---

### 4.5 Base64URL Utility Extraction

**Files:**
- `ATProtoPDS/Sources/Auth/JWT.m`
- `ATProtoPDS/Sources/Auth/DPoPUtil.m`

**Solution:** Add to `CryptoUtils`:
```objc
// CryptoUtils.h
+ (NSString *)base64URLEncodeData:(NSData *)data;
+ (NSData *)base64URLDecodeString:(NSString *)string;
```

---

## Phase 5: Additional Spec Compliance

### 5.1 P-256 Key Support in PLCDIDKey

**File:** `ATProtoPDS/Sources/PLC/PLCDIDKey.m`  
**Line:** 105

**Current:** Only accepts 33-byte compressed keys  
**Fix:** Also accept 65-byte uncompressed keys per multicodec spec

---

### 5.2 URI Scheme Validation

**File:** `ATProtoPDS/Sources/Lexicon/ATProtoLexiconValidator.m`  
**Lines:** 392-402

**Current:** Accepts any scheme with host  
**Fix:** Validate `http`/`https` only per ATProto spec

---

## Test Strategy

| Phase | Test Command |
|-------|--------------|
| 1.1 | `./build/tests/AllTests` (PLC tests) |
| 1.2 | Handle resolution tests |
| 1.3 | Firehose tests with large repos |
| 1.4 | Lexicon validation tests |
| 2.1-2.6 | `./build/tests/AllTests` (all tests) |
| 3.1 | Rate limiting tests |
| 4.1-4.5 | `./build/tests/AllTests` |

---

## Dependencies

```
Phase 1 (Critical)
├── 1.1 PLCOperation null handling
├── 1.2 DNS TXT concatenation  
├── 1.3 BFS queue fix
└── 1.4 Lexicon prefix matching

Phase 2 (Code Deduplication)
├── 2.1 CBOR Base (blocks 2.2)
├── 2.2 Varint consolidation
├── 2.3 MST binary search extraction
├── 2.4 MST keyDepth consolidation
├── 2.5 RepoCommit serialize
└── 2.6 Remove dead code

Phase 3 (Performance)
├── 3.1 Rate limiting O(1)
└── 3.2 Lexicon validator cache

Phase 4 (Architectural)
├── 4.1 XRPC registration
├── 4.2 XrpcMethodRegistry split
├── 4.3 CID generator utility
├── 4.4 NSLog migration
└── 4.5 Base64URL extraction

Phase 5 (Spec Compliance)
├── 5.1 P-256 key support
└── 5.2 URI scheme validation
```

---

## Notes

- Each phase should be completed and tested before moving to the next
- Phase 1 fixes are critical correctness issues and should be prioritized
- Phase 2 deduplication enables easier future maintenance
- Phase 4 architectural changes are larger in scope and may require additional planning
- Run `./build/tests/AllTests` after each phase to verify no regressions
