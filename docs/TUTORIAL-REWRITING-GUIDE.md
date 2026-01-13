# Tutorial Rewriting Guide

## Purpose

This guide provides principles and practical techniques for rewriting technical tutorials to be more pedagogically effective. The goal is to transform code-heavy tutorials into learning experiences that assume zero prior knowledge and build understanding incrementally.

## The Problem with Code-Heavy Tutorials

Current issues in many technical tutorials:
- Large code blocks with minimal explanation
- Assumption of prior knowledge
- "Here's how it is" rather than "Let's build this together"
- Missing motivation (the "why")
- No incremental progression from simple to complex
- Lack of exercises and reinforcement

## Core Pedagogical Principles

### 1. Zero-Knowledge Assumption

**Principle:** Assume the reader knows NOTHING about the topic.

**Techniques:**
- Define every technical term before using it
- Build from first principles
- Connect new concepts to familiar daily experiences
- Don't skip "obvious" steps

**Example Transformation:**

❌ **Before:**
```
CIDs use varint encoding for space efficiency.
```

✅ **After:**
```
CIDs contain numbers like the version (1) and codec (0x71). We could store each
as a fixed 4-byte integer, but that wastes space since most values are small.

Instead, we use **varint encoding** - a technique that uses only as many bytes
as needed. Think of it like writing numbers in scientific notation: we only
add more digits when the number requires it.
```

### 2. Explain Before Showing

**Principle:** Walk through the solution conceptually before showing code.

**Structure:**
1. State the problem or need
2. Explain the solution approach
3. Show code with annotations
4. Explain key implementation details

**Example Transformation:**

❌ **Before:**
```objc
+ (NSData *)sha256Digest:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
```

✅ **After:**
```
### Computing a SHA-256 Hash

We need to create a unique fingerprint of our data. SHA-256 is a
cryptographic hash function that:
- Always produces exactly 32 bytes of output
- Changes completely if even one bit of input changes
- Cannot be reversed (one-way function)

Apple's CommonCrypto framework provides an optimized implementation:

```objc
+ (NSData *)sha256Digest:(NSData *)data {
    // Allocate 32 bytes for the output (CC_SHA256_DIGEST_LENGTH = 32)
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];

    // Compute the hash
    // Parameters: input bytes, input length, output buffer
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);

    // Wrap in NSData for Objective-C
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
```

**Why these parameter types?**
- `data.bytes` → Raw pointer to the input bytes
- `(CC_LONG)data.length` → Length cast to CommonCrypto's expected type
- `hash` → Output buffer we pre-allocated
```

### 3. Incremental Complexity

**Principle:** Start with the simplest possible version, then evolve.

**Structure:**
1. Show minimal working version
2. Explain what it does
3. Identify limitations
4. Add one feature at a time
5. Explain each addition

**Example Transformation:**

❌ **Before:**
```objc
[Shows full production implementation with error handling, validation, edge cases]
```

✅ **After:**
```
### Building a CID Parser: Step by Step

**Version 1: Parse the basics**
```objc
+ (CID *)parseCID:(NSData *)data {
    // Just extract version and codec
    uint8_t version = data.bytes[0];
    uint8_t codec = data.bytes[1];
    // ... rest of data is multihash
}
```
This works for simple CIDs but has a problem: real CIDs use varint encoding,
so we can't assume fixed positions!

**Version 2: Handle varint encoding**
```objc
+ (CID *)parseCID:(NSData *)data {
    NSUInteger offset = 0;
    uint64_t version = [self readVarint:data offset:&offset];
    uint64_t codec = [self readVarint:data offset:&offset];
    // offset now points to the multihash
}
```
Better! But what if the data is invalid?

**Version 3: Add validation (production)**
```objc
+ (CID *)parseCID:(NSData *)data error:(NSError **)error {
    if (!data || data.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:@"CID"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid data"}];
        }
        return nil;
    }
    // ... rest of implementation with error handling
}
```
```

### 4. Active Learning

