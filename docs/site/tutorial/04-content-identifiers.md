# Chapter 4: Content Identifiers (CIDs) & Hashing

<script setup>
const varintCode = `#import <Foundation/Foundation.h>

void encodeVarint(uint64_t value) {
    NSMutableData *data = [NSMutableData dataWithCapacity:9];
    uint64_t v = value;
    
    do {
        uint8_t byte = v & 0x7F;  // Take low 7 bits
        v >>= 7;                   // Shift by 7
        if (v != 0) {
            byte |= 0x80;          // Set continuation bit
        }
        [data appendBytes:&byte length:1];
    } while (v != 0);
    
    NSLog(@"Value: %llu (0x%llX) -> Encoded: %@", value, value, data);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        encodeVarint(0x01);    // 1
        encodeVarint(0x71);    // 113
        encodeVarint(0x200);   // 512
        encodeVarint(0xFACE);  // 64206
    }
    return 0;
}`;

const base32Code = `static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

NSString *base32Encode(NSData *data) {
    if (!data || data.length == 0) return @"";

    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSMutableString *result = [NSMutableString string];

    uint64_t buffer = 0;
    int bitsLeft = 0;
    
    for (NSUInteger i = 0; i < length; i++) {
        buffer = (buffer << 8) | bytes[i];
        bitsLeft += 8;
        
        while (bitsLeft >= 5) {
            int shift = bitsLeft - 5;
            [result appendFormat:@"%c", kBase32Alphabet[(buffer >> shift) & 0x1F]];
            bitsLeft -= 5;
        }
        buffer &= ((1ULL << bitsLeft) - 1);
    }

    if (bitsLeft > 0) {
        [result appendFormat:@"%c", kBase32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]];
    }

    return [result copy];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSData *hello = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
        
        NSLog(@"Input: %@", [[NSString alloc] initWithData:hello encoding:NSUTF8StringEncoding]);
        NSLog(@"Base32: %@", base32Encode(hello));
    }
    return 0;
}`;

const fullCidCode = `#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

// --- Minimal CID Implementation ---

@interface CID : NSObject
@property (readonly) NSUInteger version;
@property (readonly) NSUInteger codec;
@property (readonly) NSData *multihash;
+ (instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec;
- (NSString *)stringValue;
@end

static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

@implementation CID

+ (NSData *)encodeVarint:(uint64_t)val {
    NSMutableData *d = [NSMutableData data];
    do {
        uint8_t byte = val & 0x7F;
        val >>= 7;
        if (val) byte |= 0x80;
        [d appendBytes:&byte length:1];
    } while (val);
    return d;
}

+ (NSString *)base32Encode:(NSData *)data {
    if (!data.length) return @"";
    const uint8_t *bytes = data.bytes;
    NSMutableString *res = [NSMutableString string];
    uint64_t buf = 0;
    int bits = 0;
    for (NSUInteger i = 0; i < data.length; i++) {
        buf = (buf << 8) | bytes[i];
        bits += 8;
        while (bits >= 5) {
            [res appendFormat:@"%c", kBase32Alphabet[(buf >> (bits -= 5)) & 0x1F]];
        }
        buf &= ((1ULL << bits) - 1);
    }
    if (bits > 0) [res appendFormat:@"%c", kBase32Alphabet[(buf << (5 - bits)) & 0x1F]];
    return res;
}

+ (instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec {
    CID *c = [CID new];
    c->_version = 1;
    c->_codec = codec;
    NSMutableData *mh = [NSMutableData dataWithBytes:(uint8_t[]){0x12, (uint8_t)digest.length} length:2];
    [mh appendData:digest];
    c->_multihash = mh;
    return c;
}

- (NSString *)stringValue {
    NSMutableData *d = [NSMutableData data];
    [d appendData:[CID encodeVarint:self.version]];
    [d appendData:[CID encodeVarint:self.codec]];
    [d appendData:self.multihash];
    return [@"b" stringByAppendingString:[CID base32Encode:d]];
}
@end

// --- Main Program ---

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Simulate reading a file
        NSString *content = @"# AT Protocol PDS\\nThis is a readme.";
        NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
        
        // Compute SHA-256
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
        NSData *digest = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
        
        // Create Raw CID (0x55)
        CID *rawCID = [CID cidWithDigest:digest codec:0x55];
        NSLog(@"File Content: %@", content);
        NSLog(@"Raw CID: %@", rawCID.stringValue);
        
        // Create DAG-CBOR CID (0x71)
        CID *dagCID = [CID cidWithDigest:digest codec:0x71];
        NSLog(@"DAG-CBOR CID: %@", dagCID.stringValue);
    }
    return 0;
}`;
</script>

