# Chapter 5: CBOR Serialization - Understanding Binary Encoding

In Chapter 4, we learned about CIDs - cryptographic fingerprints of content. But what exactly are we fingerprinting? In AT Protocol, we hash **structured data** like user records, posts, and profiles. Before we can hash this data, we need to encode it into bytes.

This chapter teaches you how to serialize structured data using CBOR (Concise Binary Object Representation) and the AT Protocol's specific variant, DAG-CBOR. By the end, you'll understand why binary encoding matters, how to implement an encoder/decoder, and why deterministic encoding is critical for content addressing.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Explain why binary encoding is essential for distributed systems
- Implement CBOR encoding for integers, strings, arrays, and maps
- Understand DAG-CBOR's deterministic constraints and why they matter
- Encode and decode AT Protocol records
- Debug CBOR encoding issues by reading hex dumps

## Prerequisites

This chapter assumes you understand:
- Content Identifiers (CIDs) - covered in Chapter 4
- Binary numbers and hexadecimal notation - basic computer science
- Objective-C classes and methods - covered in Chapters 1-2

---

## The Problem: Why Not JSON?

### JSON's Hidden Issues

You might wonder: "We already have JSON for structured data. Why do we need another format?"

Imagine you're building a decentralized social network where millions of users create posts. Each post needs a unique fingerprint (CID) so other users can reference it reliably. Let's try using JSON:

```json
{
  "text": "Hello, world!",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

Seems simple! Let's compute a hash... but wait. Is this the same as:

```json
{"text":"Hello, world!","createdAt":"2024-01-01T00:00:00Z"}
```

Or this:

```json
{
  "createdAt": "2024-01-01T00:00:00Z",
  "text": "Hello, world!"
}
```

**They're all valid JSON representing the same data, but they're different strings of bytes!** Different bytes mean different hashes, which means different CIDs. This breaks content addressing - we need **deterministic encoding** where identical data always produces identical bytes.

### The Size Problem

JSON is also **inefficient**. Consider this simple record:

```json
{
  "id": 12345,
  "name": "Alice",
  "active": true
}
```

This JSON is **62 bytes**:
- Every character is a byte
- Quotation marks, colons, commas, whitespace all count
- The number 12345 takes 5 bytes as text

Binary encoding can represent the same data in **~25 bytes** - less than half the size! When you're transmitting millions of records over the network, this matters.

### The Solution: CBOR

**CBOR (Concise Binary Object Representation)** solves both problems:

1. **Binary format**: Data encoded as bytes, not text characters
2. **Deterministic rules** (with DAG-CBOR): Same data → same bytes
3. **Compact**: Numbers encoded efficiently, no wasted space on syntax

| Feature | JSON | CBOR |
|---------|------|------|
| Format | Text (human-readable) | Binary (machine-optimized) |
| Size | ~100 bytes | ~40 bytes (60% smaller) |
| Determinism | No (whitespace, field order vary) | Yes (with DAG-CBOR rules) |
| Binary data | Base64 encoding (33% overhead) | Native (no overhead) |
| Types | 6 types | 8+ major types with subtypes |

💡 **Key Insight:** JSON is for humans to read. CBOR is for machines to process efficiently and deterministically.

---

## The Intuition: Speaking in Bytes

### Text vs Binary Encoding

Think of encoding like translating a language:

**Text encoding (JSON)**: Like writing a letter - you spell out every word, add punctuation, use spaces. Humans can read it easily, but it's verbose.

**Binary encoding (CBOR)**: Like a machine code - compact instructions using raw numbers. Not human-readable, but incredibly efficient.

**Example:**

The number `12345` in different encodings:
- **JSON**: `'1'`, `'2'`, `'3'`, `'4'`, `'5'` = 5 bytes (5 characters)
- **CBOR**: `0x19`, `0x30`, `0x39` = 3 bytes (directly encoded)

That's 40% smaller for just one number!

### What Makes CBOR Deterministic?

Imagine two bakers following a recipe:
- If the recipe says "add flour and eggs" - one might add eggs first, the other flour first
- Different order = potentially different result

**DAG-CBOR is like an ultra-precise recipe:**
- "Add ingredients in alphabetical order"
- "Use exactly 2 decimal places for measurements"
- "Mix for exactly 60 seconds"

Everyone following the recipe gets **exactly the same** result. That's determinism - critical when we need identical hashes!

---

## CBOR Basics: The Type System

### Major Types: Organizing Data

CBOR organizes data into 8 "major types" - think of them as bins where different kinds of values go:

```
┌─────────────────────────────────────┐
│         CBOR Type System            │
├──────┬──────┬──────┬──────┬─────────┤
│ Bin 0│ Bin 1│ Bin 2│ Bin 3│ ...     │
│ Ints │ -Ints│ Bytes│Strings│         │
└──────┴──────┴──────┴──────┴─────────┘
```

| Major Type | Name | Examples | Usage in AT Protocol |
|------------|------|----------|---------------------|
| 0 | Unsigned integer | `0`, `42`, `1000` | Record IDs, counts |
| 1 | Negative integer | `-1`, `-100` | Rarely used |
| 2 | Byte string | Binary data | CID bytes, signatures |
| 3 | Text string | `"Hello"`, `"Alice"` | Post text, usernames |
| 4 | Array | `[1, 2, 3]` | Lists of items |
| 5 | Map | `{"key": "value"}` | Records, objects |
| 6 | Tag | Semantic wrappers | Tag 42 = CID links |
| 7 | Simple/Float | `null`, `true`, `false` | Booleans, null |

### The Initial Byte: CBOR's DNA

Every CBOR value starts with a single "initial byte" that contains two pieces of information:

```
┌────────────────────────────────────┐
│        Initial Byte (8 bits)       │
├─────────────────┬──────────────────┤
│ Major Type      │  Additional Info │
│  (3 bits)       │  (5 bits)        │
└─────────────────┴──────────────────┘
  Bits 7-5          Bits 4-0