**Principle:** Engage the reader through questions, exercises, and exploration.

**Techniques:**
- Pose questions before revealing answers
- Include "What if?" scenarios
- Provide exercises at concept boundaries
- Show common mistakes and why they fail
- Include thought experiments

**Example:**

```
💡 **Think About It:** Why do we always sign a hash instead of raw data?

Consider what happens if you sign a 10 MB file directly:
- Signature operations are slow for large inputs
- Signature size might depend on input size
- No standard way to handle arbitrarily large messages

By signing a hash:
- ✅ Always exactly 32 bytes to sign
- ✅ Fast operation regardless of original data size
- ✅ Standardized approach across all signatures

📝 **Exercise:** What would happen if two different files produced the same
SHA-256 hash? (This is called a "collision")
1. Could an attacker exploit this?
2. Why is this astronomically unlikely?
3. What would it mean for content-addressing?
```

### 5. Visual Aids

**Principle:** Use tables, diagrams, and formatting to clarify structure.

**Techniques:**
- Tables for comparisons and component listings
- ASCII art for data structures
- Annotated examples showing byte-by-byte breakdown
- Before/after comparisons
- Decision trees

**Example:**

```
### CID Structure Visualized

```
┌─────────────────────────────────────────────────────┐
│                    Full CID                         │
├──────────┬──────────┬──────────────────────────────┤
│ Version  │  Codec   │        Multihash             │
│  (0x01)  │  (0x71)  │                              │
└──────────┴──────────┴──────────┬───────────────────┘
                                 │
                    ┌────────────┴──────────────────────┐
                    │        Multihash Structure        │
                    ├──────────┬──────────┬─────────────┤
                    │Algorithm │  Length  │   Digest    │
                    │  (0x12)  │  (0x20)  │  (32 bytes) │
                    └──────────┴──────────┴─────────────┘
```

| Field | Size | Example | Purpose |
|-------|------|---------|---------|
| Version | 1 byte (varint) | `0x01` | CID format version |
| Codec | 1 byte (varint) | `0x71` (dag-cbor) | Content type |
| Hash Algorithm | 1 byte | `0x12` (sha2-256) | Which hash function |
| Hash Length | 1 byte | `0x20` (32) | Digest size in bytes |
| Hash Digest | 32 bytes | `[binary data]` | Actual hash output |
```

### 6. Code Explanation Pattern

**Principle:** Every code block needs context, explanation, and follow-up.

**Structure for each code block:**

```
[Introduction: What are we building and why?]

[Code block with inline comments]

[Line-by-line or section-by-section breakdown]

[Key insights, gotchas, or design decisions]

[Connection to bigger picture]
```

**Template:**

```markdown
### [Feature Name]

[2-3 sentences explaining what this code accomplishes and why we need it]

```objc
[Code with strategic inline comments]
```

**Breaking this down:**

1. **Lines X-Y:** [What this section does]
   - Why we do it this way: [Design rationale]

2. **Line Z:** [Specific line explanation]
   - Common mistake: [What not to do]
   - Why this matters: [Consequences]

💡 **Key Insight:** [Important takeaway]

⚠️ **Watch Out:** [Common pitfall or edge case]

[How this connects to the larger system or next steps]
```

## Rewriting Workflow

### Phase 1: Analysis

Read through the original tutorial and identify:

1. **Assumed Knowledge**
   - What terms are used without definition?
   - What concepts are referenced without explanation?
   - Where does the tutorial jump from A to C, skipping B?

2. **Code-Heavy Sections**
   - Large code blocks with minimal explanation
   - Complex implementations shown without progression
   - Missing motivation for design decisions

3. **Missing Scaffolding**
   - Where would analogies help?
   - What visual aids would clarify structure?
   - Where are exercises needed?

4. **Technical Gaps**
   - Error cases not explained
   - Edge cases not mentioned
   - "Magic numbers" without explanation

### Phase 2: Planning

Create an outline:

```markdown
## [Chapter Title]

### Prerequisites
- [What reader needs to know coming in]

### Learning Objectives
- [What reader will be able to do after]

### Concept Progression
1. [First concept - simplest]
2. [Second concept - builds on first]
3. [Third concept - combines previous]

### Key Analogies
- [Concept] → [Familiar analogy]

### Exercises
- [Exercise 1: Simple reinforcement]
- [Exercise 2: Application]
- [Exercise 3: Exploration]
```

### Phase 3: Writing

Follow this structure for each major concept:

```markdown
## [Concept Name]

### The Problem
[What need or challenge does this address?]

### The Intuition
[Analogy or familiar example]

### The Simple Version
[Minimal working code with explanation]

### The Evolution
[How we enhance it, step by step]

### The Production Implementation
[Full code with comprehensive explanation]

### Common Mistakes
[What goes wrong and why]

### Exercises
[Hands-on practice]

### Connection
[How this fits into the bigger picture]
```

### Phase 4: Enhancement

Add:
- 📝 Exercise callouts
- 💡 Key insight boxes
- ⚠️ Warning boxes
- 🔍 Deep dive sections (optional advanced material)
- ✅ / ❌ Do's and don'ts
- Tables for comparisons
- ASCII diagrams for structures

### Phase 5: Quality Check

Verify:
- [ ] Every technical term defined before use
- [ ] Code blocks have before AND after explanation
- [ ] At least one analogy per major concept
- [ ] Clear progression from simple to complex
- [ ] Common mistakes addressed
- [ ] Exercises at concept boundaries
- [ ] No assumed knowledge beyond prerequisites
- [ ] Visual aids used where helpful
- [ ] All code is technically accurate
- [ ] File references preserved

## Example: Complete Transformation

### Original (Code-Heavy)

