# Chapter 5: CBOR Serialization

CBOR (Concise Binary Object Representation) is like JSON's more efficient binary cousin. In the AT Protocol, we use a specific subset called **DAG-CBOR** that adds deterministic encoding rules and CID links. This chapter covers implementing a full CBOR encoder and decoder.

## What is CBOR?

CBOR is defined in [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949.html). Compared to JSON:

| Feature | JSON | CBOR |
|---------|------|------|
| Format | Text | Binary |
| Size | Larger | Compact |
| Types | 6 | 8+ major types |
| Binary data | Base64 encoding | Native |
| Determinism | No | Optional (DAG-CBOR requires it) |

## CBOR Major Types

Every CBOR value starts with an "initial byte" containing the major type (3 bits) and additional info (5 bits):

```
Initial Byte: [Major Type (3 bits)][Additional Info (5 bits)]
```

| Major | Type | Example |
|-------|------|---------|
| 0 | Unsigned integer | `0`, `1`, `100` |
| 1 | Negative integer | `-1`, `-100` |
| 2 | Byte string | Binary data |
| 3 | Text string | UTF-8 text |
| 4 | Array | Ordered list |
| 5 | Map | Key-value pairs |
| 6 | Tag | Semantic annotation |
| 7 | Simple/Float | `null`, `true`, `false`, floats |

### Additional Info Encoding

The 5-bit additional info field encodes the argument (length or value):

| Value | Meaning |
|-------|---------|
| 0-23 | Literal value |
| 24 | Next 1 byte |
| 25 | Next 2 bytes (big-endian) |
| 26 | Next 4 bytes (big-endian) |
| 27 | Next 8 bytes (big-endian) |

## DAG-CBOR Constraints

DAG-CBOR adds rules for deterministic, content-addressable encoding:

1. **Definite lengths only**: No streaming/indefinite-length items
2. **Canonical integer encoding**: Use smallest possible representation
3. **Sorted map keys**: Sort by encoded byte representation (length-first)
4. **CID links**: Use tag 42 (`0xD82A`) for content identifier links
5. **No floats**: Only integers (to avoid floating-point issues)

## The CBORValue Class

We represent CBOR values with a tagged union pattern:

```objc
// CBOR.h
typedef NS_ENUM(NSInteger, CBORType) {
    CBORTypeUnsignedInteger = 0,
    CBORTypeNegativeInteger = 1,
    CBORTypeByteString = 2,
    CBORTypeTextString = 3,
    CBORTypeArray = 4,
    CBORTypeMap = 5,
    CBORTypeTag = 6,
    CBORTypeSimpleOrFloat = 7
};

@interface CBORValue : NSObject <NSCopying>

@property (nonatomic, assign, readonly) CBORType type;
@property (nonatomic, strong, readonly, nullable) NSNumber *unsignedInteger;
@property (nonatomic, strong, readonly, nullable) NSData *byteString;
@property (nonatomic, copy, readonly, nullable) NSString *textString;
@property (nonatomic, copy, readonly, nullable) NSArray<CBORValue *> *array;
@property (nonatomic, copy, readonly, nullable) NSDictionary<CBORValue *, CBORValue *> *map;
@property (nonatomic, strong, readonly, nullable) NSNumber *tag;
@property (nonatomic, strong, readonly, nullable) CBORValue *tagValue;

// Factory methods
+ (instancetype)unsignedInteger:(NSUInteger)value;
+ (instancetype)textString:(NSString *)string;
+ (instancetype)byteString:(NSData *)data;
+ (instancetype)array:(NSArray<CBORValue *> *)array;
+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map;
+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value;
+ (instancetype)nilValue;

- (NSData *)encode;
+ (nullable instancetype)decode:(NSData *)data;

@end
```

### Factory Method Implementations

```objc
// CBOR.m
+ (instancetype)unsignedInteger:(NSUInteger)value {
    return [[self alloc] initWithUnsignedNumber:@(value)];
}

+ (instancetype)textString:(NSString *)string {
    return [[self alloc] initWithTextString:string];
}

+ (instancetype)byteString:(NSData *)data {
    return [[self alloc] initWithByteString:data];
}

+ (instancetype)array:(NSArray<CBORValue *> *)array {
    return [[self alloc] initWithArray:array];
}

+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map {
    return [[self alloc] initWithMap:map];
}

+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value {
    return [[self alloc] initWithTag:@(tag) value:value];
}

+ (instancetype)nilValue {
    return [self simple:22];  // CBOR null = simple value 22
}
```

## CBOR Encoding

### Encoding Integers

Integers are encoded with the smallest possible representation:

```objc
+ (void)encodeUnsignedInteger:(NSUInteger)value toData:(NSMutableData *)data {
    if (value < 24) {
        // Fits in additional info field
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    } else if (value < 256) {
        // 1 additional byte
        uint8_t bytes[2] = { 0x18, (uint8_t)value };
        [data appendBytes:bytes length:2];
    } else if (value < 65536) {
        // 2 additional bytes (big-endian)
        uint8_t major = 0x19;
        [data appendBytes:&major length:1];
        uint16_t be = OSSwapHostToBigInt16((uint16_t)value);
        [data appendBytes:&be length:2];
    } else if (value < 4294967296ULL) {
        // 4 additional bytes
        uint8_t major = 0x1A;
        [data appendBytes:&major length:1];
        uint32_t be = OSSwapHostToBigInt32((uint32_t)value);
        [data appendBytes:&be length:4];
    } else {
        // 8 additional bytes
        uint8_t major = 0x1B;
        [data appendBytes:&major length:1];
        uint64_t be = OSSwapHostToBigInt64(value);
        [data appendBytes:&be length:8];
    }
}
```

**Examples:**
- `0` → `0x00`
- `23` → `0x17`
- `24` → `0x18 0x18`
- `256` → `0x19 0x01 0x00`

### Encoding Strings

Text strings use major type 3, byte strings use major type 2:

```objc
+ (void)encodeTextString:(NSString *)string toData:(NSMutableData *)data {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = utf8.length;
    [self encodeCount:length withMajorType:0x60 toData:data];  // Major type 3
    [data appendData:utf8];
}

+ (void)encodeByteString:(NSData *)bytes toData:(NSMutableData *)output {
    NSUInteger length = bytes.length;
    [self encodeCount:length withMajorType:0x40 toData:output];  // Major type 2
    [output appendData:bytes];
}

+ (void)encodeCount:(NSUInteger)count withMajorType:(uint8_t)majorType toData:(NSMutableData *)data {
    if (count < 24) {
        uint8_t byte = majorType | (uint8_t)count;
        [data appendBytes:&byte length:1];
    } else if (count < 256) {
        uint8_t bytes[2] = { majorType | 24, (uint8_t)count };
        [data appendBytes:bytes length:2];
    } else if (count < 65536) {
        uint8_t bytes[3] = { majorType | 25 };
        uint16_t be = OSSwapHostToBigInt16((uint16_t)count);
        memcpy(bytes + 1, &be, 2);
        [data appendBytes:bytes length:3];
    } else {
        uint8_t bytes[5] = { majorType | 26 };
        uint32_t be = OSSwapHostToBigInt32((uint32_t)count);
        memcpy(bytes + 1, &be, 4);
        [data appendBytes:bytes length:5];
    }
}
```

### Encoding Maps with DAG-CBOR Sorting

DAG-CBOR requires map keys to be sorted by their encoded representation (length-first, then lexicographic):

```objc
+ (void)encodeMap:(NSDictionary<CBORValue *, CBORValue *> *)map 
           toData:(NSMutableData *)output {
    NSUInteger count = map.count;
    [self encodeCount:count withMajorType:0xA0 toData:output];  // Major type 5
    
    if (count == 0) return;
    
    // Sort keys by their encoded byte representation
    NSArray *keys = [map allKeys];
    NSArray *sortedKeys = [keys sortedArrayUsingComparator:^NSComparisonResult(CBORValue *key1, CBORValue *key2) {
        NSData *d1 = [key1 encode];
        NSData *d2 = [key2 encode];
        
        // DAG-CBOR: shorter keys first, then lexicographic
        NSUInteger len1 = d1.length;
        NSUInteger len2 = d2.length;
        NSUInteger minLen = MIN(len1, len2);
        
        int cmp = memcmp(d1.bytes, d2.bytes, minLen);
        if (cmp != 0) return cmp < 0 ? NSOrderedAscending : NSOrderedDescending;
        if (len1 < len2) return NSOrderedAscending;
        if (len1 > len2) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // Encode sorted key-value pairs
    for (CBORValue *key in sortedKeys) {
        [self encodeValue:key toData:output];
        [self encodeValue:map[key] toData:output];
    }
}
```

### Encoding Tags (CID Links)

Tags wrap other values with semantic meaning. Tag 42 is reserved for CID links:

```objc
+ (void)encodeTag:(NSUInteger)tag value:(CBORValue *)value toData:(NSMutableData *)data {
    [self encodeCount:tag withMajorType:0xC0 toData:data];  // Major type 6
    [self encodeValue:value toData:data];
}
```

**Example: Encoding a CID link**
```objc
// Create CID link (tag 42)
NSData *cidBytes = /* CID binary data */;
NSMutableData *linkData = [NSMutableData dataWithBytes:"\x00" length:1];  // Multibase identity prefix
[linkData appendData:cidBytes];

CBORValue *cidLink = [CBORValue tag:42 value:[CBORValue byteString:linkData]];
NSData *encoded = [cidLink encode];
// 0xD8 0x2A <byte string with CID>
```

## CBOR Decoding

### The Decoder Structure

```objc
+ (CBORValue *)decode:(NSData *)data offset:(NSUInteger *)offset {
    if (*offset >= data.length) return nil;

    const uint8_t *bytes = data.bytes;
    uint8_t initial = bytes[(*offset)++];
    uint8_t majorType = (initial & 0xE0) >> 5;  // Top 3 bits
    uint8_t additional = initial & 0x1F;         // Bottom 5 bits

    switch (majorType) {
        case 0: return [self decodeUnsignedInteger:additional data:data offset:offset];
        case 1: return [self decodeNegativeInteger:additional data:data offset:offset];
        case 2: return [self decodeByteString:additional data:data offset:offset];
        case 3: return [self decodeTextString:additional data:data offset:offset];
        case 4: return [self decodeArray:additional data:data offset:offset];
        case 5: return [self decodeMap:additional data:data offset:offset];
        case 6: return [self decodeTag:additional data:data offset:offset];
        case 7: return [self decodeSimpleOrFloat:additional data:data offset:offset];
        default: return nil;
    }
}
```