Example: 0x65 = 0110 0101
         Major = 011 (3) = Text string
         Additional = 00101 (5) = Length is 5
```

**Think of it like a shipping label:**
- Major type = "What's inside?" (package type)
- Additional info = "How much?" (size or value)

The initial byte tells the decoder:
1. What type of value follows (major type)
2. Either the value itself OR how many bytes to read next (additional info)

### Additional Info: The Size Indicator

The 5-bit additional info field encodes either:
- **The value itself** (for small values 0-23)
- **How many more bytes to read** (for larger values)

| Additional Info | Meaning | Example |
|-----------------|---------|---------|
| 0-23 | Value is the number itself | `0x05` = integer 5 |
| 24 | Read next 1 byte for value | `0x18 0x64` = integer 100 |
| 25 | Read next 2 bytes for value | `0x19 0x01 0x00` = integer 256 |
| 26 | Read next 4 bytes for value | `0x1A 0x00 0x01 0x00 0x00` = integer 65536 |
| 27 | Read next 8 bytes for value | `0x1B ...` = very large integers |

💡 **Key Insight:** CBOR uses the minimum bytes needed. Small values fit in the initial byte, large values get extra bytes.

---

## Encoding Integers: Starting Simple

Let's build an integer encoder step by step, starting with the simplest case and adding complexity.

### Version 1: Just Small Values (0-23)

The simplest possible encoder - values that fit entirely in the initial byte:

```objc
// Version 1: Only handles 0-23
+ (NSData *)encodeSmallInteger:(NSUInteger)value {
    if (value > 23) {
        return nil;  // Can't handle this yet!
    }

    // Major type 0 (unsigned int) in top 3 bits = 000
    // Value in bottom 5 bits
    uint8_t byte = (uint8_t)value;  // e.g., 5 → 0x05

    return [NSData dataWithBytes:&byte length:1];
}
```

**Examples:**
```
Value 0  → 0x00 (binary: 0000 0000)
Value 5  → 0x05 (binary: 0000 0101)
Value 23 → 0x17 (binary: 0001 0111)
```

**Why this works:** Major type 0 is `000` in the top 3 bits, so for small values, the top 3 bits are already zero. The value itself goes in the bottom 5 bits.

**Limitation:** Can only represent 0-23. What about 100? Or 1000000?

### Version 2: Adding Medium Values (24-255)

Now let's handle values that need 1 additional byte:

```objc
// Version 2: Handles 0-255
+ (NSData *)encodeMediumInteger:(NSUInteger)value {
    NSMutableData *data = [NSMutableData data];

    if (value < 24) {
        // Fits in initial byte
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];
    } else if (value < 256) {
        // Need 1 additional byte
        uint8_t bytes[2];
        bytes[0] = 0x18;  // Major type 0, additional info = 24 (means "1 byte follows")
        bytes[1] = (uint8_t)value;  // The actual value
        [data appendBytes:bytes length:2];
    }

    return [data copy];
}
```

**Examples:**
```
Value 24  → 0x18 0x18  (first byte: marker, second byte: value)
Value 100 → 0x18 0x64  (0x64 = 100 in hex)
Value 255 → 0x18 0xFF
```

**Why 0x18?**
- Top 3 bits: `000` (major type 0)
- Bottom 5 bits: `11000` (decimal 24, means "1 byte follows")
- Combined: `0001 1000` = `0x18`

### Understanding Big-Endian Byte Order

Before we add larger integers, we need to understand **byte ordering**.

When a number needs multiple bytes, which byte comes first?

**Example: The number 300** (0x012C in hex)

```
Binary: 0000 0001 0010 1100
        └─ high byte  └─ low byte
           0x01          0x2C
```

**Big-endian** (what CBOR uses): Most significant byte first
```
Memory: [0x01] [0x2C]
         high   low
```

**Little-endian** (what most CPUs use internally): Least significant byte first
```
Memory: [0x2C] [0x01]
         low    high
```

💡 **Why big-endian?** Network protocols use big-endian because it's the "natural" order humans read numbers (left-to-right, big to small). CBOR follows this convention for consistency.

On Apple platforms, we use `OSSwapHostToBigInt*` functions to convert:
```objc
uint16_t host = 300;  // CPU's native byte order
uint16_t big = OSSwapHostToBigInt16(host);  // Convert to big-endian
```

### Version 3: Production Integer Encoder

Now the complete encoder handling all integer ranges:

```objc
+ (void)encodeUnsignedInteger:(NSUInteger)value toData:(NSMutableData *)data {
    if (value < 24) {
        // Value fits in additional info (5 bits)
        uint8_t byte = (uint8_t)value;
        [data appendBytes:&byte length:1];

    } else if (value < 256) {
        // 1 additional byte needed
        uint8_t bytes[2] = { 0x18, (uint8_t)value };
        [data appendBytes:bytes length:2];

    } else if (value < 65536) {
        // 2 additional bytes (big-endian uint16)
        uint8_t marker = 0x19;  // Additional info = 25
        [data appendBytes:&marker length:1];

        uint16_t be = OSSwapHostToBigInt16((uint16_t)value);
        [data appendBytes:&be length:2];

    } else if (value < 4294967296ULL) {
        // 4 additional bytes (big-endian uint32)
        uint8_t marker = 0x1A;  // Additional info = 26
        [data appendBytes:&marker length:1];

        uint32_t be = OSSwapHostToBigInt32((uint32_t)value);
        [data appendBytes:&be length:4];

    } else {
        // 8 additional bytes (big-endian uint64)
        uint8_t marker = 0x1B;  // Additional info = 27
        [data appendBytes:&marker length:1];

        uint64_t be = OSSwapHostToBigInt64(value);
        [data appendBytes:&be length:8];
    }
}
```

**Complete Examples:**

```
Value 10:
  < 24, so fits in initial byte
  Result: 0x0A  (1 byte)