Welcome to Part II! Now that we have Objective-C foundations and a working build system, we'll start implementing the core data structures that power the AT Protocol. First up: Content Identifiers (CIDs)—the cryptographic fingerprints that make content-addressable storage possible.

## What is Content-Addressing?

Traditional file systems use **location-based addressing**: files are identified by where they are stored (e.g., `/Users/alice/documents/photo.jpg`). Content-addressable storage flips this: files are identified by **what they contain**.

```
Location-based:  /path/to/file.txt → content
Content-addressed: sha256(content) → content
```

Benefits of content-addressing:
- **Deduplication**: Identical content has the same address
- **Integrity verification**: The address IS the checksum
- **Immutability**: Changing content changes the address
- **Distribution**: Fetch from anywhere, verify locally

## CID Structure

A CID (Content Identifier) packages multiple pieces of information:

```
CID = version + codec + multihash
    = 0x01 (CIDv1) + 0x71 (dag-cbor) + <multihash>

multihash = algorithm + length + digest
          = 0x12 (sha2-256) + 0x20 (32 bytes) + <hash bytes>
```

### Components Explained

| Field | Purpose | Example |
|-------|---------|---------|
| **Version** | CID format version | `0x01` = CIDv1 |
| **Codec** | Content type | `0x55` = raw, `0x71` = dag-cbor |
| **Algorithm** | Hash function | `0x12` = sha2-256 |
| **Length** | Digest size | `0x20` = 32 bytes |
| **Digest** | Hash output | 32 bytes |

### Common Codecs in AT Protocol

| Code | Name | Usage |
|------|------|-------|
| `0x55` | raw | Blob data |
| `0x71` | dag-cbor | Records, commits, MST nodes |

## Varint Encoding

Numbers in CIDs use **varint** (variable-length integer) encoding to save space:

- Small values use fewer bytes
- High bit (`0x80`) indicates continuation
- Remaining 7 bits carry the value

```objc
// CID.m - Varint encoding
+ (NSData *)encodeVarint:(uint64_t)value {
    NSMutableData *data = [NSMutableData dataWithCapacity:9];
    uint64_t v = value;
    
    do {
        uint8_t byte = v & 0x7F;  // Take low 7 bits
        v >>= 7;                   // Shift by 7
        if (v != 0) {
            byte |= 0x80;          // Set continuation bit
        }
        [data appendBytes:&byte length:1];
    } while (v != 0);
    
    return [data copy];
}
```

- `0x0200` → `[0x80, 0x04]` (2 bytes)



<ObjcRunner :initialCode="varintCode" />

## SHA-256 Hashing with CommonCrypto

Apple's CommonCrypto framework provides optimized hash functions:

```objc
#import <CommonCrypto/CommonCrypto.h>

+ (NSData *)rawSha256:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];  // 32 bytes
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
```

To create a full multihash (with algorithm prefix):

```objc
+ (NSData *)sha256Digest:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}

+ (CID *)sha256:(NSData *)data {
    NSData *digest = [self sha256Digest:data];
    return [self cidWithDigest:digest codec:0x55];  // raw codec
}
```

## Building the CID Class

### Interface Definition

```objc
// CID.h
@interface CID : NSObject <NSCopying, NSSecureCoding>

@property (readonly, nonatomic) NSUInteger version;
@property (readonly, nonatomic) NSUInteger codec;
@property (readonly, nonatomic, strong) NSData *multihash;

+ (nullable instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec;
+ (nullable instancetype)cidFromString:(NSString *)string;
+ (nullable instancetype)cidFromBytes:(NSData *)data;

- (NSString *)stringValue;
- (NSData *)bytes;

+ (CID *)sha256:(NSData *)data;

@end
```

### Creating CIDs from Digests

```objc
+ (nullable instancetype)cidWithDigest:(NSData *)digest codec:(NSUInteger)codec {
    if (!digest || digest.length == 0) {
        return nil;
    }
    
    // Construct multihash: algorithm + length + digest
    NSMutableData *multihash = [NSMutableData dataWithCapacity:2 + digest.length];
    uint8_t header[] = {
        0x12,                        // sha2-256 algorithm
        (uint8_t)digest.length       // digest length (32 for SHA-256)
    };
    [multihash appendBytes:header length:2];
    [multihash appendData:digest];
    
    return [self cidWithMultihash:multihash codec:codec];
}

+ (nullable instancetype)cidWithMultihash:(NSData *)multihash codec:(NSUInteger)codec {
    CID *cid = [[CID alloc] init];
    cid->_version = 1;
    cid->_codec = codec;
    cid->_multihash = [multihash copy];
    return cid;
}
```

