---
title: CID and Hashing
---

# CID and Hashing

## Overview

CID (Content Identifier) is a self-describing content address that combines a hash function, hash digest, and codec. It enables content-addressed storage and verification.

## CID Structure

```

CIDv1: z<multibase><multicodec><multihash>

Example: zbafy2bzaced4ueelaegfs5fq4a3fvh2ijmmq7xjlmakivezbsxyhynaiksqq

z       - multibase (base32)
bafy    - multicodec (dag-cbor)
2bzaced... - multihash (sha256 hash)
```

## Multihash Format

```

<hash-function-code><digest-length><digest>

Example: 12 20 <32-byte-sha256-hash>

12      - SHA-256 code
20      - 32 bytes (hex)
<hash>  - 32-byte SHA-256 digest
```

## CID Class

The `CID` class provides methods for creating, parsing, and working with content identifiers:

```objc
@interface CID : NSObject

// Creating CIDs from digest and codec
+ (nullable instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec;

// Creating CIDs from multihash
+ (nullable instancetype)cidWithMultihash:(NSData *)multihash codec:(NSUInteger)codec;

// Parsing CIDs from string or bytes
+ (nullable instancetype)cidFromString:(NSString *)string;
+ (nullable instancetype)cidFromBytes:(NSData *)data;

// Properties
@property (nonatomic, readonly) NSUInteger version;
@property (nonatomic, readonly) NSUInteger codec;
@property (nonatomic, readonly) NSData *multihash;
@property (nonatomic, readonly) NSData *bytes;
@property (nonatomic, readonly) NSString *stringValue;

// Comparison
- (BOOL)isEqualToCID:(CID *)other;

// Hashing
+ (CID *)sha256:(NSData *)data;
+ (NSData *)sha256Digest:(NSData *)data;

@end
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 1-150)

## Hashing

### SHA-256 Hashing

```objc
// 1. Encode record to CBOR
NSError *error = nil;
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record 
                                                                error:&error];

// 2. Hash with SHA-256
NSData *hash = [CID sha256Digest:cborData];

// 3. Create CID with dag-cbor codec (0x71)
CID *cid = [CID cidWithDigest:hash codec:0x71];
NSString *cidString = cid.stringValue;  // "bafy2bzaced..."
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 280-295)

## Creating CIDs

### From Digest and Codec

```objc
// 1. Hash content with SHA-256
NSData *content = [@"Hello, world!" dataUsingEncoding:NSUTF8StringEncoding];
NSData *hash = [CID sha256Digest:content];

// 2. Create CID with dag-cbor codec (0x71)
CID *cid = [CID cidWithDigest:hash codec:0x71];

// 3. Get string representation
NSString *cidString = cid.stringValue;  // "bafy2bzaced..."

// 4. Get binary representation
NSData *cidBytes = cid.bytes;
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 35-50, 155-175)

### For Records

```objc
// 1. Create record
NSDictionary *post = @{
    @"text": @"Hello!",
    @"createdAt": @"2025-01-15T10:30:00Z"
};

// 2. Encode to DAG-CBOR
NSError *error = nil;
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:post 
                                                                error:&error];
if (!cborData) {
    NSLog(@"Encoding failed: %@", error);
    return;
}

// 3. Hash with SHA-256
NSData *hash = [CID sha256Digest:cborData];

// 4. Create CID (0x71 = dag-cbor codec)
CID *recordCid = [CID cidWithDigest:hash codec:0x71];

// 5. Use CID for storage and retrieval
NSString *cidString = recordCid.stringValue;  // "bafy2bzaced..."
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 35-50, 155-175, 280-295)

### For Blocks

```objc
// 1. Encode block to DAG-CBOR
NSError *error = nil;
NSData *blockData = [ATProtoCBORSerialization encodeDataWithJSONObject:blockObject 
                                                                 error:&error];
if (!blockData) {
    NSLog(@"Encoding failed: %@", error);
    return;
}

// 2. Hash with SHA-256
NSData *hash = [CID sha256Digest:blockData];

// 3. Create CID
CID *blockCid = [CID cidWithDigest:hash codec:0x71];

// 4. Create CAR block
CARBlock *carBlock = [CARBlock blockWithCID:blockCid data:blockData];

// 5. Add to CAR archive
CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
[writer addBlock:carBlock];
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 35-50, 155-175, 280-295); `Garazyk/Sources/Repository/CAR.m` (lines 280-320)

## Parsing CIDs

### From String

```objc
// 1. Parse CID from string (base32 encoded with 'b' prefix)
NSError *error = nil;
CID *cid = [CID cidFromString:@"bafy2bzaced4ueelaegfs5fq4a3fvh2ijmmq7xjlmakivezbsxyhynaiksqq"];

if (cid) {
    NSUInteger version = cid.version;           // 1
    NSUInteger codec = cid.codec;               // 0x71 (dag-cbor)
    NSData *multihash = cid.multihash;          // hash bytes
    NSString *cidString = cid.stringValue;      // "bafy2bzaced..."
    
    NSLog(@"CID Version: %lu", (unsigned long)version);
    NSLog(@"CID Codec: 0x%lx", (unsigned long)codec);
    NSLog(@"CID String: %@", cidString);
} else {
    NSLog(@"Failed to parse CID");
}
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 65-85, 155-175)

### From Bytes