```markdown
## Base32 Encoding

CIDs use Base32 encoding:

```objc
+ (NSString *)base32Encode:(NSData *)data {
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
```
```

### Rewritten (Pedagogically Enhanced)

```markdown
## Making CIDs Human-Readable with Base32 Encoding

### The Problem: Binary Data Isn't Shareable

A CID is binary data - 35+ bytes of 1s and 0s. Try sharing that in a tweet or URL:

```
❌ [0x01, 0x71, 0x12, 0x20, 0x7a, 0x3e, ...]  // Can't click this!
✅ bafyreigdwqgxqmvjf...                      // Clean, shareable, clickable
```

We need to encode binary as text, but which encoding?

### Encoding Options

| Encoding | Characters | Example | Issues |
|----------|-----------|---------|---------|
| Base64 | A-Z, a-z, 0-9, +, / | `QmX7y...` | Case-sensitive, URL-unsafe |
| Base58 | No 0, O, I, l | `Qm...` | Not as compact |
| **Base32** | **a-z, 2-7** | **`bafy...`** | ✅ URL-safe, case-insensitive |

AT Protocol uses **Base32 lowercase** because:
- ✅ Works in URLs without escaping
- ✅ Case-insensitive (no confusion between I/l or 0/O)
- ✅ Reasonable space efficiency

### How Base32 Works: From 8-bit to 5-bit Chunks

Binary data is organized in 8-bit bytes, but Base32 encodes 5 bits at a time.

**Why 5 bits?** Because 2^5 = 32, giving us exactly 32 possible values, which we
can represent with 32 characters (a-z + 2-7).

**The Challenge:** Convert 8-bit bytes → 5-bit chunks:

```
Input bytes (8-bit each):
[0xCA, 0xFE]  = [11001010, 11111110]

Regrouped into 5-bit chunks:
11001 | 01011 | 11111 | 0....

Base32 values:
  25  |   11  |   31  |  (incomplete)
   ↓      ↓       ↓
   z      l       7
```

### The Algorithm: Bit Buffering

We need a buffer to collect bits and extract 5 at a time:

1. Start with empty buffer
2. Add 8 bits from next byte
3. Extract 5-bit chunks while buffer has ≥5 bits
4. Repeat until all bytes processed
5. Handle any remaining bits

**Visualization:**

```
Step 1: Add byte (8 bits)
Buffer: [--------]  →  [11001010]  (8 bits)

Step 2: Extract 5 bits
Buffer: [11001010]  →  [010] (3 bits remain)
Output: 11001 = 25 = 'z'

Step 3: Add next byte
Buffer: [010]  →  [01011111110]  (11 bits)

Step 4: Extract 5 bits (twice!)
Buffer: [01011111110]  →  [111110]  →  [10] (2 bits remain)
Output: 01011 = 11 = 'l'
Output: 11111 = 31 = '7'
```

### The Implementation: Step by Step

**Version 1: The Core Loop (No Error Handling)**

```objc
NSMutableString *result = [NSMutableString string];
uint64_t buffer = 0;        // Bit accumulator
int bitsLeft = 0;           // How many bits in buffer

for (NSUInteger i = 0; i < length; i++) {
    // Add 8 bits to buffer
    buffer = (buffer << 8) | bytes[i];
    bitsLeft += 8;

    // Extract 5-bit chunks
    while (bitsLeft >= 5) {
        int shift = bitsLeft - 5;
        uint8_t chunk = (buffer >> shift) & 0x1F;  // 0x1F = 0b11111 (5 bits)
        [result appendFormat:@"%c", kBase32Alphabet[chunk]];
        bitsLeft -= 5;
    }
}
```

**Breaking it down:**

1. **`buffer = (buffer << 8) | bytes[i]`**
   - Shift existing bits left to make room
   - OR in the new byte
   - Example: `0x01 << 8 | 0x23` = `0x0123`

2. **`(buffer >> shift) & 0x1F`**
   - Shift right to get desired 5 bits at bottom
   - AND with 0x1F to extract only those 5 bits
   - Example: `0b11001010 >> 3` = `0b00011001` → `& 0x1F` = `0b00011001`

3. **`kBase32Alphabet[chunk]`**
   - Use the 5-bit value (0-31) as index
   - Maps to alphabet: `"abcdefghijklmnopqrstuvwxyz234567"`

**Version 2: Handle Remaining Bits**

After the loop, we might have 1-4 bits left:

```objc
if (bitsLeft > 0) {
    // Pad to 5 bits by shifting left
    uint8_t chunk = (buffer << (5 - bitsLeft)) & 0x1F;
    [result appendFormat:@"%c", kBase32Alphabet[chunk]];
}
```

**Why pad left?** Base32 requires complete 5-bit chunks. If we have 3 bits
left (`010`), we shift left 2 positions to make it 5 bits: `01000`.

**Version 3: Production Code with Guards**

```objc
static const char kBase32Alphabet[] = "abcdefghijklmnopqrstuvwxyz234567";

+ (NSString *)base32Encode:(NSData *)data {
    // Guard: Empty input → empty output
    if (!data || data.length == 0) {
        return @"";
    }

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

        // Keep only remaining bits
        buffer &= ((1ULL << bitsLeft) - 1);
    }

    // Handle remaining bits
    if (bitsLeft > 0) {
        [result appendFormat:@"%c", kBase32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]];
    }

    return [result copy];
}
```

### Understanding the Buffer Mask

**Line:** `buffer &= ((1ULL << bitsLeft) - 1);`

This clears processed high bits to prevent overflow. Here's why:

```
If bitsLeft = 3:
  1ULL << 3     = 0b00001000
  - 1           = 0b00000111  ← Mask for 3 bits
  buffer & mask = keeps only lowest 3 bits
```

Without this, buffer grows indefinitely and eventually overflows.

### Complete Example

Let's encode the bytes `[0xCA, 0xFE]`:

```
Alphabet: "abcdefghijklmnopqrstuvwxyz234567"
          0  1  2  3  4  5  6  7  8  9  ...

Input: [0xCA, 0xFE] = [11001010, 11111110]