## Base32 Encoding

CIDs are typically represented as strings using **Base32 lowercase** encoding with a `b` prefix (multibase identifier):

```
bafyreigdwqgxq...  
│└──────────────── base32 encoded data
└────────────────── multibase 'b' prefix
```

### Multibase Prefixes

| Prefix | Encoding |
|--------|----------|
| `b` | Base32 lowercase |
| `z` | Base58btc |
| `f` | Base16 lowercase |

### Base32 Encoding Implementation



<ObjcRunner :initialCode="base32Code" />

### Converting CID to String

```objc
- (NSString *)stringValue {
    NSMutableData *binaryData = [NSMutableData data];
    
    // Write version (0x01)
    [binaryData appendData:[CID encodeVarint:0x01]];
    
    // Write codec
    [binaryData appendData:[CID encodeVarint:self.codec]];
    
    // Write multihash
    [binaryData appendData:self.multihash];
    
    // Base32 encode with 'b' prefix
    NSString *base32 = [CID base32Encode:binaryData];
    return [@"b" stringByAppendingString:base32];
}
```

## Parsing CID Strings

```objc
+ (nullable instancetype)cidFromString:(NSString *)string {
    if (!string || string.length == 0) {
        return nil;
    }

    // Check for base32 prefix
    if ([string characterAtIndex:0] != 'b') {
        return nil;  // Only supporting base32 for now
    }

    // Decode base32 (skip 'b' prefix)
    NSString *encodedPart = [string substringFromIndex:1];
    NSData *decodedData = [self base32Decode:encodedPart];
    
    if (!decodedData || decodedData.length < 2) {
        return nil;
    }

    return [self cidFromBytes:decodedData];
}

+ (nullable instancetype)cidFromBytes:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;

    // Read version
    uint64_t version;
    NSUInteger versionSize = [self readVarint:bytes 
                                    maxLength:data.length 
                                        value:&version];
    if (versionSize == 0 || version != 0x01) {
        return nil;  // Must be CIDv1
    }
    offset += versionSize;

    // Read codec
    uint64_t codec;
    NSUInteger codecSize = [self readVarint:bytes + offset
                                   maxLength:data.length - offset
                                       value:&codec];
    offset += codecSize;

    // Remaining bytes are multihash
    NSData *multihash = [data subdataWithRange:NSMakeRange(offset, data.length - offset)];

    return [self cidWithMultihash:multihash codec:(NSUInteger)codec];
}
```

## Practical Exercise: CID Generator

Build a command-line tool that computes CIDs for files:

```objc


<ObjcRunner :initialCode="fullCidCode" />
```

**Usage:**
```bash
$ ./cid-tool README.md
Raw CID: bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku
DAG-CBOR CID: bafyreigdwqgxqmvjf7uepmyxgxxz4xhpwv7...
```

## Testing CID Implementation

```objc
// CIDTests.m
- (void)testCreateFromDigest {
    NSData *testData = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *digest = [CID rawSha256:testData];
    
    CID *cid = [CID cidWithDigest:digest codec:0x55];
    
    XCTAssertNotNil(cid);
    XCTAssertEqual(cid.version, 1);
    XCTAssertEqual(cid.codec, 0x55);
}

- (void)testRoundTrip {
    NSData *testData = [@"test content" dataUsingEncoding:NSUTF8StringEncoding];
    CID *original = [CID sha256:testData];
    
    NSString *stringValue = original.stringValue;
    CID *parsed = [CID cidFromString:stringValue];
    
    XCTAssertTrue([original isEqualToCID:parsed]);
}

- (void)testDeterminism {
    NSData *data1 = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data2 = [@"same content" dataUsingEncoding:NSUTF8StringEncoding];
    
    CID *cid1 = [CID sha256:data1];
    CID *cid2 = [CID sha256:data2];
    
    XCTAssertEqualObjects(cid1.stringValue, cid2.stringValue);
}
```

---

## Common Mistakes

### Mistake 1: Confusing Codecs

❌ **What people do:**
```objc
// WRONG: Using dag-cbor codec for raw file data
NSData *imageData = [NSData dataWithContentsOfFile:@"photo.jpg"];
CID *cid = [CID cidWithDigest:[CID rawSha256:imageData] codec:0x71];  // 0x71 = dag-cbor
```

**Why this fails:**
- JPEG is raw binary, not CBOR-encoded data
- Other implementations won't be able to decode it as dag-cbor
- Violates AT Protocol conventions