Value 300:
  >= 256, < 65536, so needs 2 additional bytes
  300 = 0x012C in hex
  Result: 0x19 0x01 0x2C  (3 bytes total)
          ↑    ↑─────────┐
        marker  big-endian
                 uint16

Value 100000:
  >= 65536, < 4294967296, so needs 4 additional bytes
  100000 = 0x000186A0 in hex
  Result: 0x1A 0x00 0x01 0x86 0xA0  (5 bytes total)
```

### Visualizing the Encoding Process

Let's trace encoding the value **300**:

```
Step 1: Determine range
  300 >= 256 and < 65536
  → Need 2 additional bytes

Step 2: Write marker byte
  Major type 0 (unsigned int) = 000
  Additional info 25 (2 bytes follow) = 11001
  Combined: 0001 1001 = 0x19

  Buffer: [0x19]

Step 3: Convert value to big-endian
  300 in binary: 0000 0001 0010 1100
  Split into bytes:
    High byte: 0000 0001 = 0x01
    Low byte:  0010 1100 = 0x2C
  Big-endian: 0x01 0x2C (high byte first)

Step 4: Append value bytes
  Buffer: [0x19] [0x01] [0x2C]

Final result: 3 bytes encoding the value 300
```

---

## Encoding Strings: Text and Bytes

Strings follow a similar pattern: **type marker + length + data**.

### Text Strings (Major Type 3)

Text strings are UTF-8 encoded text:

```objc
+ (void)encodeTextString:(NSString *)string toData:(NSMutableData *)data {
    // Convert to UTF-8 bytes
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger length = utf8.length;

    // Encode: major type 3 + length + UTF-8 bytes
    [self encodeCount:length withMajorType:0x60 toData:data];  // 0x60 = major type 3
    [data appendData:utf8];
}
```

**The `encodeCount` helper** (same logic as integers, but with major type prefix):

```objc
+ (void)encodeCount:(NSUInteger)count withMajorType:(uint8_t)majorType toData:(NSMutableData *)data {
    if (count < 24) {
        // Length fits in additional info
        uint8_t byte = majorType | (uint8_t)count;
        [data appendBytes:&byte length:1];

    } else if (count < 256) {
        // Length needs 1 byte
        uint8_t bytes[2] = { majorType | 24, (uint8_t)count };
        [data appendBytes:bytes length:2];

    } else if (count < 65536) {
        // Length needs 2 bytes
        uint8_t header = majorType | 25;
        [data appendBytes:&header length:1];
        uint16_t be = OSSwapHostToBigInt16((uint16_t)count);
        [data appendBytes:&be length:2];

    } else {
        // Length needs 4 bytes
        uint8_t header = majorType | 26;
        [data appendBytes:&header length:1];
        uint32_t be = OSSwapHostToBigInt32((uint32_t)count);
        [data appendBytes:&be length:4];
    }
}
```

**Example: Encoding "Hello"**

```
Step 1: Convert to UTF-8
  "Hello" → [0x48, 0x65, 0x6C, 0x6C, 0x6F]  (5 bytes)

Step 2: Encode header
  Major type 3 (text string) = 011 = 0x60
  Length 5 < 24, so fits in additional info
  Combined: 0110 0101 = 0x65

Step 3: Append UTF-8 bytes
  Result: 0x65 0x48 0x65 0x6C 0x6C 0x6F
          ↑    ↑─────────────────────────┐
        header       "Hello" in UTF-8
```

### Byte Strings (Major Type 2)

Byte strings are for raw binary data (like CID bytes, signatures):

```objc
+ (void)encodeByteString:(NSData *)bytes toData:(NSMutableData *)output {
    NSUInteger length = bytes.length;
    [self encodeCount:length withMajorType:0x40 toData:output];  // 0x40 = major type 2
    [output appendData:bytes];
}
```

Same pattern as text strings, but major type 2 instead of 3.

---

## Encoding Collections: Arrays and Maps

### Arrays (Major Type 4)

Arrays are encoded as: **count + items**

```objc
+ (void)encodeArray:(NSArray<CBORValue *> *)array toData:(NSMutableData *)output {
    NSUInteger count = array.count;
    [self encodeCount:count withMajorType:0x80 toData:output];  // 0x80 = major type 4

    // Encode each item
    for (CBORValue *item in array) {
        [self encodeValue:item toData:output];
    }
}
```

**Example: `[1, 2, 3]`**

```
Step 1: Encode array header
  Major type 4, count 3 < 24
  Result: 0x83  (10000011 = major 4, additional 3)

Step 2: Encode each element
  1 → 0x01
  2 → 0x02
  3 → 0x03

Final: 0x83 0x01 0x02 0x03
       ↑    ↑───────────┐
     header   array items