Step-by-step:
1. buffer=0, bitsLeft=0
2. Read 0xCA: buffer=11001010, bitsLeft=8
3. Extract 5: chunk=11001(25='z'), bitsLeft=3, buffer=010
4. Read 0xFE: buffer=01011111110, bitsLeft=11
5. Extract 5: chunk=01011(11='l'), bitsLeft=6, buffer=111110
6. Extract 5: chunk=11111(31='7'), bitsLeft=1, buffer=0
7. No more bytes, 1 bit left: 0 → 00000(pad) → chunk=0('a')

Result: "zl7a"
```

💡 **Key Insight:** Base32 encoding is just bit-shuffling! We're reorganizing
8-bit bytes into 5-bit chunks and using an alphabet to represent each chunk
as a character.

### Common Mistakes

❌ **Mistake 1: Forgetting to mask the buffer**
```objc
// Missing: buffer &= ((1ULL << bitsLeft) - 1);
```
**Problem:** Old bits remain in buffer, causing incorrect output or overflow

❌ **Mistake 2: Wrong padding direction**
```objc
// Wrong: buffer >> (5 - bitsLeft)  // Should be << not >>
```
**Problem:** Remaining bits should be left-aligned, not right-aligned

❌ **Mistake 3: Off-by-one in chunk extraction**
```objc
// Wrong: & 0x1E  (only 4 bits)
// Right: & 0x1F  (5 bits)
```

### Exercises

📝 **Exercise 1:** What is the Base32 encoding of a single byte `0x7F` (binary: `01111111`)?
- Hint: You'll extract one full 5-bit chunk and have 3 bits remaining

📝 **Exercise 2:** Why does Base32 use lowercase by default in AT Protocol?
- Hint: Think about DNS, which is case-insensitive

📝 **Exercise 3:** Implement Base32 decoding - convert the encoded string back to bytes
- Start by reversing the algorithm
- Map characters back to 5-bit values
- Accumulate into bytes

### Connection to CIDs

Now we can represent CIDs as strings:

```objc
// Binary CID → Base32 string
NSData *cidBytes = [...];  // Version + codec + multihash
NSString *base32 = [CID base32Encode:cidBytes];
NSString *cid = [@"b" stringByAppendingString:base32];  // Add multibase prefix

// Result: "bafyreigdwqgxqmvjf..."
//          ↑ 'b' = "this is base32 lowercase"
```

The `b` prefix is called a **multibase** identifier - it tells parsers which
encoding was used, so different encodings can coexist.
```

## Tips for Specific Content Types

### Mathematical Concepts
- Start with visual/geometric intuition
- Show concrete examples before formulas
- Explain each variable in a formula
- Provide worked examples step-by-step

### Data Structures
- Draw ASCII diagrams
- Show before/after for operations
- Explain invariants and why they matter
- Trace through operations step-by-step

### Algorithms
- Start with the simplest case
- Show progression to general case
- Visualize each step
- Explain time/space complexity in concrete terms

### APIs and Interfaces
- Show the simplest possible usage first
- Explain each parameter's purpose
- Provide complete working examples
- Show common patterns and anti-patterns

### Cryptography
- Explain the security property first (what it prevents)
- Use analogies (locks, seals, signatures)
- Explain key sizes and why they matter
- Show what attacks are prevented

## Conclusion

Great tutorials don't just show code - they teach concepts. By assuming zero knowledge,
building incrementally, and explaining thoroughly, we create learning experiences that
empower readers to truly understand, not just copy and paste.

Remember: **Your reader's confusion is not a failure on their part - it's an opportunity
for you to explain more clearly.**

## Quick Reference Checklist

When rewriting a tutorial section:

- [ ] Define all technical terms before use
- [ ] Start with the problem/need
- [ ] Provide analogies for abstract concepts
- [ ] Show simple version before complex
- [ ] Annotate code with explanatory comments
- [ ] Explain code after showing it
- [ ] Include common mistakes and why they fail
- [ ] Add exercises for reinforcement
- [ ] Use visual aids (tables, ASCII diagrams)
- [ ] Connect to bigger picture
- [ ] Test on someone unfamiliar with the topic