✅ **Correct approach:**
```objc
// RIGHT: Use raw codec for binary blobs
CID *imageCID = [CID cidWithDigest:[CID rawSha256:imageData] codec:0x55];  // 0x55 = raw

// Use dag-cbor for structured data (records, commits, MST nodes)
NSData *recordCBOR = [self serializeRecordToCBOR:record];
CID *recordCID = [CID cidWithDigest:[CID rawSha256:recordCBOR] codec:0x71];
```

### Mistake 2: Base32 vs Base58 Confusion

❌ **What people do:**
```objc
// WRONG: Trying to parse Base58 CID as Base32
NSString *cidString = @"QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";  // CIDv0 Base58
CID *cid = [CID cidFromString:cidString];  // Fails: expects 'b' prefix
```

**Why this fails:**
- AT Protocol uses CIDv1 with Base32 lowercase ('b' prefix)
- Legacy CIDv0 uses Base58 ('Q' prefix) - not supported
- Mixing encodings produces parse errors

✅ **Correct approach:**
```objc
// RIGHT: AT Protocol CIDs always start with 'b'
NSString *cidString = @"bafyreigdwqgxq...";  // CIDv1 Base32
CID *cid = [CID cidFromString:cidString];   // Works!

// If you need to convert from CIDv0, upgrade first (external tool)
```

### Mistake 3: Not Validating CID Version

❌ **What people do:**
```objc
// WRONG: Accepting any CID version
+ (nullable instancetype)cidFromBytes:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    uint64_t version = bytes[0];  // Assume first byte is version
    // Continue without validation...
}
```

**Why this fails:**
- CIDv0 has different structure (no version/codec prefix)
- Varint encoding may use multiple bytes
- Incorrect parsing leads to wrong hashes

✅ **Correct approach:**
```objc
// RIGHT: Validate version is CIDv1
uint64_t version;
NSUInteger size = [self readVarint:bytes maxLength:length value:&version];
if (version != 0x01) {
    if (error) *error = [NSError errorWithDomain:CIDErrorDomain
        code:CIDErrorUnsupportedVersion
        userInfo:@{NSLocalizedDescriptionKey: @"Only CIDv1 supported"}];
    return nil;
}
```

---

## Exercises

📝 **Exercise 1: CID CLI Tool** (from Practical Example)

Build the command-line CID generator shown earlier and verify it works:

```bash
$ ./cid-tool README.md
Raw CID: bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku
```

📝 **Exercise 2: Varint Decoder**

Implement a varint decoder to complement the encoder:

```objc
+ (NSUInteger)readVarint:(const uint8_t *)bytes
               maxLength:(NSUInteger)maxLen
                   value:(uint64_t *)outValue;
// Returns number of bytes consumed, 0 on error
```

- Hint: Loop while high bit is set, accumulate low 7 bits
- Consider: What's the maximum valid varint size?

<details>
<summary>Solution</summary>

```objc
+ (NSUInteger)readVarint:(const uint8_t *)bytes
               maxLength:(NSUInteger)maxLen
                   value:(uint64_t *)outValue {
    uint64_t result = 0;
    NSUInteger shift = 0;
    
    for (NSUInteger i = 0; i < maxLen && i < 9; i++) {
        uint8_t byte = bytes[i];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        
        if ((byte & 0x80) == 0) {
            *outValue = result;
            return i + 1;  // Bytes consumed
        }
        shift += 7;
    }
    return 0;  // Error: varint too long or truncated
}
```

</details>

📝 **Exercise 3: Multi-Hash Validator**

Implement a method that validates a multihash structure:

```objc
+ (BOOL)validateMultihash:(NSData *)multihash error:(NSError **)error;
// Verify:
// - Algorithm code is recognized (0x12 = sha2-256)
// - Digest length matches actual data
// - Overall structure is valid
```

- Hint: Parse algorithm (varint), length (varint), then verify remaining bytes
- Challenge: Support multiple hash algorithms (sha2-256, sha2-512)

---

## Summary

In this chapter, you learned:

- ✅ Content-addressing vs location-based addressing
- ✅ CID structure: version + codec + multihash
- ✅ Varint encoding for space-efficient integers
- ✅ SHA-256 hashing with CommonCrypto
- ✅ Base32 encoding for string representation
- ✅ Parsing and creating CIDs

## Key Takeaways

1. **CIDs are self-describing**: They contain the hash algorithm used.

2. **Immutable by design**: Changing content changes the CID.

3. **Use correct codecs**: Raw (0x55) for blobs, dag-cbor (0x71) for structured data.

4. **Foundation for AT Protocol**: Records, commits, and blobs all use CIDs.

## Next Steps

In **Chapter 5**, we'll implement **CBOR serialization**—the binary format used to encode structured data that gets hashed into CIDs.

---

**Files Referenced in This Chapter:**
- [CID.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/CID.h)
- [CID.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/CID.m)
