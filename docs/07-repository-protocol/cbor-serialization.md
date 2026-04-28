---
title: CBOR Serialization
---

# CBOR Serialization

## Overview

CBOR (Concise Binary Object Representation) is used for serializing ATProto records and IPLD blocks. DAG-CBOR is a deterministic variant that ensures consistent hashing and content addressing.

## CBOR Basics

CBOR is a binary format that encodes JSON-like data structures efficiently:

```

JSON: {"name": "Alice", "age": 30}
CBOR: a2 64 6e 61 6d 65 65 41 6c 69 63 65 63 61 67 65 18 1e
      (binary representation)
```

## DAG-CBOR

DAG-CBOR adds constraints for deterministic encoding:

1. **Canonical ordering**: Map keys sorted by encoded bytes
2. **No floating point**: Only integers and rationals
3. **No undefined values**: All values must be defined
4. **No duplicate keys**: Each key appears once

## ATProtoCBORSerialization

The `ATProtoCBORSerialization` class handles CBOR encoding/decoding:

```objc
@interface ATProtoCBORSerialization : NSObject

// Encoding
+ (nullable NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error;

// Decoding
+ (nullable id)JSONObjectWithData:(NSData *)data error:(NSError **)error;

@end
```

**Source:** `Garazyk/Sources/Core/ATProtoCBORSerialization.m` (lines 1-50)

## Encoding Records

```objc
// Record to encode
NSDictionary *post = @{
    @"text": @"Hello, ATProto!",
    @"createdAt": @"2025-01-15T10:30:00Z",
    @"facets": @[]
};

// Encode to CBOR
NSError *error = nil;
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:post error:&error];

if (cborData) {
    // Use CBOR data for storage or transmission
    NSLog(@"Encoded %lu bytes", (unsigned long)cborData.length);
} else {
    NSLog(@"Encoding failed: %@", error);
}
```

**Source:** `Garazyk/Sources/Core/ATProtoCBORSerialization.m` (lines 8-20)

## Decoding Records

```objc
// CBOR data from storage
NSData *cborData = /* ... */;

// Decode from CBOR
NSError *error = nil;
id decoded = [ATProtoCBORSerialization JSONObjectWithData:cborData error:&error];

if (decoded && [decoded isKindOfClass:[NSDictionary class]]) {
    NSDictionary *record = (NSDictionary *)decoded;
    NSString *text = record[@"text"];
    NSString *createdAt = record[@"createdAt"];
    NSLog(@"Decoded record: %@", record);
} else {
    NSLog(@"Decoding failed: %@", error);
}
```

**Source:** `Garazyk/Sources/Core/ATProtoCBORSerialization.m` (lines 22-35)

## CID Generation

CIDs (Content Identifiers) are generated from CBOR-encoded data:

```objc
// 1. Encode record
NSError *error = nil;
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:record error:&error];

if (!cborData) {
    NSLog(@"Encoding failed: %@", error);
    return;
}

// 2. Hash with SHA-256
NSData *hash = [CID sha256Digest:cborData];

// 3. Create CID (0x71 = dag-cbor codec)
CID *cid = [CID cidWithDigest:hash codec:0x71];
NSString *cidString = cid.stringValue;  // "bafy2bzaced..."
```

**Source:** `Garazyk/Sources/Core/ATProtoCBORSerialization.m` (lines 8-20); `Garazyk/Sources/Core/CID.m` (lines 280-295)

## Validation

### Canonical Ordering

Map keys must be sorted by encoded bytes:

```objc
// Valid (keys sorted)
{
  "a": 1,
  "b": 2,
  "c": 3
}

// Invalid (keys not sorted)
{
  "c": 3,
  "a": 1,
  "b": 2
}
```

### No Floating Point

Only integers are allowed:

```objc
// Valid
@{@"count": @42}

// Invalid
@{@"count": @42.5}
```

### Deterministic Encoding

Same object always encodes to same bytes:

```objc
NSData *encoded1 = [ATProtoCBORSerialization encodeRecord:record error:&error];
NSData *encoded2 = [ATProtoCBORSerialization encodeRecord:record error:&error];

// encoded1 == encoded2 (byte-for-byte identical)
```

## Common Patterns

### Encoding a Post

```objc
NSDictionary *post = @{
    @"text": @"Hello world!",
    @"createdAt": @"2025-01-15T10:30:00Z",
    @"facets": @[],
    @"reply": @{
        @"root": @{
            @"uri": @"at://...",
            @"cid": @"bafy..."
        },
        @"parent": @{
            @"uri": @"at://...",
            @"cid": @"bafy..."
        }
    }
};

NSError *error = nil;
NSData *cborData = [ATProtoCBORSerialization encodeDataWithJSONObject:post error:&error];

if (cborData) {
    // Generate CID
    NSData *hash = [CID sha256Digest:cborData];
    CID *cid = [CID cidWithDigest:hash codec:0x71];
    
    NSLog(@"Post encoded to CBOR: %lu bytes", (unsigned long)cborData.length);
    NSLog(@"Post CID: %@", cid.stringValue);
    
    // Store record (service layer handles persistence)
    // The CID is used as the record's content address
} else {
    NSLog(@"Encoding failed: %@", error);
}
```

**Source:** `Garazyk/Sources/Core/ATProtoCBORSerialization.m` (lines 8-20, 37-100); `Garazyk/Sources/Core/CID.m` (lines 280-295)

### Decoding and Validating

```objc
NSData *cborData = /* from storage */;

// Decode
NSError *error = nil;
id decoded = [ATProtoCBORSerialization JSONObjectWithData:cborData error:&error];

if (!decoded) {
    NSLog(@"Decode failed: %@", error);
    return;
}

if (![decoded isKindOfClass:[NSDictionary class]]) {
    NSLog(@"Decoded object is not a dictionary");
    return;
}

NSDictionary *record = (NSDictionary *)decoded;

// Validate required fields
if (!record[@"text"] || !record[@"createdAt"]) {
    NSLog(@"Missing required fields");
    return;
}

// Use record
NSString *text = record[@"text"];
NSString *createdAt = record[@"createdAt"];
NSLog(@"Record text: %@", text);
```

**Source:** `Garazyk/Sources/Core/ATProtoCBORSerialization.m` (lines 22-35, 37-100)

## Best Practices

1. **Encoding**
   - Always use DAG-CBOR for determinism
   - Validate canonical ordering
   - Use integers, not floats
   - Avoid undefined values

2. **Decoding**
   - Validate CBOR format
   - Check for required fields
   - Handle missing optional fields
   - Validate field types

3. **Storage**
   - Store CBOR data, not JSON
   - Generate CID from CBOR
   - Verify CID matches content
   - Use CID for deduplication

4. **Performance**
   - Cache encoded CBOR
   - Reuse serialization objects
   - Batch encoding operations
   - Monitor encoding time

## See Also

- [CAR Format](car-format)
- [CID and Hashing](cid-and-hashing)
- [Repository Basics](repository-basics)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