```objc
// 1. Parse CID from binary bytes
NSData *cidBytes = /* ... */;
CID *cidFromBytes = [CID cidFromBytes:cidBytes];

if (cidFromBytes) {
    // Access CID properties
    NSData *binaryForm = cidFromBytes.bytes;
    NSString *stringForm = cidFromBytes.stringValue;
}
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 87-110, 155-175)

### Comparing CIDs

```objc
// 1. Compare two CIDs
CID *cid1 = [CID cidFromString:@"bafy2bzaced..."];
CID *cid2 = [CID cidFromString:@"bafy2bzaced..."];

if ([cid1 isEqualToCID:cid2]) {
    NSLog(@"CIDs match");
} else {
    NSLog(@"CIDs differ");
}

// 2. Use in collections
NSMutableSet *cidSet = [NSMutableSet set];
[cidSet addObject:cid1];

if ([cidSet containsObject:cid2]) {
    NSLog(@"CID found in set");
}
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 177-195)

## Validation

### Verifying Content Integrity

```objc
// 1. Get content by CID
NSError *error = nil;
CID *cid = [CID cidFromString:cidString];
if (!cid) {
    NSLog(@"Invalid CID");
    return NO;
}

// 2. Retrieve content (from storage, network, etc.)
NSData *content = [blobService getBlob:cid forDid:userDid error:&error];
if (!content) {
    NSLog(@"Failed to retrieve content: %@", error);
    return NO;
}

// 3. Hash the retrieved content
NSData *hash = [CID sha256Digest:content];

// 4. Extract the digest from the CID's multihash
// Multihash format: [hash-function-code][digest-length][digest]
// For SHA-256: 0x12 (code) + 0x20 (32 bytes) + [32-byte digest]
NSData *multihash = cid.multihash;
if (multihash.length < 34) {
    NSLog(@"Invalid multihash length");
    return NO;
}

// Skip the first 2 bytes (hash code and length) to get the digest
NSData *cidDigest = [multihash subdataWithRange:NSMakeRange(2, 32)];

// 5. Verify the hashes match
if ([hash isEqualToData:cidDigest]) {
    NSLog(@"Content verified!");
    return YES;
} else {
    NSLog(@"Content corrupted!");
    return NO;
}
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 280-295); `Garazyk/Sources/Blob/BlobStorage.m` (lines 95-115)

## CIDv0 vs CIDv1

### CIDv0 (Legacy)

```

Qm... (base58 encoded)
- Only supports dag-pb codec
- Shorter but less flexible
```

### CIDv1 (Current)

```

bafy... (base32 encoded)
- Supports multiple codecs
- Self-describing
- Recommended for new code
```

### Conversion

```objc
// Convert v0 to v1
NSError *error = nil;
NSString *cidv1 = [CID convertCIDv0toV1:@"Qm..." error:&error];

// Result: bafy...
```

## Best Practices

1. **CID Generation**
   - Use CIDv1 for new content
   - Use SHA-256 for hashing
   - Use dag-cbor for records
   - Verify CID matches content

2. **Storage**
   - Store content by CID
   - Deduplicate by CID
   - Verify on retrieval
   - Cache CID lookups

3. **Transmission**
   - Include CID with content
   - Verify CID on receipt
   - Use CID for integrity checks
   - Support both v0 and v1

4. **Performance**
   - Cache hash computations
   - Batch CID generation
   - Use streaming for large content
   - Monitor hash time

## Common Patterns

### Storing a Record with CID

```objc
// 1. Create record
NSDictionary *post = @{
    @"text": @"Hello!",
    @"createdAt": @"2025-01-15T10:30:00Z"
};

// 2. Encode and hash
NSError *error = nil;
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:post 
                                                                error:&error];
if (!cborData) {
    NSLog(@"Encoding failed: %@", error);
    return;
}

NSData *hash = [CID sha256Digest:cborData];
CID *cid = [CID cidWithDigest:hash codec:0x71];

// 3. Store record (service layer handles persistence)
// The CID is used as the record's content address
NSString *cidString = cid.stringValue;

// 4. Return CID to client
NSDictionary *response = @{
    @"uri": [NSString stringWithFormat:@"at://%@/app.bsky.feed.post/abc123", userDid],
    @"cid": cidString
};
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 35-50, 155-175, 280-295)

### Verifying Content Integrity

```objc
// 1. Get content
NSData *content = [blobService getBlob:cidData forDid:userDid error:&error];
if (!content) {
    NSLog(@"Failed to retrieve content: %@", error);
    return NO;
}

// 2. Verify CID
NSData *hash = [CID sha256Digest:content];
CID *cid = [CID cidFromString:cidString];

if (!cid) {
    NSLog(@"Invalid CID");
    return NO;
}

// 3. Extract digest from multihash
NSData *multihash = cid.multihash;
if (multihash.length < 34) {
    NSLog(@"Invalid multihash");
    return NO;
}

NSData *cidDigest = [multihash subdataWithRange:NSMakeRange(2, 32)];

// 4. Compare hashes
if (![hash isEqualToData:cidDigest]) {
    NSLog(@"Content corrupted!");
    return NO;
}

return YES;
```

**Source:** `Garazyk/Sources/Core/CID.m` (lines 280-295); `Garazyk/Sources/Blob/BlobStorage.m` (lines 95-115)

## See Also

- [CBOR Serialization](cbor-serialization)
- [CAR Format](car-format)
- [Blob Storage](blob-storage)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