```

### Maps (Major Type 5)

Maps are key-value pairs. The basic encoding:

```objc
+ (void)encodeMapSimple:(NSDictionary<CBORValue *, CBORValue *> *)map
                 toData:(NSMutableData *)output {
    NSUInteger count = map.count;
    [self encodeCount:count withMajorType:0xA0 toData:output];  // 0xA0 = major type 5

    // Encode each key-value pair
    for (CBORValue *key in map) {
        [self encodeValue:key toData:output];         // Key
        [self encodeValue:map[key] toData:output];    // Value
    }
}
```

**But there's a problem!** Dictionary iteration order is unpredictable. This means:
- Same map could encode differently on different runs
- Different hashes → different CIDs
- **Breaks determinism!**

---

## DAG-CBOR: The Determinism Layer

### Why Determinism Matters

Remember our goal: **content addressing**. Identical content must produce identical CIDs.

Consider this map:
```objc
@{
    @"name": @"Alice",
    @"age": @30
}
```

Without deterministic encoding:
- Run 1: `name` first → Hash A
- Run 2: `age` first → Hash B
- **Different CIDs for the same data!**

This breaks the entire content-addressing system. We need **canonical encoding**: same data always encodes exactly the same way.

### DAG-CBOR Rules

**DAG-CBOR** (Directed Acyclic Graph CBOR) adds 5 constraints for determinism:

| Rule | Purpose | Example |
|------|---------|---------|
| **1. Definite lengths** | No streaming/indefinite encoding | Array length known upfront |
| **2. Canonical integers** | Smallest possible representation | 10 → `0x0A`, not `0x18 0x0A` |
| **3. Sorted map keys** | Deterministic key order | Sort by encoded bytes |
| **4. CID links** | Tag 42 for content references | `{0xD82A: <CID bytes>}` |
| **5. No floats** | Avoid precision issues | Use integers only |

Let's dive deep into the most complex rule: **map key sorting**.

### Map Key Sorting: The Algorithm

DAG-CBOR sorts map keys by their **encoded byte representation**:

1. **Encode each key** to CBOR bytes
2. **Sort** by these rules (in order):
   - Shorter encoded length comes first
   - If same length, compare bytes lexicographically (like dictionary order)

**Why this order?**
- Length-first ensures smaller encodings come first (efficiency)
- Lexicographic within same length is fast (simple byte comparison)

### Sorting Example: Step by Step

Let's sort these keys: `["name", "id", "created"]`

**Step 1: Encode each key**

```
"id":
  Major type 3 (text), length 2 < 24
  0x62 0x69 0x64
  Length: 3 bytes

"name":
  Major type 3, length 4 < 24
  0x64 0x6E 0x61 0x6D 0x65
  Length: 5 bytes

"created":
  Major type 3, length 7 < 24
  0x67 0x63 0x72 0x65 0x61 0x74 0x65 0x64
  Length: 9 bytes
```

**Step 2: Sort by length**

```
"id"      → 3 bytes  (shortest)
"name"    → 5 bytes
"created" → 9 bytes  (longest)
```

**Step 3: Within same length, sort lexicographically**

In this example, all lengths are different, so we're done!

**Result order: `["id", "name", "created"]`**

### Visual Representation

```
Before sort (unpredictable order):
┌──────────────────────────┐
│ "name": "Alice"          │
│ "id": 123                │
│ "created": "2024-01-01"  │
└──────────────────────────┘