### Decoding Integers

```objc
+ (CBORValue *)decodeUnsignedInteger:(uint8_t)additional 
                               data:(NSData *)data 
                             offset:(NSUInteger *)offset {
    NSUInteger value = 0;
    
    if (additional < 24) {
        value = additional;  // Value in additional info
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (*offset + bytesToRead > data.length) return nil;
        
        const uint8_t *bytes = data.bytes;
        for (NSUInteger i = 0; i < bytesToRead; i++) {
            value = (value << 8) | bytes[*offset + i];
        }
        *offset += bytesToRead;
    }
    
    return [CBORValue unsignedInteger:value];
}

+ (NSUInteger)bytesToReadForAdditional:(uint8_t)additional {
    switch (additional) {
        case 24: return 1;
        case 25: return 2;
        case 26: return 4;
        case 27: return 8;
        default: return 0;
    }
}
```

### Decoding Strings

```objc
+ (CBORValue *)decodeTextString:(uint8_t)additional 
                          data:(NSData *)data 
                        offset:(NSUInteger *)offset {
    // Read length
    NSUInteger length = 0;
    if (additional < 24) {
        length = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        length = [self readIntegerFromData:data offset:offset bytesToRead:bytesToRead];
        *offset += bytesToRead;
    }
    
    // Read UTF-8 bytes
    if (*offset + length > data.length) return nil;
    NSData *valueData = [data subdataWithRange:NSMakeRange(*offset, length)];
    *offset += length;
    
    NSString *value = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
    return [CBORValue textString:value ?: @""];
}
```

## Practical Example: Encoding an AT Protocol Record

Let's encode a simple Bluesky post record:

```objc
// Create the record structure
NSDictionary<CBORValue *, CBORValue *> *record = @{
    [CBORValue textString:@"$type"]: [CBORValue textString:@"app.bsky.feed.post"],
    [CBORValue textString:@"createdAt"]: [CBORValue textString:@"2024-01-01T00:00:00Z"],
    [CBORValue textString:@"text"]: [CBORValue textString:@"Hello from NSPds!"]
};

CBORValue *cborRecord = [CBORValue map:record];
NSData *encoded = [cborRecord encode];

// Hash to get CID
CID *recordCID = [CID cidWithDigest:[CID rawSha256:encoded] codec:0x71];  // dag-cbor
NSLog(@"Record CID: %@", recordCID.stringValue);
```

**Encoded bytes breakdown:**
```
A3                     # Map with 3 entries
   65                  # Text string, 5 bytes
      2474797065       # "$type"
   72                  # Text string, 18 bytes  
      6170702E62...    # "app.bsky.feed.post"
   69                  # Text string, 9 bytes
      6372656174...    # "createdAt"
   ...
```

## Testing CBOR Implementation

```objc
- (void)testRoundTrip {
    NSDictionary<CBORValue *, CBORValue *> *original = @{
        [CBORValue textString:@"name"]: [CBORValue textString:@"Alice"],
        [CBORValue textString:@"age"]: [CBORValue unsignedInteger:30]
    };
    
    CBORValue *value = [CBORValue map:original];
    NSData *encoded = [value encode];
    CBORValue *decoded = [CBORValue decode:encoded];
    
    XCTAssertTrue([value isEqual:decoded]);
}

- (void)testMapKeySorting {
    // Keys should be sorted by encoded length, then lexicographically
    NSDictionary<CBORValue *, CBORValue *> *map = @{
        [CBORValue textString:@"bb"]: [CBORValue unsignedInteger:2],
        [CBORValue textString:@"a"]: [CBORValue unsignedInteger:1],
        [CBORValue textString:@"aaa"]: [CBORValue unsignedInteger:3]
    };
    
    CBORValue *value = [CBORValue map:map];
    NSData *encoded = [value encode];
    
    // Expected order: "a" (1 char), "bb" (2 chars), "aaa" (3 chars)
    // ...verify encoded byte order
}
```

## Summary

In this chapter, you learned:

- ✅ CBOR major types and encoding structure
- ✅ DAG-CBOR additional constraints for determinism
- ✅ Encoding integers with minimal byte representation
- ✅ Encoding strings, arrays, and maps
- ✅ Canonical map key sorting (length-first)
- ✅ Tag 42 for CID links
- ✅ Decoding CBOR binary data

## Next Steps

In **Chapter 6**, we'll implement **Merkle Search Trees (MST)**—the data structure that organizes records in AT Protocol repositories, using CBOR for node serialization.

---

**Files Referenced in This Chapter:**
- [CBOR.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/CBOR.h)
- [CBOR.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Repository/CBOR.m)
