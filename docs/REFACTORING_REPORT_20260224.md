# Code Review: Refactoring Opportunities

**Date:** 2026-02-24  
**Scope:** Data Structures, API Design, Algorithms, ATProto Spec Compliance

---

## Status: COMPLETED

The following items were fixed in this session:

- ✅ **1.1 PLCOperation null handling** - Fixed at `PLCOperation.m:194-202`
- ✅ **1.2 DNS TXT concatenation** - Fixed at `HandleResolver.m:361-391`
- ✅ **1.3 BFS queue O(n²)** - Fixed at `SubscribeReposHandler.m:792-806`
- ✅ **1.4 Lexicon $type prefix matching** - Fixed at `ATProtoLexiconValidator.m:61-80`
- ✅ **2.3 MST binary search extraction** - Added `binarySearchIndexForKey:` and `subtreeAtIndex:` helpers to `MST.m`
- ✅ **2.4 MST keyDepth consolidation** - Consolidated to single `keyDepthFromBytes:` method in `MST.m`
- ✅ **2.5 RepoCommit serialize deduplication** - Consolidated to single `serializeWithSignature:` method in `RepoCommit.m`
- ✅ **2.6 Dead code removal** - Removed unused `connectionsByFileDescriptor` from `WebSocketServer.m`
- ✅ **3.1 Rate limiting** - Improved at `HandleResolver.m:392-420`
- ✅ **3.2 Lexicon validator caching** - Added static caching at `ATProtoLexiconValidator.m:10-31`
- ✅ **5.1 P-256 uncompressed key support** - Added `compressP256PublicKey:` helper in `PLCDIDKey.m`
- ✅ **5.2 URI scheme validation** - Added http/https validation in `ATProtoLexiconValidator.m`

---

## High Priority (Spec Compliance / Correctness)

### PLCOperation null handling
- **Location:** `PLCOperation.m:195-202`
- **Issue:** `toDictionary` includes `prev: null` - ATProto spec omits null fields from DAG-CBOR encoding
- **Impact:** Will cause CID mismatches during verification
- **Fix:** Remove null fields from dictionary before serialization

### DNS TXT concatenation
- **Location:** `HandleResolver.m:357-374`
- **Issue:** Assumes single string per TXT record
- **Impact:** ATProto spec allows multiple strings per TXT record (concatenated)
- **Fix:** Handle multiple strings in DNS TXT parsing

### BFS queue O(n²)
- **Location:** `SubscribeReposHandler.m:792-806`
- **Issue:** Uses `NSMutableArray` with `removeObjectAtIndex:0` - O(n) per removal
- **Impact:** Quadratic complexity for large MST traversals
- **Fix:** Replace with proper queue (deque) or NSMutableData with head pointer

### $type prefix matching
- **Location:** `ATProtoLexiconValidator.m:62-69`
- **Issue:** `$type` matching collection is too strict
- **Impact:** ATProto allows `$type` to be a prefix NSID (e.g., `app.bsky.feed.post` matches `app.bsky.feed.post#main`)
- **Fix:** Support NSID prefix matching

---

## Medium Priority (Design/Performance)

### CBOR duplication
- **Location:** `CBOR.m` vs `ATProtoDagCBOR.m`
- **Issue:** ~80% code duplication between CBOR and DAG-CBOR implementations
- **Fix:** Extract shared base class or category

### Varint duplication
- **Location:** CAR.m, CBOR.m, PLCDIDKey.m
- **Issue:** Varint encoding/decoding duplicated in multiple files
- **Fix:** Single varint utility class

### MST binary search duplication
- **Location:** `MST.m` - `getRecursive`, `deleteRecursive`, `addRecursive`
- **Issue:** Identical binary search patterns in three methods
- **Fix:** Extract to helper method

### Rate limiting O(n)
- **Location:** `HandleResolver.m:382-401`
- **Issue:** Uses `NSMutableArray` with O(n) filtering
- **Fix:** Use `NSMutableIndexSet` or circular buffer for O(1) operations

### Boilerplate XRPC registration
- **Location:** `XrpcHandler.m:102-516`
- **Issue:** ~400 lines of near-identical registration methods
- **Fix:** Macro or loop-based registration over NSID array

### XrpcMethodRegistry god class
- **Location:** `XrpcMethodRegistry.m`
- **Issue:** 1000+ lines, HTTP proxy + XRPC implementations + static helpers
- **Fix:** Split into per-namespace handler classes (server, repo, identity)

### Unused dictionary
- **Location:** `WebSocketServer.m:24`
- **Issue:** `connectionsByFileDescriptor` populated but never read
- **Fix:** Remove dead code

### RepoCommit serialize duplication
- **Location:** `RepoCommit.m:26-56 vs 63-97`
- **Issue:** `serialize` and `serializeSigned` duplicate nearly identical logic
- **Fix:** Single method with optional signature parameter

---

## Low Priority (Code Quality)

### NSLog in production
- **Locations:** `PDSController.m`, `PDSRecordService.m`
- **Issue:** Debug logging with NSLog
- **Fix:** Replace with `PDSLogger`

### Base64URL duplication
- **Locations:** `JWT.m`, `DPoPUtil.m`
- **Issue:** Base64URL encoding duplicated
- **Fix:** Extract to `CryptoUtils`

### Character set cache
- **Location:** `ATProtoLexiconValidator.m:431-432`
- **Issue:** Character set created every call
- **Fix:** Make static

### Regex cache
- **Location:** `ATProtoLexiconValidator.m:445-458`
- **Issue:** Creates new NSRegularExpression on every validation
- **Fix:** Cache compiled regex

### P-256 key support
- **Location:** `PLCDIDKey.m:105`
- **Issue:** Only accepts 33-byte compressed keys
- **Impact:** P-256 uncompressed (65 bytes) should also be accepted per multicodec spec
- **Fix:** Accept both formats

---

## Architectural Improvements

### 1. Shared CBOR Infrastructure
Create `CBORCodec` base class to eliminate duplication between `CBOR.m` and `ATProtoDagCBOR.m`

### 2. Service Layer Split
`XrpcMethodRegistry` should delegate to:
- `ServerMethodsHandler`
- `RepoMethodsHandler`
- `IdentityMethodsHandler`
- `ServerMethodsHandler`

### 3. Data Structure Improvements
Replace array-based BFS queue with proper deque for O(1) operations

### 4. Transport Abstraction
Extract macOS/Linux transport code in `HandleResolver.m` (lines 174-293) to abstraction layer

---

## Additional Findings

### CID Generation
- **Location:** `PDSRecordService.m:190-200, 473-485, 565-577`
- **Issue:** Duplicate CID generation logic
- **Fix:** Extract to shared utility method

### URI Validation
- **Location:** `ATProtoLexiconValidator.m:392-402`
- **Issue:** Accepts any scheme with host
- **Fix:** Validate `http`/`https` only per ATProto spec

### Grapheme Counting
- **Location:** `ATProtoLexiconValidator.m:276-281`
- **Issue:** Iterates all characters
- **Fix:** Use `-[NSString getGlyphs:count:]` for better performance