After DAG-CBOR sort (by encoded length):
┌──────────────────────────┐
│ "id": 123         (3 bytes key)
│ "name": "Alice"   (5 bytes key)
│ "created": "..."  (9 bytes key)
└──────────────────────────┘
```

### Production Map Encoder with Sorting

```objc
+ (void)encodeMap:(NSDictionary<CBORValue *, CBORValue *> *)map
           toData:(NSMutableData *)output {
    NSUInteger count = map.count;
    [self encodeCount:count withMajorType:0xA0 toData:output];

    if (count == 0) return;

    // Sort keys by their encoded byte representation
    NSArray *keys = [map allKeys];
    NSArray *sortedKeys = [keys sortedArrayUsingComparator:^NSComparisonResult(CBORValue *k1, CBORValue *k2) {
        // Encode both keys
        NSData *d1 = [k1 encode];
        NSData *d2 = [k2 encode];

        // Compare: shorter length first
        if (d1.length != d2.length) {
            return d1.length < d2.length ? NSOrderedAscending : NSOrderedDescending;
        }

        // Same length: compare bytes lexicographically
        int cmp = memcmp(d1.bytes, d2.bytes, d1.length);
        if (cmp < 0) return NSOrderedAscending;
        if (cmp > 0) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // Encode in sorted order (deterministic!)
    for (CBORValue *key in sortedKeys) {
        [self encodeValue:key toData:output];         // Key
        [self encodeValue:map[key] toData:output];    // Value
    }
}
```

💡 **Key Insight:** This sorting comparator is the heart of DAG-CBOR determinism. Without it, content addressing breaks!

---

## Tags: Adding Semantic Meaning

### What Are Tags?

Tags are CBOR's way of saying "this value has special meaning beyond its type."

Think of tags like labels on boxes:
- The box itself is a string (bytes)
- The label says "this is a date" or "this is a CID link"

### Tag 42: CID Links

AT Protocol uses **Tag 42** to mark CID references:

```objc
+ (void)encodeTag:(NSUInteger)tag value:(CBORValue *)value toData:(NSMutableData *)data {
    // Encode tag number (same as unsigned integer, but major type 6)
    [self encodeCount:tag withMajorType:0xC0 toData:data];  // 0xC0 = major type 6

    // Encode the tagged value
    [self encodeValue:value toData:data];
}
```

**Example: CID Link**

```objc
// Create CID bytes (from Chapter 4)
CID *cid = [CID cidFromString:@"bafyreig..."];
NSData *cidBytes = [cid bytes];

// Add multibase prefix (0x00 = identity, means "raw binary")
NSMutableData *linkData = [NSMutableData dataWithBytes:"\x00" length:1];
[linkData appendData:cidBytes];

// Wrap in Tag 42
CBORValue *cidLink = [CBORValue tag:42 value:[CBORValue byteString:linkData]];

// Encode
NSData *encoded = [cidLink encode];
// Result: 0xD8 0x2A <byte string with CID>
//         ↑    ↑
//       tag 42 marker
```

**Breaking down 0xD82A:**
```
0xD8 = 11011000
       ↑↑↑    ↑↑↑
     major 6  additional 24 (1 byte follows)

0x2A = 42 (the tag number)
```

---

## The CBORValue Class: Tying It Together

Now that we understand encoding primitives, let's see how it's structured in code:

### The Tagged Union Pattern

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

// Type discriminator
@property (nonatomic, assign, readonly) CBORType type;

// Payload (only one is populated based on type)
@property (nonatomic, strong, readonly, nullable) NSNumber *unsignedInteger;
@property (nonatomic, strong, readonly, nullable) NSData *byteString;
@property (nonatomic, copy, readonly, nullable) NSString *textString;
@property (nonatomic, copy, readonly, nullable) NSArray<CBORValue *> *array;
@property (nonatomic, copy, readonly, nullable) NSDictionary<CBORValue *, CBORValue *> *map;
@property (nonatomic, strong, readonly, nullable) NSNumber *tag;
@property (nonatomic, strong, readonly, nullable) CBORValue *tagValue;

// Factory methods (safe construction)
+ (instancetype)unsignedInteger:(NSUInteger)value;
+ (instancetype)textString:(NSString *)string;
+ (instancetype)byteString:(NSData *)data;
+ (instancetype)array:(NSArray<CBORValue *> *)array;
+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map;
+ (instancetype)tag:(NSUInteger)tag value:(CBORValue *)value;
+ (instancetype)nilValue;

// Encoding/Decoding
- (NSData *)encode;
+ (nullable instancetype)decode:(NSData *)data;

@end
```

**Why this design?**
- **Type safety**: Can't accidentally treat a string as an integer
- **Clear intent**: Factory methods make code readable
- **Encapsulation**: Encoding logic is hidden

### Factory Method Examples

```objc
// CBOR.m
+ (instancetype)unsignedInteger:(NSUInteger)value {
    CBORValue *obj = [[self alloc] init];
    obj->_type = CBORTypeUnsignedInteger;
    obj->_unsignedInteger = @(value);
    return obj;
}

+ (instancetype)textString:(NSString *)string {
    CBORValue *obj = [[self alloc] init];
    obj->_type = CBORTypeTextString;
    obj->_textString = [string copy];
    return obj;
}

+ (instancetype)map:(NSDictionary<CBORValue *, CBORValue *> *)map {
    CBORValue *obj = [[self alloc] init];
    obj->_type = CBORTypeMap;
    obj->_map = [map copy];
    return obj;
}

+ (instancetype)nilValue {
    CBORValue *obj = [[self alloc] init];
    obj->_type = CBORTypeSimpleOrFloat;
    obj->_unsignedInteger = @22;  // CBOR null = simple value 22
    return obj;
}
```

---

## CBOR Decoding: The Reverse Process

Decoding is reading CBOR bytes and reconstructing the original value.

### The Decoder Strategy

```
Input: CBOR byte stream
  ↓
Read initial byte
  ↓
Extract major type and additional info
  ↓
Based on major type, read appropriate data
  ↓
Recursively decode nested structures
  ↓
Return CBORValue object
```

### The Main Decoder

```objc
+ (CBORValue *)decode:(NSData *)data offset:(NSUInteger *)offset {
    if (*offset >= data.length) return nil;  // No more data

    const uint8_t *bytes = data.bytes;
    uint8_t initial = bytes[(*offset)++];  // Read initial byte, advance offset

    // Extract major type (top 3 bits)
    uint8_t majorType = (initial & 0xE0) >> 5;  // 0xE0 = 1110 0000

    // Extract additional info (bottom 5 bits)
    uint8_t additional = initial & 0x1F;  // 0x1F = 0001 1111

    // Dispatch based on major type
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

**Understanding bit manipulation:**

```objc
// Example: initial byte = 0x65 (0110 0101)

// Extract major type (top 3 bits)
uint8_t majorType = (initial & 0xE0) >> 5;
// Step 1: initial & 0xE0 = 0110 0101 & 1110 0000 = 0110 0000
// Step 2: >> 5 shifts right 5 bits = 0000 0011 = 3
// Result: majorType = 3 (text string)

// Extract additional info (bottom 5 bits)
uint8_t additional = initial & 0x1F;
// initial & 0x1F = 0110 0101 & 0001 1111 = 0000 0101 = 5
// Result: additional = 5 (length)
```

### Decoding Integers

```objc
+ (CBORValue *)decodeUnsignedInteger:(uint8_t)additional
                               data:(NSData *)data
                             offset:(NSUInteger *)offset {
    NSUInteger value = 0;

    if (additional < 24) {
        // Value is in the additional info itself
        value = additional;

    } else {
        // Read additional bytes
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (*offset + bytesToRead > data.length) return nil;  // Not enough data!

        const uint8_t *bytes = data.bytes;

        // Read bytes in big-endian order
        for (NSUInteger i = 0; i < bytesToRead; i++) {
            value = (value << 8) | bytes[*offset + i];
        }

        *offset += bytesToRead;
    }

    return [CBORValue unsignedInteger:value];
}

+ (NSUInteger)bytesToReadForAdditional:(uint8_t)additional {
    switch (additional) {
        case 24: return 1;  // uint8
        case 25: return 2;  // uint16
        case 26: return 4;  // uint32
        case 27: return 8;  // uint64
        default: return 0;
    }
}
```

**Tracing a decode: `0x19 0x01 0x2C` (the number 300)**

```
Step 1: Read initial byte 0x19
  Major type = 0 (unsigned int)
  Additional = 25 (read 2 bytes)

Step 2: Read next 2 bytes
  Bytes: [0x01, 0x2C]

Step 3: Combine in big-endian order
  value = 0
  value = (0 << 8) | 0x01 = 0x0100 = 256
  value = (256 << 8) | 0x2C = 0x012C = 300

Result: CBORValue with unsignedInteger = 300
```

### Decoding Strings

```objc
+ (CBORValue *)decodeTextString:(uint8_t)additional
                          data:(NSData *)data
                        offset:(NSUInteger *)offset {
    // Step 1: Read length
    NSUInteger length = 0;

    if (additional < 24) {
        length = additional;
    } else {
        NSUInteger bytesToRead = [self bytesToReadForAdditional:additional];
        if (*offset + bytesToRead > data.length) return nil;

        // Read length value
        const uint8_t *bytes = data.bytes;
        for (NSUInteger i = 0; i < bytesToRead; i++) {
            length = (length << 8) | bytes[*offset + i];
        }
        *offset += bytesToRead;
    }

    // Step 2: Read UTF-8 bytes
    if (*offset + length > data.length) return nil;  // Not enough data!

    NSData *valueData = [data subdataWithRange:NSMakeRange(*offset, length)];
    *offset += length;

    // Step 3: Convert to NSString
    NSString *value = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];

    return [CBORValue textString:value ?: @""];  // Return empty string if UTF-8 decode fails
}
```

### Decoding Collections (Recursive)

```objc
+ (CBORValue *)decodeArray:(uint8_t)additional
                     data:(NSData *)data
                   offset:(NSUInteger *)offset {
    // Read count (same as reading an integer)
    NSUInteger count = /* ... read count from additional info ... */;

    NSMutableArray<CBORValue *> *array = [NSMutableArray arrayWithCapacity:count];

    // Recursively decode each element
    for (NSUInteger i = 0; i < count; i++) {
        CBORValue *element = [self decode:data offset:offset];  // Recursive!
        if (!element) return nil;  // Decode failed
        [array addObject:element];
    }

    return [CBORValue array:array];
}

+ (CBORValue *)decodeMap:(uint8_t)additional
                   data:(NSData *)data
                 offset:(NSUInteger *)offset {
    NSUInteger count = /* ... read count ... */;

    NSMutableDictionary<CBORValue *, CBORValue *> *map = [NSMutableDictionary dictionaryWithCapacity:count];

    // Decode key-value pairs
    for (NSUInteger i = 0; i < count; i++) {
        CBORValue *key = [self decode:data offset:offset];    // Recursive!
        CBORValue *value = [self decode:data offset:offset];  // Recursive!

        if (!key || !value) return nil;
        map[key] = value;
    }

    return [CBORValue map:map];
}
```

💡 **Key Insight:** Decoding is recursive - nested structures call `decode` again for their contents.

---

## Practical Example: AT Protocol Record

Let's encode a real Bluesky post record and examine every byte.

### Creating the Record

```objc
// Create a simple post
NSDictionary<CBORValue *, CBORValue *> *record = @{
    [CBORValue textString:@"$type"]: [CBORValue textString:@"app.bsky.feed.post"],
    [CBORValue textString:@"createdAt"]: [CBORValue textString:@"2024-01-01T00:00:00Z"],
    [CBORValue textString:@"text"]: [CBORValue textString:@"Hello from NSPds!"]
};

CBORValue *cborRecord = [CBORValue map:record];
NSData *encoded = [cborRecord encode];

// Hash to get CID
NSData *hash = [CID rawSha256:encoded];
CID *recordCID = [CID cidWithDigest:hash codec:0x71];  // 0x71 = dag-cbor codec

NSLog(@"Record CID: %@", recordCID.stringValue);
NSLog(@"Encoded size: %lu bytes", (unsigned long)encoded.length);
```

### Byte-by-Byte Breakdown

After encoding and sorting keys, the CBOR bytes look like this (hypothetical, simplified):

```
Hex Dump:
A3                          # Map with 3 entries
   65                       # Text string, length 5
      2474797065            # "$type" in UTF-8
   72                       # Text string, length 18
      6170702E62736B792E... # "app.bsky.feed.post"
   69                       # Text string, length 9
      637265617465644174    # "createdAt"
   74                       # Text string, length 20
      323032342D30312D...   # "2024-01-01T00:00:00Z"
   64                       # Text string, length 4
      74657874              # "text"
   72                       # Text string, length 18
      48656C6C6F2066726...  # "Hello from NSPds!"

Total: ~95 bytes
```

**Comparison with JSON:**

```json
{
  "$type": "app.bsky.feed.post",
  "createdAt": "2024-01-01T00:00:00Z",
  "text": "Hello from NSPds!"
}
```

JSON (minified): **123 bytes**
CBOR: **~95 bytes**

**Savings: 23%** - and that's just a tiny record! Larger records see even more savings.

### Why This Matters for AT Protocol

1. **Content addressing works**: Same post always produces same CID
2. **Efficient**: Less bandwidth for syncing millions of posts
3. **Verifiable**: Anyone can recompute the CID and verify integrity
4. **Interoperable**: All PDS implementations produce identical encoding

---

## Common Mistakes

Let's look at what can go wrong and how to fix it.

### Mistake 1: Wrong Byte Order

❌ **WRONG:**
```objc
// Native CPU byte order (probably little-endian)
uint16_t value = 300;
[data appendBytes:&value length:2];
// Result: 0x2C 0x01 (on little-endian systems)
// CBOR expects: 0x01 0x2C (big-endian)
```

✅ **CORRECT:**
```objc
// Explicitly convert to big-endian
uint16_t value = 300;
uint16_t be = OSSwapHostToBigInt16(value);
[data appendBytes:&be length:2];
// Result: 0x01 0x2C (always, regardless of CPU)
```

**Why it fails:** Different machines would produce different encodings, breaking determinism.

### Mistake 2: Not Sorting Map Keys

❌ **WRONG:**
```objc
// Iterate dictionary directly (unpredictable order!)
for (CBORValue *key in map) {
    [self encodeValue:key toData:output];
    [self encodeValue:map[key] toData:output];
}
```

✅ **CORRECT:**
```objc
// Sort keys by encoded bytes first
NSArray *sortedKeys = [[map allKeys] sortedArrayUsingComparator:^(id k1, id k2) {
    NSData *d1 = [k1 encode];
    NSData *d2 = [k2 encode];
    // ... sorting logic from earlier ...
}];

for (CBORValue *key in sortedKeys) {
    [self encodeValue:key toData:output];
    [self encodeValue:map[key] toData:output];
}
```

**Why it fails:** Map iteration order is undefined. Different runs → different encodings → different CIDs.

### Mistake 3: Not Using Minimal Encoding

❌ **WRONG:**
```objc
// Always use 4 bytes for integers (wasteful!)
uint8_t header = 0x1A;  // Marker for 4-byte uint32
uint32_t be = OSSwapHostToBigInt32((uint32_t)value);
[data appendBytes:&header length:1];
[data appendBytes:&be length:4];
// Result for value 10: 0x1A 0x00 0x00 0x00 0x0A (5 bytes!)
```

✅ **CORRECT:**
```objc
// Use smallest representation
if (value < 24) {
    uint8_t byte = (uint8_t)value;
    [data appendBytes:&byte length:1];
}
// Result for value 10: 0x0A (1 byte!)
```

**Why it fails:** DAG-CBOR requires canonical (minimal) encoding. Non-canonical encodings won't match expected CIDs.

### Mistake 4: Forgetting the Multibase Prefix for CIDs

❌ **WRONG:**
```objc
// Direct CID bytes in Tag 42
CBORValue *link = [CBORValue tag:42 value:[CBORValue byteString:cidBytes]];
```

✅ **CORRECT:**
```objc
// Add multibase identity prefix (0x00)
NSMutableData *linkData = [NSMutableData dataWithBytes:"\x00" length:1];
[linkData appendData:cidBytes];
CBORValue *link = [CBORValue tag:42 value:[CBORValue byteString:linkData]];
```

**Why it fails:** AT Protocol spec requires CID links to have a multibase prefix. Without it, other implementations won't recognize the link correctly.

---

## Testing CBOR Implementation

### Test 1: Round-Trip Encoding

```objc
- (void)testRoundTrip {
    // Create a complex nested structure
    NSDictionary<CBORValue *, CBORValue *> *original = @{
        [CBORValue textString:@"name"]: [CBORValue textString:@"Alice"],
        [CBORValue textString:@"age"]: [CBORValue unsignedInteger:30],
        [CBORValue textString:@"tags"]: [CBORValue array:@[
            [CBORValue textString:@"developer"],
            [CBORValue textString:@"swift"]
        ]]
    };

    CBORValue *value = [CBORValue map:original];

    // Encode
    NSData *encoded = [value encode];
    XCTAssertNotNil(encoded);

    // Decode
    CBORValue *decoded = [CBORValue decode:encoded];
    XCTAssertNotNil(decoded);

    // Should be identical
    XCTAssertTrue([value isEqual:decoded]);
}
```

### Test 2: Map Key Sorting

```objc
- (void)testMapKeySorting {
    // Keys with different encoded lengths
    NSDictionary<CBORValue *, CBORValue *> *map = @{
        [CBORValue textString:@"aaa"]: [CBORValue unsignedInteger:3],  // 4 bytes encoded
        [CBORValue textString:@"bb"]: [CBORValue unsignedInteger:2],   // 3 bytes encoded
        [CBORValue textString:@"a"]: [CBORValue unsignedInteger:1],    // 2 bytes encoded
    };

    CBORValue *value = [CBORValue map:map];
    NSData *encoded = [value encode];

    // Manually check byte order (expected: "a", "bb", "aaa")
    const uint8_t *bytes = encoded.bytes;

    // After map header (0xA3), first key should be "a"
    XCTAssertEqual(bytes[1], 0x61);  // Text string, length 1
    XCTAssertEqual(bytes[2], 'a');

    // ... continue checking order ...
}
```

### Test 3: Determinism

```objc
- (void)testDeterministicEncoding {
    NSDictionary<CBORValue *, CBORValue *> *map1 = @{
        [CBORValue textString:@"x"]: [CBORValue unsignedInteger:1],
        [CBORValue textString:@"y"]: [CBORValue unsignedInteger:2]
    };

    NSDictionary<CBORValue *, CBORValue *> *map2 = @{
        [CBORValue textString:@"y"]: [CBORValue unsignedInteger:2],  // Different order!
        [CBORValue textString:@"x"]: [CBORValue unsignedInteger:1]
    };

    NSData *encoded1 = [[CBORValue map:map1] encode];
    NSData *encoded2 = [[CBORValue map:map2] encode];

    // Should be byte-for-byte identical despite different input order
    XCTAssertEqualObjects(encoded1, encoded2);
}
```

### Test 4: Integer Ranges

```objc
- (void)testIntegerEncodingRanges {
    // Small value (fits in initial byte)
    CBORValue *small = [CBORValue unsignedInteger:10];
    NSData *smallEncoded = [small encode];
    XCTAssertEqual(smallEncoded.length, 1);
    XCTAssertEqual(((uint8_t*)smallEncoded.bytes)[0], 0x0A);

    // Medium value (needs 1 additional byte)
    CBORValue *medium = [CBORValue unsignedInteger:100];
    NSData *mediumEncoded = [medium encode];
    XCTAssertEqual(mediumEncoded.length, 2);
    XCTAssertEqual(((uint8_t*)mediumEncoded.bytes)[0], 0x18);
    XCTAssertEqual(((uint8_t*)mediumEncoded.bytes)[1], 0x64);

    // Large value (needs 2 additional bytes)
    CBORValue *large = [CBORValue unsignedInteger:300];
    NSData *largeEncoded = [large encode];
    XCTAssertEqual(largeEncoded.length, 3);
    XCTAssertEqual(((uint8_t*)largeEncoded.bytes)[0], 0x19);
}
```

---

## Exercises

📝 **Exercise 1: Hand-Encode a Value**

Encode the integer value **42** to CBOR by hand. What byte(s) result?

<details>
<summary>Hint</summary>

42 is less than 256, so check which range it falls in:
- < 24: fits in initial byte
- < 256: needs 1 additional byte

</details>

<details>
<summary>Solution</summary>

42 >= 24 and < 256, so needs 1 additional byte:
- Initial byte: `0x18` (major type 0, additional info 24)
- Value byte: `0x2A` (42 in hex)
- **Result: `0x18 0x2A`**

</details>

---

📝 **Exercise 2: Decode an Initial Byte**

Given the byte `0x83`, what is the major type and additional info?

<details>
<summary>Hint</summary>

Break into binary: `0x83` = `1000 0011`
- Top 3 bits = major type
- Bottom 5 bits = additional info

</details>

<details>
<summary>Solution</summary>

`0x83` = `1000 0011`
- Major type: `100` = 4 (array)
- Additional info: `00011` = 3 (count)
- **Meaning: Array with 3 elements**

</details>

---

📝 **Exercise 3: Sort Map Keys**

Sort these keys according to DAG-CBOR rules: `["zz", "a", "bbb"]`

<details>
<summary>Hint</summary>

First encode each key to CBOR, then sort by:
1. Encoded length (shorter first)
2. Lexicographic order (if same length)

</details>

<details>
<summary>Solution</summary>

Encoding each:
- `"a"` → `0x61 0x61` (2 bytes)
- `"zz"` → `0x62 0x7A 0x7A` (3 bytes)
- `"bbb"` → `0x63 0x62 0x62 0x62` (4 bytes)

Sorted by length: `["a", "zz", "bbb"]`

All have different lengths, so no need for lexicographic comparison.

</details>

---

📝 **Exercise 4: Calculate Encoding Size**

How many bytes would it take to encode this map in CBOR?

```objc
@{
    @"id": @123,
    @"name": @"Bob"
}
```

<details>
<summary>Hint</summary>

Break it down:
- Map header (count = 2)
- Key "id" (2 chars)
- Value 123
- Key "name" (4 chars)
- Value "Bob" (3 chars)

</details>

<details>
<summary>Solution</summary>

```
Map header: 0xA2 (1 byte)
Key "id": 0x62 0x69 0x64 (3 bytes)
Value 123: 0x18 0x7B (2 bytes)
Key "name": 0x64 0x6E 0x61 0x6D 0x65 (5 bytes)
Value "Bob": 0x63 0x42 0x6F 0x62 (4 bytes)

Total: 1 + 3 + 2 + 5 + 4 = 15 bytes
```

Compare to JSON (minified): `{"id":123,"name":"Bob"}` = 23 bytes
CBOR is 35% smaller!

</details>

---

## Summary

In this chapter, you learned:

- ✅ **Why CBOR exists**: Binary encoding for efficiency and determinism
- ✅ **CBOR structure**: Major types, initial byte, additional info
- ✅ **Integer encoding**: Minimal representation, big-endian byte order
- ✅ **String encoding**: Length + data pattern for text and bytes
- ✅ **Collection encoding**: Arrays and maps with recursive structures
- ✅ **DAG-CBOR**: Deterministic constraints for content addressing
- ✅ **Map sorting**: Length-first, lexicographic comparison
- ✅ **Tags**: Semantic meaning, especially Tag 42 for CIDs
- ✅ **Decoding**: Recursive parsing with offset tracking
- ✅ **Common mistakes**: Byte order, sorting, canonical encoding

## Key Takeaways

1. **Determinism is critical**: For content addressing to work, identical data must produce identical bytes. DAG-CBOR's sorting and canonical encoding rules ensure this.

2. **Binary is efficient**: CBOR typically saves 30-60% space compared to JSON, and the savings increase with larger, more complex data structures.

3. **Encoding is recursive**: Complex nested structures are encoded by recursively encoding their components, building up from primitives.

4. **Byte order matters**: Always use big-endian for network protocols. Never rely on native CPU byte order.

5. **Test determinism**: The same logical data encoded twice should produce byte-identical results.

## Looking Ahead

In **Chapter 6**, we'll implement **Merkle Search Trees (MST)** - the data structure that organizes all records in an AT Protocol repository. MSTs use CBOR to serialize their nodes, and rely on CIDs for linking child nodes.

You'll learn how to:
- Build a balanced tree structure
- Compute node CIDs from CBOR-encoded nodes
- Perform efficient key lookups and updates
- Maintain tree integrity through cryptographic hashes

Everything you learned about CBOR and CIDs comes together in the MST implementation!

---

**Files Referenced in This Chapter:**
- [CBOR.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/CBOR.h) - CBORValue interface
- [CBOR.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/CBOR.m) - Encoding/decoding implementation

**Further Reading:**
- [RFC 8949: CBOR Specification](https://www.rfc-editor.org/rfc/rfc8949.html)
- [DAG-CBOR Specification](https://ipld.io/specs/codecs/dag-cbor/spec/)
- [AT Protocol Data Model](https://atproto.com/specs/data-model)
