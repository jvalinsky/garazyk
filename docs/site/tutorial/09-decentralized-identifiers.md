# Chapter 9: Decentralized Identifiers (DIDs)

In the previous chapter, we learned about secp256k1 cryptography—how to generate key pairs, sign data, and verify signatures. But having a cryptographic key pair raises an important question: how do we turn that into a **persistent identity** that works across the entire network?

This chapter introduces **Decentralized Identifiers (DIDs)**—the foundation of identity in the AT Protocol. Unlike traditional usernames tied to specific platforms, DIDs provide cryptographically verifiable, self-sovereign identities that you control without relying on any central authority.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Understand why decentralized identity matters and how it differs from platform-locked accounts
- Parse and generate `did:key` identifiers with multicodec and multibase encoding
- Implement Base58-BTC encoding from scratch
- Distinguish between `did:key` (ephemeral) and `did:plc` (persistent) identity methods
- Sign and verify data using DID-based identities

## Prerequisites

This chapter assumes you understand:
- **secp256k1 cryptography** - key generation, signing, verification (Chapter 8)
- **Public key cryptography basics** - asymmetric encryption concepts (Chapter 8)
- **Data encoding** - hexadecimal, binary representation (Chapter 4)

If you're not comfortable with these, especially Chapter 8, review that chapter first.

---

## The Problem: Platform-Locked Identity

### Why Identity Matters

Imagine you've built a following on Twitter—10,000 followers, years of posts, reputation in your community. What happens if:
- Twitter bans your account (mistake or policy change)
- Twitter shuts down (remember Vine?)
- You want to move to a different platform

**Answer:** You lose everything. Your identity, your content, your connections—all gone.

This happens because traditional platforms use **centralized identity**:
```
You → twitter.com/yourname ← Controlled by Twitter
You → facebook.com/yourname ← Controlled by Facebook
You → reddit.com/u/yourname ← Controlled by Reddit
```

The platform **owns** your identity. They can:
- Revoke it at any time
- Change the rules
- Shut down and take it all with them
- Lock you into their ecosystem

### The Vision: Self-Sovereign Identity

What if your identity was **yours**—not controlled by any company or server? What if you could:
- **Prove ownership** cryptographically (like signing a document)
- **Move freely** between platforms while keeping your identity
- **Recover access** even if a server disappears
- **Control your data** instead of trusting companies

This is **decentralized identity**: you own your identifier, and you prove ownership with cryptography.

---

## What is a DID?

A **Decentralized Identifier (DID)** is a globally unique identifier that:
- **You control** - no company or central authority can take it away
- **Is cryptographically verifiable** - you prove ownership by signing with your private key
- **Works everywhere** - not tied to any specific service
- **Resolves to a document** - tells systems how to verify you and communicate with you

### The Structure

Every DID follows this format:
```
did:method:method-specific-identifier
│   │      │
│   │      └─ Unique identifier (varies by method)
│   └─ How to resolve/verify this DID
└─ Always starts with "did:"
```

**Examples:**
```
did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme
│   │   └─────────────────────────────────────────────────────┘
│   │                  Base58-encoded public key
│   └─ "key" method: DID embeds the key directly

did:plc:z72i7hdynmk6r22z27h6tvur
│   │   └───────────────────────┘
│   │      Base32 hash of genesis operation
│   └─ "plc" method: DID references operations in a directory
```

Think of DID methods like different file systems: `http://` and `ftp://` are different protocols for accessing resources. Similarly, `did:key:` and `did:plc:` are different methods for resolving identities.

---

## AT Protocol's Two DID Methods

AT Protocol uses **two** DID methods, each for different purposes:

| Aspect | `did:key` | `did:plc` |
|--------|-----------|-----------|
| **Purpose** | Ephemeral, embedded keys | Persistent account identity |
| **Use Case** | Temporary tokens, one-time operations | Your main account identity |
| **Portability** | Not portable (key is identity) | Fully portable (can move between servers) |
| **Recoverability** | Lost key = lost identity | Recovery keys enable account recovery |
| **Updateability** | Cannot update (immutable) | Can update handle, PDS, keys |
| **Example** | `did:key:zQ3sh...` | `did:plc:z72i7...` |

**Analogy:**
- **`did:key`** is like a **burner phone number** - simple, self-contained, disposable
- **`did:plc`** is like your **real phone number** - persistent, can change carriers, recoverable if lost

### When to Use Each

**Use `did:key` when:**
- Generating ephemeral signing keys
- Creating short-lived authentication tokens
- Testing or development
- You don't need persistence or recoverability

**Use `did:plc` when:**
- Creating a user account
- Building a persistent identity
- Needing portability between PDSes
- Requiring recovery mechanisms

**In practice:** Your main AT Protocol account uses `did:plc`, but many internal operations (JWT signing, temporary credentials) use `did:key` for simplicity.

---

## Understanding did:key Structure

A `did:key` directly embeds a public key in the identifier itself. Let's break down how this works step by step.

### The Complete Picture

```
did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme
│      │└───────────────────────────────────────────────────┘
│      │              Base58-encoded payload
│      └─ 'z' is the multibase prefix (means "base58btc")
└─ DID method prefix

Payload (before Base58 encoding):
┌──────────────┬────────────────────────────────────┐
│   Multicodec │        Public Key Bytes            │
│   (2 bytes)  │        (33 bytes for secp256k1)    │
├──────────────┼────────────────────────────────────┤
│  0xe7 0x01   │  0x02 0xb1 0xf4 ... (compressed)   │
└──────────────┴────────────────────────────────────┘
   │
   └─ Tells us this is a secp256k1 public key
```

Three encoding layers:
1. **Multicodec** - Identifies the key type (secp256k1, Ed25519, etc.)
2. **Base58-BTC** - Encodes the bytes into ASCII text
3. **Multibase** - Labels which base encoding was used

Let's understand each layer.

---

## Layer 1: Multicodec

### The Problem: How Do We Know Key Type?

Imagine receiving these bytes:
```
0x02 0xb1 0xf4 0x8e 0xc4 ... (33 bytes total)
```

What kind of key is this?
- secp256k1 compressed public key? (33 bytes)
- Ed25519 public key? (32 bytes, but could have a prefix byte)
- P-256 public key? (33 bytes)
- Something else?

**You can't tell** just by looking at the bytes. Different cryptographic algorithms can produce keys of the same length.

### The Solution: Multicodec Prefixes

**Multicodec** is a standard that prefixes data with a code indicating its type. It uses **varint encoding** (variable-length integers) to be space-efficient.

**Common multicodec codes for DIDs:**

| Key Type | Code (hex) | Varint Bytes | Description |
|----------|------------|--------------|-------------|
| secp256k1-pub | `0xe7` | `0xe7 0x01` | Compressed secp256k1 public key (33 bytes) |
| ed25519-pub | `0xed` | `0xed 0x01` | Ed25519 public key (32 bytes) |
| p256-pub | `0x1200` | `0x80 0x24` | P-256 compressed public key (33 bytes) |

**Why varint?** Small numbers (< 128) encode in 1 byte. Larger numbers need 2+ bytes. This saves space for common codes.

### Varint Encoding Explained

Varint uses the high bit (bit 7) as a "more bytes coming" flag:
- **0xxxxxxx** - Single byte, value 0-127
- **1xxxxxxx 0xxxxxxx** - Two bytes, value 128+

For secp256k1 (`0xe7 = 231`):
```
231 >= 128, so we need 2 bytes:
Byte 1: 231 % 128 + 128 = 103 + 128 = 231 = 0xe7
Byte 2: 231 / 128 = 1 = 0x01

Result: [0xe7] [0x01]
```

### Practical Example

**Encoding a secp256k1 public key:**

```
Step 1: Start with 33-byte compressed public key
[0x02] [0xb1 0xf4 0x8e 0xc4 ... 32 more bytes]
   │
   └─ 0x02 prefix indicates compressed key (y-coordinate is even)

Step 2: Add multicodec prefix for secp256k1-pub (0xe7)
[0xe7] [0x01] [0x02] [0xb1 0xf4 0x8e 0xc4 ... 32 more bytes]
   │      │      └──────────────────────────────────────────┘
   │      │              33-byte public key
   │      └─ Varint continuation byte
   └─ Multicodec code for secp256k1-pub

Result: 35 bytes total (2-byte prefix + 33-byte key)
```

Now anyone receiving this data knows: "This is a secp256k1 public key."

---

## Layer 2: Base58-BTC Encoding

### The Problem: Binary Data Isn't Portable

We now have 35 bytes of data (multicodec + public key), but:
- Can't put raw bytes in URLs or JSON strings
- Binary data doesn't copy/paste well
- Need to share identifiers as text

**Base64** is common, but has a problem: **ambiguous characters**
```
Base64: 0 O I l 1 / +
        │ │ │ │ │
        └─┴─┴─┴─┴─ Easy to misread or mistype
```

Is that a zero or the letter O? The letter I or lowercase L? This matters for identifiers people might type or read aloud.

### The Solution: Base58-BTC

**Base58** removes ambiguous characters from the alphabet:

```
Base64:  ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
         Removed:                                            0    O  I  l

Base58:  123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
         58 characters: no 0, O, I, l, +, or /
```

**The "-BTC" suffix** means it uses Bitcoin's specific Base58 alphabet (there are slight variations).

### How Base58 Encoding Works

Base58 is like converting a big number from base 256 (bytes) to base 58 (alphabet).

**The Intuition: Think of odometer digits**

When your car's odometer goes from `999` to `1000`, the digits "roll over." Base58 is the same idea, but with a 58-character alphabet instead of 10 digits.

**Step-by-Step Algorithm:**

Let's encode `[0xCA, 0xFE]` (2 bytes) to Base58:

```
Step 1: Treat input as big-endian number
0xCAFE = 51966 in decimal

Step 2: Repeatedly divide by 58, collecting remainders
51966 ÷ 58 = 895 remainder 56  → alphabet[56] = 'u'
  895 ÷ 58 =  15 remainder 25  → alphabet[25] = 'R'
   15 ÷ 58 =   0 remainder 15  → alphabet[15] = 'G'

Step 3: Result is remainders reversed: "GRu"
```

**Why reversed?** We extract digits from least significant to most significant (like reading odometer right-to-left), so we reverse to get proper order.

**Handling leading zeros:**

Leading zero bytes are special—they become leading '1's:
```
Input: [0x00, 0x00, 0xCA, 0xFE]
       └──────┘
       2 leading zeros → "11GRu"
```

### Concrete Example: Encoding Our did:key Payload

```
Input: [0xe7, 0x01, 0x02, 0xb1, 0xf4, 0x8e, ...] (35 bytes)

Step 1: Convert to large integer (treat as big-endian number)
→ Very large number (35 bytes = 280 bits!)

Step 2: Divide by 58 repeatedly, collecting remainders
→ Produces ~48 characters (35 bytes * 1.38 ≈ 48 chars)

Step 3: Map each remainder to Base58 alphabet
→ "Q3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme"

Step 4: Check for leading zeros
→ No leading zeros in this example
```

**Result:** `Q3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme`

---

## Layer 3: Multibase Prefix

### The Problem: Which Base Encoding?

We've Base58-encoded our data, but how does someone receiving it know we used Base58? Could be:
- Base58 (58-character alphabet)
- Base64 (different alphabet)
- Base32 (even different alphabet)
- Hexadecimal (base16)

### The Solution: Multibase

**Multibase** prefixes encoded data with a single character indicating the encoding:

| Prefix | Encoding | Example |
|--------|----------|---------|
| `z` | base58btc | `zQ3shokFTS...` |
| `b` | base32 | `bafkreih5az...` |
| `f` | base16 (hex) | `f4d756c74...` |
| `u` | base64url | `uaGVsbG8gd29...` |
| `m` | base64 | `mSGVsbG8gV29...` |

**For `did:key`**, we always use **`z`** (base58btc) because:
- Human-readable (no ambiguous characters)
- Compact (shorter than base32)
- Standard in DID specifications

### Putting All Three Layers Together

```
Original public key (33 bytes):
[0x02] [0xb1 0xf4 0x8e 0xc4 0x7a ...]

↓ Step 1: Add multicodec prefix (2 bytes)
[0xe7] [0x01] [0x02] [0xb1 0xf4 0x8e 0xc4 0x7a ...]
└──────────┘
Identifies as secp256k1-pub

↓ Step 2: Base58-BTC encode (35 bytes → ~48 chars)
Q3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme

↓ Step 3: Add multibase prefix (1 char)
zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme
│
└─ 'z' means "this is base58btc"

↓ Step 4: Add DID method prefix
did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme

Final DID: 69 characters total
```

**Why these encodings matter:**
- **Multicodec** enables multiple key types to coexist
- **Base58** prevents transcription errors
- **Multibase** enables future encoding flexibility
- Together: a future-proof, human-friendly identifier format

---

## Implementing did:key Generation

Now that we understand the structure, let's implement it step by step.

### Version 1: The Basic Structure

Let's start with the simplest version that just shows the structure:

```objc
// DIDKey.h
@interface DIDKey : NSObject

@property (nonatomic, copy, readonly) NSString *didKey;
@property (nonatomic, strong, readonly) NSData *publicKeyData;

+ (instancetype)generateSecp256k1;

@end
```

```objc
// DIDKey.m
+ (instancetype)generateSecp256k1 {
    // 1. Generate a key pair (using Chapter 8's Secp256k1 class)
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSData *publicKey = keyPair.compressedPublicKey;  // 33 bytes

    // 2. Build multicodec-prefixed data
    NSMutableData *payload = [NSMutableData data];
    uint8_t prefix[2] = {0xe7, 0x01};  // secp256k1-pub multicodec
    [payload appendBytes:prefix length:2];
    [payload appendData:publicKey];

    // 3. Base58 encode
    NSString *encoded = [self base58Encode:payload];

    // 4. Build DID string
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", encoded];

    return [[DIDKey alloc] initWithPublicKey:publicKey didKey:didKey];
}
```

**What this does:**
1. Generates a secp256k1 key pair (33-byte compressed public key)
2. Prepends the multicodec identifier (`0xe7 0x01`)
3. Base58-encodes the combined data
4. Adds the `did:key:z` prefix

**Limitations:**
- No private key storage (can't sign)
- No error handling
- Hardcoded to secp256k1

### Version 2: Add Private Key Support

Now let's store the private key so we can sign:

```objc
@interface DIDKey : NSObject

@property (nonatomic, copy, readonly) NSString *didKey;
@property (nonatomic, strong, readonly) NSData *publicKeyData;
@property (nonatomic, strong, readonly, nullable) NSData *privateKeyData;  // NEW

+ (instancetype)generateSecp256k1;

// NEW: Signing capabilities
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
                  error:(NSError **)error;

@end
```

```objc
+ (instancetype)generateSecp256k1 {
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];

    // NEW: Store both private and public keys
    NSData *privateKey = keyPair.privateKey;          // 32 bytes
    NSData *publicKey = keyPair.compressedPublicKey;  // 33 bytes

    // Build multicodec-prefixed data
    NSMutableData *payload = [NSMutableData data];
    uint8_t prefix[2] = {0xe7, 0x01};
    [payload appendBytes:prefix length:2];
    [payload appendData:publicKey];

    // Base58 encode and build DID string
    NSString *encoded = [self base58Encode:payload];
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", encoded];

    // NEW: Include private key in initialization
    return [[DIDKey alloc] initWithPublicKey:publicKey
                                  privateKey:privateKey  // NEW
                                      didKey:didKey];
}

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    if (!self.privateKeyData) {
        if (error) {
            *error = [NSError errorWithDomain:@"DIDKeyError"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Cannot sign: no private key"}];
        }
        return nil;
    }

    // Hash the data, then sign the hash
    NSData *hash = [self sha256Hash:data];
    return [[Secp256k1 shared] signHash:hash
                         withPrivateKey:self.privateKeyData
                                  error:error];
}
```

**What changed:**
- Added `privateKeyData` property (optional—parsing a DID won't have it)
- Store private key during generation
- Implement `signData:` method using secp256k1 signing from Chapter 8

**Why hash before signing?**
secp256k1 signs fixed-size hashes (32 bytes), not arbitrary-length data. We SHA-256 hash the data first.

### The Production Implementation

Here's the full, production-ready implementation:

```objc
// DIDKey.h
@interface DIDKey : NSObject <NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *didKey;
@property (nonatomic, strong, readonly) NSData *publicKeyData;
@property (nonatomic, strong, readonly, nullable) NSData *privateKeyData;

// Generation
+ (instancetype)generateSecp256k1;

// Parsing
+ (nullable instancetype)parse:(NSString *)didKeyString error:(NSError **)error;

// Signing & Verification
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
                  error:(NSError **)error;

@end
```

```objc
// DIDKey.m
+ (instancetype)generateSecp256k1 {
    // 1. Generate secp256k1 key pair
    NSError *error = nil;
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:&error];
    if (!keyPair) {
        NSLog(@"Failed to generate key pair: %@", error);
        return nil;
    }

    NSData *privateKey = keyPair.privateKey;          // 32 bytes
    NSData *publicKey = keyPair.compressedPublicKey;  // 33 bytes (0x02/0x03 prefix + 32 bytes)

    // 2. Build multicodec-prefixed payload
    //    secp256k1-pub multicodec: 0xe7 (varint: 0xe7 0x01)
    NSMutableData *multicodecData = [NSMutableData dataWithCapacity:35];
    uint8_t multicodecPrefix[2] = {0xe7, 0x01};
    [multicodecData appendBytes:multicodecPrefix length:2];
    [multicodecData appendData:publicKey];

    // 3. Base58-BTC encode the payload
    NSString *base58Encoded = [self base58Encode:multicodecData];

    // 4. Add multibase prefix ('z') and DID method prefix
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", base58Encoded];

    // 5. Create and return DIDKey instance
    return [[DIDKey alloc] initWithPublicKeyData:publicKey
                                    privateKeyData:privateKey
                                      didKeyString:didKey];
}
```

**Breaking this down:**

**Lines 1-7:** Key pair generation
- Use Chapter 8's `Secp256k1` class to generate a key pair
- Error handling: return `nil` if generation fails
- Get both private (32 bytes) and public (33 bytes compressed) keys

**Lines 9-13:** Multicodec prefix
- Create mutable buffer for payload (2 + 33 = 35 bytes)
- Prepend `0xe7 0x01` (secp256k1-pub multicodec varint)
- Append the compressed public key

**Line 15:** Base58 encoding
- Encode the 35-byte payload to Base58-BTC string
- Result is ~48 characters

**Line 18:** Final DID construction
- Prepend `did:key:z` to the Base58 string
- `z` is the multibase prefix for base58btc

💡 **Key Insight:** The entire public key is embedded in the DID. Anyone can extract it by reversing these steps—this is intentional! The DID is self-contained.

⚠️ **Watch Out:** Never include the private key in the DID string. Only the public key is encoded. The private key is stored separately for signing.

---

## Implementing Base58-BTC Encoding

### The Alphabet

```objc
// Base58-BTC alphabet (Bitcoin's variant)
static const char base58Alphabet[] =
    "123456789"                    // No '0' (zero)
    "ABCDEFGHJKLMNPQRSTUVWXYZ"     // No 'O' (capital O) or 'I' (capital I)
    "abcdefghijkmnopqrstuvwxyz";   // No 'l' (lowercase L)
```

### The Algorithm: From Bytes to Base58

```objc
+ (NSString *)base58Encode:(NSData *)data {
    if (data.length == 0) return @"";

    const uint8_t *input = data.bytes;
    NSUInteger inputLength = data.length;

    // Step 1: Count leading zero bytes
    NSUInteger zeroCount = 0;
    while (zeroCount < inputLength && input[zeroCount] == 0) {
        zeroCount++;
    }

    // Step 2: Allocate output buffer (log_58(256) ≈ 1.38, so ~138% of input size)
    NSUInteger maxSize = inputLength * 138 / 100 + 1;
    uint8_t *output = calloc(maxSize, sizeof(uint8_t));
    NSUInteger outputLength = 1;
    output[0] = 0;

    // Step 3: For each input byte, multiply output by 256 and add input
    for (NSUInteger i = zeroCount; i < inputLength; i++) {
        uint16_t carry = input[i];

        // Multiply output by 256 and add current byte
        for (NSUInteger j = 0; j < outputLength; j++) {
            uint32_t product = (uint32_t)(output[j] * 256 + carry);
            output[j] = product % 58;       // Store remainder
            carry = product / 58;           // Propagate quotient
        }

        // Handle remaining carry by extending output
        while (carry > 0) {
            output[outputLength++] = carry % 58;
            carry /= 58;
        }
    }

    // Step 4: Build string from output (in reverse order)
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = outputLength; i > 0; i--) {
        [result appendFormat:@"%c", base58Alphabet[output[i - 1]]];
    }

    // Step 5: Add leading '1' characters for leading zero bytes
    for (NSUInteger i = 0; i < zeroCount; i++) {
        [result insertString:@"1" atIndex:0];
    }

    free(output);
    return [result copy];
}
```

**How this works:**

**Step 1 (Lines 8-11):** Count leading zeros
- Leading zero bytes are special in Base58
- Each zero byte becomes a leading '1' character
- We skip these in the main algorithm and add them back at the end

**Step 2 (Lines 13-17):** Allocate output buffer
- Base58 is less efficient than Base256 (bytes)
- Maximum size: `inputLength * 138 / 100 + 1` (conservative estimate)
- Initialize with a single zero digit

**Step 3 (Lines 19-33):** Main encoding loop
- **For each input byte:**
  1. Treat output as a big number in base 58
  2. Multiply by 256 (shifting left in base 256)
  3. Add the current input byte
  4. Convert back to base 58 by taking remainders

**Example trace for [0xCA, 0xFE]:**
```
Start: output = [0]

Process 0xCA (202 decimal):
  output[0] = (0 * 256 + 202) % 58 = 202 % 58 = 28
  carry = 202 / 58 = 3
  output[1] = 3
  → output = [28, 3]

Process 0xFE (254 decimal):
  output[0] = (28 * 256 + 254) % 58 = 7422 % 58 = 56
  carry = 7422 / 58 = 127
  output[1] = (3 * 256 + 127) % 58 = 895 % 58 = 25
  carry = 895 / 58 = 15
  output[2] = 15
  → output = [56, 25, 15]
```

**Step 4 (Lines 36-39):** Build string
- Output digits are least-significant first (reversed)
- Map each digit to the Base58 alphabet
- Append in reverse order: alphabet[15]=G, alphabet[25]=R, alphabet[56]=u → "GRu"

**Step 5 (Lines 41-44):** Handle leading zeros
- Each leading zero byte → leading '1' character
- '1' is the zero character in Base58 alphabet

💡 **Key Insight:** We're doing base conversion—treating the input bytes as a single large number and converting from base 256 (bytes) to base 58 (alphabet).

### Decoding Base58 (The Reverse)

```objc
+ (NSData *)base58Decode:(NSString *)string {
    if (string.length == 0) return [NSData data];

    // Count leading '1' characters (these become leading zeros)
    NSUInteger zeroCount = 0;
    while (zeroCount < string.length && [string characterAtIndex:zeroCount] == '1') {
        zeroCount++;
    }

    // Allocate output buffer
    NSUInteger maxSize = string.length * 733 / 1000 + 1;  // log_256(58) ≈ 0.733
    uint8_t *output = calloc(maxSize, sizeof(uint8_t));
    NSUInteger outputLength = 1;
    output[0] = 0;

    // Process each Base58 character
    for (NSUInteger i = zeroCount; i < string.length; i++) {
        char c = [string characterAtIndex:i];

        // Find character in alphabet
        const char *p = strchr(base58Alphabet, c);
        if (!p) {
            free(output);
            return nil;  // Invalid character
        }
        uint8_t digit = (uint8_t)(p - base58Alphabet);

        // Multiply output by 58 and add digit
        uint16_t carry = digit;
        for (NSUInteger j = 0; j < outputLength; j++) {
            uint32_t product = (uint32_t)(output[j] * 58 + carry);
            output[j] = product % 256;
            carry = product / 256;
        }
        while (carry > 0) {
            output[outputLength++] = carry % 256;
            carry /= 256;
        }
    }

    // Build NSData (reversed, with leading zeros)
    NSMutableData *result = [NSMutableData dataWithCapacity:zeroCount + outputLength];
    uint8_t zero = 0;
    for (NSUInteger i = 0; i < zeroCount; i++) {
        [result appendBytes:&zero length:1];
    }
    for (NSUInteger i = outputLength; i > 0; i--) {
        [result appendBytes:&output[i - 1] length:1];
    }

    free(output);
    return [result copy];
}
```

**The reverse process:**
- Multiply output by 58 (instead of 256)
- Add each Base58 digit
- Convert back to base 256 (bytes)
- Leading '1's become leading zero bytes

---

## Parsing a did:key

<script setup>
const sharedDIDCode = `#import <Foundation/Foundation.h>

// --- Base58 Helper ---
static const char base58Alphabet[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

NSData *base58Decode(NSString *string) {
    if (string.length == 0) return [NSData data];
    NSUInteger zeroCount = 0;
    while (zeroCount < string.length && [string characterAtIndex:zeroCount] == '1') zeroCount++;
    
    // Simple decoding (mock-ish but functional)
    // For full implementation see tutorial text.
    // This decoder is sufficient for the demo strings.
    
    // ... (Compact decoder)
    NSUInteger maxSize = string.length * 733 / 1000 + 1;
    uint8_t *output = calloc(maxSize, 1);
    NSUInteger outputLength = 1;
    
    for (NSUInteger i = zeroCount; i < string.length; i++) {
        const char *p = strchr(base58Alphabet, [string characterAtIndex:i]);
        if (!p) { free(output); return nil; }
        uint8_t digit = p - base58Alphabet;
        uint16_t carry = digit;
        for (NSUInteger j = 0; j < outputLength; j++) {
            uint32_t product = output[j] * 58 + carry;
            output[j] = product % 256;
            carry = product / 256;
        }
        while (carry) output[outputLength++] = carry % 256;
    }
    
    NSMutableData *res = [NSMutableData dataWithLength:zeroCount + outputLength];
    uint8_t *bytes = res.mutableBytes;
    for (NSUInteger i = 0; i < outputLength; i++) bytes[zeroCount + i] = output[outputLength - 1 - i];
    free(output);
    return res;
}

NSString *base58Encode(NSData *data) {
    if (data.length == 0) return @"";
    const uint8_t *input = data.bytes;
    NSUInteger len = data.length;
    NSUInteger zeroCount = 0;
    while (zeroCount < len && input[zeroCount] == 0) zeroCount++;
    
    NSUInteger maxSize = len * 138 / 100 + 1;
    uint8_t *output = calloc(maxSize, 1);
    NSUInteger outputLength = 1;

    for (NSUInteger i = zeroCount; i < len; i++) {
        uint16_t carry = input[i];
        for (NSUInteger j = 0; j < outputLength; j++) {
            uint32_t product = output[j] * 256 + carry;
            output[j] = product % 58;
            carry = product / 58;
        }
        while (carry) output[outputLength++] = carry % 58;
    }

    NSMutableString *res = [NSMutableString string];
    for (NSUInteger i = 0; i < zeroCount; i++) [res appendString:@"1"];
    for (NSUInteger i = outputLength; i > 0; i--) [res appendFormat:@"%c", base58Alphabet[output[i-1]]];
    free(output);
    return res;
}
`;

const didParserCode = sharedDIDCode + `
void parseDIDKey(NSString *did) {
    printf("Parsing: %s\\n", did.UTF8String);
    if (![did hasPrefix:@"did:key:z"]) {
        printf("Error: Invalid prefix.\\n");
        return;
    }
    NSString *encoded = [did substringFromIndex:9];
    NSData *data = base58Decode(encoded);
    if (!data) { printf("Error: Invalid Base58.\\n"); return; }
    
    const uint8_t *bytes = data.bytes;
    if (data.length > 2 && bytes[0] == 0xE7 && bytes[1] == 0x01) {
        printf("Key Type:  secp256k1 (0xe701)\\n");
        NSData *pubKey = [data subdataWithRange:NSMakeRange(2, data.length - 2)];
        printf("Public Key: %s... (%lu bytes)\\n", 
               [pubKey subdataWithRange:NSMakeRange(0, 4)].description.UTF8String, 
               pubKey.length);
    } else {
        printf("Key Type:  Unknown\\n");
    }
    printf("\\n");
}

int main() {
    @autoreleasepool {
        parseDIDKey(@"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme");
    }
    return 0;
}`;

const exercise1Code = sharedDIDCode + `
// --- EXERCISE 1: Hand-Encode did:key ---

NSString * encodeDIDKey(NSData *compressedPubKey) {
    // TODO:
    // 1. Create mutable data
    // 2. Append multicodec prefix (0xe7, 0x01)
    // 3. Append public key
    // 4. Base58 encode
    // 5. Prepend "did:key:z"
    
    return @""; // Replace this
}

int main() {
    @autoreleasepool {
        // Example Key: 0x02b1f4...
        uint8_t k[] = {0x02, 0xb1, 0xf4, 0x8e, 0xc4, 0xa9, 0x2a, 0x8f, 0x1f, 0x99, 
                       0x4b, 0xdc, 0x8e, 0x00, 0x52, 0xbc, 0xe9, 0xd3, 0x97, 0x76, 
                       0xb4, 0x6b, 0x01, 0xb9, 0xe7, 0xc0, 0xf2, 0xe3, 0x1c, 0x7a, 
                       0xe4, 0xed, 0x9c};
        NSData *pub = [NSData dataWithBytes:k length:33];
        
        NSString *did = encodeDIDKey(pub);
        printf("Result: %s\\n", did.UTF8String);
        
        NSString *expected = @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme";
        if ([did isEqualToString:expected]) {
            printf("PASS: Correctly encoded.\\n");
        } else {
            printf("FAIL: Expected %s\\n", expected.UTF8String);
        }
    }
    return 0;
}`;

const exercise2Code = sharedDIDCode + `
// --- EXERCISE 2: Identify Key Type ---

NSString * identifyKeyType(NSString *did) {
    // TODO:
    // 1. Strip prefix
    // 2. Decode Base58
    // 3. Check first byte(s)
    // Return @"secp256k1", @"ed25519", or @"unknown"
    
    // Hint: secp256k1 = 0xe7, ed25519 = 0xed
    
    return @"unknown";
}

int main() {
    @autoreleasepool {
        NSString *d1 = @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme";
        NSString *d2 = @"did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK";
        
        printf("DID 1: %s\\n", identifyKeyType(d1).UTF8String);
        printf("DID 2: %s\\n", identifyKeyType(d2).UTF8String);
        
        if ([identifyKeyType(d1) isEqualToString:@"secp256k1"] && 
            [identifyKeyType(d2) isEqualToString:@"ed25519"]) {
            printf("PASS: Identified correctly.\\n");
        } else {
            printf("FAIL.\\n");
        }
    }
    return 0;
}`;

const exercise3Code = `#import <Foundation/Foundation.h>

// --- EXERCISE 3: Key Rotation Op Builder ---

NSDictionary * buildUpdateOp(NSString *did, NSString *newKeyDID, NSString *prevOpHash) {
    // TODO: Build the dictionary for a PLC update operation
    // Fields: type="update", rotationKeys=[newKeyDID], alsoKnownAs, services...
    // For this exercise, focus on rotating the signing key.
    
    return @{};
}

int main() {
    @autoreleasepool {
        NSDictionary *op = buildUpdateOp(@"did:plc:123", @"did:key:zNew...", @"bafyPrev");
        
        printf("Op Type: %s\\n", [op[@"type"] UTF8String]);
        NSArray *keys = op[@"rotationKeys"];
        if (keys.count > 0) {
            printf("New Key: %s\\n", [keys[0] UTF8String]);
        }
        
        if ([op[@"type"] isEqualToString:@"update"] && [keys containsObject:@"did:key:zNew..."]) {
            printf("PASS: Operation structure correct.\\n");
        } else {
            printf("FAIL.\\n");
        }
    }
    return 0;
}`;
</script>


<ObjcRunner :initialCode="didParserCode" />

Now let's reverse the generation process to parse a DID string:

```objc
+ (nullable instancetype)parse:(NSString *)didKeyString error:(NSError **)error {
    // 1. Validate DID prefix
    NSString *prefix = @"did:key:";
    if (![didKeyString hasPrefix:prefix]) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"DID key must start with 'did:key:'"}];
        }
        return nil;
    }

    // 2. Extract the encoded portion (after "did:key:")
    NSString *encoded = [didKeyString substringFromIndex:prefix.length];

    // 3. Validate multibase prefix ('z' = base58btc)
    if (encoded.length == 0 || [encoded characterAtIndex:0] != 'z') {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidMultibase
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"DID key must use 'z' prefix (base58btc)"}];
        }
        return nil;
    }

    // 4. Decode Base58 (strip 'z' prefix first)
    NSString *base58Data = [encoded substringFromIndex:1];
    NSData *decodedData = [self base58Decode:base58Data];
    if (!decodedData || decodedData.length < 3) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorDecodingFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Failed to decode Base58 data"}];
        }
        return nil;
    }

    // 5. Parse multicodec prefix
    const uint8_t *bytes = decodedData.bytes;
    uint8_t multicodecType = bytes[0];

    // Varint decoding (simple case: 2-byte varints)
    if (decodedData.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidMulticodec
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Invalid multicodec prefix"}];
        }
        return nil;
    }

    // Skip multicodec prefix (2 bytes for secp256k1)
    NSData *keyData = [decodedData subdataWithRange:
        NSMakeRange(2, decodedData.length - 2)];

    // 6. Validate key type and length
    switch (multicodecType) {
        case 0xe7: {  // secp256k1-pub
            if (keyData.length != 33) {
                if (error) {
                    *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                                 code:DIDKeyErrorInvalidKeyLength
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"secp256k1 key must be 33 bytes"}];
                }
                return nil;
            }

            // Validate compression prefix (0x02 or 0x03)
            const uint8_t *keyBytes = keyData.bytes;
            if (keyBytes[0] != 0x02 && keyBytes[0] != 0x03) {
                if (error) {
                    *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                                 code:DIDKeyErrorInvalidKeyFormat
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"Invalid secp256k1 compression prefix"}];
                }
                return nil;
            }

            return [[DIDKey alloc] initWithPublicKeyData:keyData
                                            privateKeyData:nil  // No private key when parsing
                                              didKeyString:didKeyString];
        }

        case 0xed: {  // ed25519-pub
            if (keyData.length != 32) {
                if (error) {
                    *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                                 code:DIDKeyErrorInvalidKeyLength
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                 @"Ed25519 key must be 32 bytes"}];
                }
                return nil;
            }
            // Create Ed25519 DIDKey (not implemented in this tutorial)
            return nil;
        }

        default:
            if (error) {
                *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                             code:DIDKeyErrorUnsupportedKeyType
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:
                                                 @"Unsupported multicodec: 0x%02x", multicodecType]}];
            }
            return nil;
    }
}
```

**Breaking this down:**

**Step 1 (Lines 2-12):** Validate DID prefix
- Must start with `did:key:`
- Return error if malformed

**Step 2 (Line 15):** Extract encoded portion
- Everything after `did:key:`

**Step 3 (Lines 17-26):** Check multibase prefix
- Must be `z` (base58btc)
- Other multibase prefixes not supported for DIDs

**Step 4 (Lines 28-39):** Decode Base58
- Strip the `z` prefix
- Decode using our Base58 decoder
- Validate we got at least 3 bytes (2-byte multicodec + 1+ byte key)

**Step 5 (Lines 41-57):** Parse multicodec
- First byte identifies key type
- Skip 2-byte varint prefix (for secp256k1)
- Extract remaining bytes as key data

**Step 6 (Lines 59-119):** Validate key type and length
- **secp256k1 (0xe7):** Must be exactly 33 bytes, valid compression prefix (0x02 or 0x03)
- **Ed25519 (0xed):** Must be exactly 32 bytes (not fully implemented here)
- **Unknown type:** Return error

**Note:** Parsing doesn't give us the private key—only the public key. This is correct! DIDs are public identifiers.

---

## Signing and Verifying with did:key

Now that we can generate and parse DIDs, let's implement signing and verification:

```objc
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    // 1. Check we have a private key
    if (!self.privateKeyData) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Cannot sign: no private key"}];
        }
        return nil;
    }

    // 2. Hash the data with SHA-256
    NSData *hash = [self hashForSigning:data];

    // 3. Sign the hash using secp256k1
    return [[Secp256k1 shared] signHash:hash
                         withPrivateKey:self.privateKeyData
                                  error:error];
}

- (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
                  error:(NSError **)error {
    // 1. Hash the data (same as signing)
    NSData *hash = [self hashForSigning:data];

    // 2. Verify using the public key
    return [[Secp256k1 shared] verifySignature:signature
                                       forHash:hash
                                 withPublicKey:self.publicKeyData
                                         error:error];
}

- (NSData *)hashForSigning:(NSData *)data {
    // SHA-256 hash (32 bytes)
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
```

**Why hash before signing?**

secp256k1's signing algorithm requires a **32-byte hash**, not arbitrary-length data. We use SHA-256 because:
- Produces 32-byte output (perfect for secp256k1)
- Cryptographically secure
- Standard in many protocols

**Verification process:**
1. Hash the data the same way (SHA-256)
2. Verify signature using the public key
3. No private key needed for verification (that's the point of public key crypto!)

### Complete Example: Sign and Verify

```objc
// Generate a new DID
DIDKey *alice = [DIDKey generateSecp256k1];
NSLog(@"Alice's DID: %@", alice.didKey);

// Sign some data
NSString *message = @"Hello, AT Protocol!";
NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
NSError *error = nil;
NSData *signature = [alice signData:messageData error:&error];

if (!signature) {
    NSLog(@"Signing failed: %@", error);
    return;
}

NSLog(@"Signature: %@", signature);

// Verify the signature
BOOL valid = [alice verifySignature:signature forData:messageData error:&error];
NSLog(@"Signature valid: %@", valid ? @"YES" : @"NO");

// Try verifying with wrong data (should fail)
NSData *wrongData = [@"Different message" dataUsingEncoding:NSUTF8StringEncoding];
BOOL invalid = [alice verifySignature:signature forData:wrongData error:&error];
NSLog(@"Wrong data verification: %@", invalid ? @"YES" : @"NO");  // Should be NO
```

**Output:**
```
Alice's DID: did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme
Signature: <4da5c8f2 ...64 bytes...>
Signature valid: YES
Wrong data verification: NO
```

---

## Common Mistakes

### Mistake 1: Encoding Private Key in DID

❌ **What people try:**
```objc
// WRONG: Including private key
NSMutableData *payload = [NSMutableData data];
[payload appendBytes:multicodecPrefix length:2];
[payload appendData:keyPair.privateKey];  // DON'T DO THIS!
[payload appendData:keyPair.compressedPublicKey];
```

**Why this fails:**
- DIDs are **public identifiers**—they're shared openly
- Including private key means anyone can sign as you
- Private key should NEVER leave secure storage

✅ **Correct approach:**
```objc
// RIGHT: Only public key in DID
NSMutableData *payload = [NSMutableData data];
[payload appendBytes:multicodecPrefix length:2];
[payload appendData:keyPair.compressedPublicKey];  // Public only!
// Private key stored separately in keyPair.privateKey
```

**Why this works:**
- DID contains only public key (safe to share)
- Private key stored separately, never transmitted
- Follows public key cryptography principles

### Mistake 2: Forgetting Multicodec Prefix

❌ **What people try:**
```objc
// WRONG: Direct Base58 encoding without multicodec
NSString *encoded = [self base58Encode:keyPair.compressedPublicKey];
NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", encoded];
```

**Why this fails:**
- No way to know what type of key this is
- Is it secp256k1? Ed25519? Something else?
- Parser can't determine correct verification algorithm

✅ **Correct approach:**
```objc
// RIGHT: Add multicodec prefix first
NSMutableData *payload = [NSMutableData data];
uint8_t multicodec[2] = {0xe7, 0x01};  // secp256k1-pub
[payload appendBytes:multicodec length:2];
[payload appendData:keyPair.compressedPublicKey];
NSString *encoded = [self base58Encode:payload];
```

**Why this works:**
- Multicodec prefix identifies key type
- Parser knows which algorithm to use
- Supports multiple key types in same system

### Mistake 3: Wrong Base58 Alphabet

❌ **What people try:**
```objc
// WRONG: Using Flickr's Base58 alphabet
static const char wrongAlphabet[] =
    "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
```

**Why this fails:**
- AT Protocol uses **Bitcoin's Base58 alphabet** (base58btc)
- Different alphabet = different encodings for same bytes
- DIDs won't match across systems

✅ **Correct approach:**
```objc
// RIGHT: Bitcoin's Base58 alphabet (base58btc)
static const char base58Alphabet[] =
    "123456789"                    // Digits first
    "ABCDEFGHJKLMNPQRSTUVWXYZ"     // Uppercase next
    "abcdefghijkmnopqrstuvwxyz";   // Lowercase last
```

**Why this works:**
- Matches multibase spec for 'z' prefix
- Interoperable with other AT Protocol implementations
- Standard across Bitcoin ecosystem

### Mistake 4: Not Validating Compression Prefix

❌ **What people try:**
```objc
// WRONG: Accepting any 33-byte data
if (keyData.length == 33) {
    return [[DIDKey alloc] initWithPublicKeyData:keyData ...];
}
```

**Why this fails:**
- Valid secp256k1 compressed keys start with `0x02` or `0x03`
- Random 33 bytes aren't a valid public key
- Will fail during cryptographic operations

✅ **Correct approach:**
```objc
// RIGHT: Validate compression prefix
const uint8_t *bytes = keyData.bytes;
if (keyData.length == 33 && (bytes[0] == 0x02 || bytes[0] == 0x03)) {
    return [[DIDKey alloc] initWithPublicKeyData:keyData ...];
}
// else: invalid key format error
```

**Why this works:**
- Validates key format before accepting
- Catches corrupted or invalid data early
- Prevents cryptographic errors downstream

---

## Visualizing the did:key Structure

### Complete Byte Breakdown

```
did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme

┌─────────┬───┬──────────────────────────────────────────────┐
│ did:key │ z │ Q3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQi │
├─────────┼───┼──────────────────────────────────────────────┤
│ Method  │MB │             Base58-BTC Encoded               │
│ Prefix  │ │ │                                              │
└─────────┴───┴──────────────────────────────────────────────┘
             │
             └─ Multibase prefix: 'z' = base58btc

Base58-BTC decodes to 35 bytes:

Byte:    0     1     2     3     4     5  ... 34
      ┌─────┬─────┬─────┬─────┬─────┬─────────────┐
      │ 0xe7│ 0x01│ 0x02│ 0xb1│ 0xf4│ ... 28 more │
      └─────┴─────┴─────┴─────┴─────┴─────────────┘
        │     │     └─────────────────────────────┘
        │     │        33-byte compressed public key
        │     │        (0x02 prefix + 32-byte x-coordinate)
        │     └─ Varint continuation byte
        └─ Multicodec: secp256k1-pub
```

### Encoding Flow Diagram

```
┌──────────────────────────────────────┐
│   Generate secp256k1 Key Pair        │
│   Private: 32 bytes                  │
│   Public: 33 bytes (compressed)      │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│   Add Multicodec Prefix              │
│   [0xe7][0x01][33-byte public key]   │
│   Total: 35 bytes                    │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│   Base58-BTC Encode                  │
│   35 bytes → ~48 characters          │
│   "Q3shokFTS3br..."                  │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│   Add Multibase Prefix               │
│   'z' + "Q3shokFTS3br..."            │
│   "zQ3shokFTS3br..."                 │
└────────────┬─────────────────────────┘
             │
             ▼
┌──────────────────────────────────────┐
│   Add DID Method Prefix              │
│   "did:key:" + "zQ3shokFTS3br..."    │
│   Final DID (69 chars)               │
└──────────────────────────────────────┘
```

---

## Understanding did:plc

While `did:key` embeds the key directly, `did:plc` takes a different approach: it references operations stored in a **PLC Directory**.

### The Structure

```
did:plc:z72i7hdynmk6r22z27h6tvur
        └───────────────────────┘
          Base32-sortable hash of
          the genesis operation
```

**Key differences from did:key:**

| Aspect | did:key | did:plc |
|--------|---------|---------|
| **Key location** | Embedded in DID | Stored in operation |
| **Mutability** | Immutable | Can be updated |
| **Recovery** | No recovery | Recovery keys enable recovery |
| **Portability** | Not portable | Can move between PDSes |
| **Directory** | Self-contained | Requires PLC directory lookup |

### PLC Operations

`did:plc` uses **operations** stored in a directory to manage identity:

| Operation | Purpose | Required Fields |
|-----------|---------|-----------------|
| `create` | Genesis (first) operation | signingKey, recoveryKey, handle, service |
| `update` | Modify keys, handle, or PDS | Same as create, plus `prev` (hash of previous op) |
| `tombstone` | Deactivate the DID permanently | Just `prev` and signature |

### Create Operation Structure

```json
{
  "type": "create",
  "signingKey": "did:key:zQ3sho...",       // Your signing key (did:key!)
  "recoveryKey": "did:key:zQ3abc...",      // Recovery key (different from signing)
  "handle": "alice.bsky.social",           // Your human-readable handle
  "service": "https://pds.example.com",    // Your PDS location
  "prev": null,                            // No previous op (genesis)
  "sig": "<base64-signature>"              // Signature over operation data
}
```

**How the DID is computed:**

1. Serialize the create operation (without `sig` field) to DAG-CBOR
2. Hash with SHA-256
3. Take first 28 bytes
4. Encode with Base32-sortable
5. Result: `did:plc:z72i7hdynmk6r22z27h6tvur`

### Why Two Keys?

**Signing Key:** Used for daily operations
- Signs posts, updates, XRPC requests
- Can be rotated if compromised

**Recovery Key:** Emergency backup
- Kept in cold storage (offline)
- Used only if signing key is lost
- Last resort to regain control

**Analogy:** Signing key is your everyday car key. Recovery key is the spare key in a safe at home.

### Portability: Moving Between PDSes

This is the killer feature of `did:plc`:

```
Step 1: You're on pds-a.example.com
Operation: { "service": "https://pds-a.example.com", ... }

Step 2: You decide to move to pds-b.example.com
1. Export your data from pds-a
2. Import to pds-b
3. Submit update operation:
   {
     "type": "update",
     "service": "https://pds-b.example.com",  // NEW
     "prev": "<hash of previous operation>",
     "sig": "<signature with signing key>"
   }

Step 3: Your DID now points to pds-b
Anyone resolving your DID sees the new service location
```

**Your followers don't need to do anything.** The DID stays the same; only the service location changes.

### Resolving a did:plc

To resolve a `did:plc` to a DID Document:

1. **Query the PLC directory** (e.g., `https://plc.directory/did:plc:z72i7...`)
2. **Get the operation chain** (create → update → update → ...)
3. **Verify signatures** on each operation
4. **Apply operations in order** to get current state
5. **Return DID Document** with current keys and service

**Example DID Document:**
```json
{
  "id": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "verificationMethod": [{
    "id": "did:plc:z72i7...#atproto",
    "type": "EcdsaSecp256k1VerificationKey2019",
    "controller": "did:plc:z72i7...",
    "publicKeyMultibase": "zQ3sho..."  // Current signing key
  }],
  "service": [{
    "id": "#atproto_pds",
    "type": "AtprotoPersonalDataServer",
    "serviceEndpoint": "https://pds.example.com"
  }]
}
```

This tells clients:
- **Who you are:** The DID
- **How to verify you:** The signing key (publicKeyMultibase)
- **Where to find your data:** The service endpoint (PDS URL)

---

## Practical Example: Account Creation Flow

Let's walk through creating an AT Protocol account with `did:plc`:

### Step 1: Generate Keys

```objc
// Generate signing key pair (for daily use)
DIDKey *signingKey = [DIDKey generateSecp256k1];
NSLog(@"Signing key: %@", signingKey.didKey);
// Output: did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme

// Generate recovery key pair (for emergencies)
DIDKey *recoveryKey = [DIDKey generateSecp256k1];
NSLog(@"Recovery key: %@", recoveryKey.didKey);
// Output: did:key:zQ3abc123XYZ...

// Store recovery key safely (offline storage, encrypted backup, etc.)
```

### Step 2: Build Create Operation

```objc
NSDictionary *createOp = @{
    @"type": @"create",
    @"signingKey": signingKey.didKey,
    @"recoveryKey": recoveryKey.didKey,
    @"handle": @"alice.bsky.social",
    @"service": @"https://my-pds.example.com",
    @"prev": [NSNull null]  // Genesis operation
};
```

### Step 3: Sign the Operation

```objc
// Serialize to JSON (canonical form)
NSError *error = nil;
NSData *opData = [NSJSONSerialization dataWithJSONObject:createOp
                                                 options:NSJSONWritingSortedKeys
                                                   error:&error];

// Sign with signing key's private key
NSData *signature = [signingKey signData:opData error:&error];
if (!signature) {
    NSLog(@"Signing failed: %@", error);
    return;
}

// Encode signature as Base64
NSString *sigBase64 = [signature base64EncodedStringWithOptions:0];
```

### Step 4: Submit to PLC Directory

```objc
// Add signature to operation
NSMutableDictionary *signedOp = [createOp mutableCopy];
signedOp[@"sig"] = sigBase64;

// Submit to PLC directory
NSURL *plcURL = [NSURL URLWithString:@"https://plc.directory/"];
NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:plcURL];
request.HTTPMethod = @"POST";
request.HTTPBody = [NSJSONSerialization dataWithJSONObject:signedOp
                                                  options:0
                                                    error:nil];

// Send request...
// Response will include: {"did": "did:plc:z72i7..."}
```

### Step 5: Use Your New DID

```objc
NSString *myDID = @"did:plc:z72i7hdynmk6r22z27h6tvur";  // From response

// Now you can:
// - Create posts signed with signingKey
// - Authenticate XRPC requests
// - Resolve your DID to find your PDS
// - Update handle or move to different PDS with update operations
```

---

## Exercises

### 📝 Exercise 1: Hand-Encode a did:key

Given a secp256k1 compressed public key:
```
0x02b1f48ec4a92a8f1f994bdc8e0052bce9d39776b46b01b9e7c0f2e31c7ae4ed9c
```

**Tasks:**
1. Add the multicodec prefix for secp256k1-pub
2. Base58-encode the result
3. Add the multibase prefix
4. Construct the full `did:key` string

<ObjcRunner :initialCode="exercise1Code" />


### 📝 Exercise 2: Identify Key Types from DIDs

For each DID, determine the key type:

1. `did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme`
2. `did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK`

<ObjcRunner :initialCode="exercise2Code" />


### 📝 Exercise 3: Op Builder

Implement a method to build a PLC update operation dictionary:

<ObjcRunner :initialCode="exercise3Code" />


Key rotation flow:
1. Generate new signing key
2. Create update operation with new `signingKey` field
3. Sign operation with **old** signing key (proving you control current account)
4. Submit to PLC directory
5. After update, only new key is valid for new operations

Old signatures remain valid because they were valid at the time they were created.


---

## Connection to AT Protocol

### DIDs in Action

In AT Protocol, DIDs serve multiple purposes:

1. **Account Identity**
   - Your `did:plc` is your permanent account identifier
   - Example: `did:plc:z72i7...` represents alice.bsky.social
   - Handle can change, DID stays the same

2. **Content Signing**
   - Every post is signed with your signing key
   - Signature proves authorship
   - Can't be forged (cryptographic proof)

3. **Authentication**
   - XRPC requests signed with your key
   - PDS verifies signature using your DID Document
   - No passwords needed—just cryptographic proof

4. **Federation**
   - AppViews resolve DIDs to find your PDS
   - Other users verify your posts by checking your DID
   - Works across different PDSes seamlessly

### DID Resolution Flow

```
User posts "Hello World"
    │
    ▼
Post record created with DID: did:plc:z72i7...
    │
    ▼
Signed with signing key from DID Document
    │
    ▼
Stored in MST (Merkle Search Tree)
    │
    ▼
Other users see post
    │
    ▼
Resolve DID → Get DID Document → Extract signing key
    │
    ▼
Verify signature → Confirm authorship
```

This decentralized identity system enables:
- **Portability:** Move between PDSes without losing identity
- **Verification:** Cryptographically prove you authored content
- **Decentralization:** No single point of control
- **Recovery:** Regain access with recovery keys

---

## Summary

In this chapter, you learned:

- ✅ **Decentralized identity:** Self-sovereign identities you control, not tied to any platform
- ✅ **DID structure:** `did:method:method-specific-identifier` format
- ✅ **Multicodec:** Prefixes that identify key types (secp256k1, Ed25519, etc.)
- ✅ **Base58-BTC encoding:** Human-friendly encoding without ambiguous characters
- ✅ **Multibase:** Labels indicating encoding scheme (`z` = base58btc)
- ✅ **did:key generation:** Embed public key directly in identifier
- ✅ **did:key parsing:** Extract and validate public key from DID string
- ✅ **Signing and verification:** Prove identity with cryptographic signatures
- ✅ **did:plc operations:** Persistent, updatable, portable identity with recovery

## Key Takeaways

1. **DIDs provide self-sovereign identity:** You own your identifier through cryptographic proof, not platform permission. No company can revoke it.

2. **Encoding layers enable flexibility:** Multicodec (key type), Base58 (human-friendly), and Multibase (encoding label) work together to create extensible identifiers.

3. **did:key vs did:plc trade-offs:** did:key is simple and self-contained (great for ephemeral use), while did:plc adds complexity but enables portability, recovery, and updates (essential for accounts).

## Looking Ahead

In **Chapter 10**, we'll implement **PLC Operations & Account Creation**—the full workflow for creating and managing AT Protocol accounts.

You'll discover how to:
- Compute DID identifiers from operations
- Chain operations for updates
- Implement tombstone (deactivation)
- Build a self-hosted PLC directory

This builds directly on the DID concepts you just learned, especially `did:plc` operations.

---

**Files Referenced in This Chapter:**
- [DIDKey.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/DIDKey.h) - DID key interface
- [DIDKey.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/DIDKey.m) - DID key implementation
- [Secp256k1.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/Secp256k1.h) - Cryptographic signing (Chapter 8)

**Further Reading:**
- [DID Core Specification](https://www.w3.org/TR/did-core/) - W3C standard for DIDs
- [did:key Method Spec](https://w3c-ccg.github.io/did-method-key/) - Detailed did:key specification
- [Multicodec Table](https://github.com/multiformats/multicodec/blob/master/table.csv) - All multicodec codes
- [Multibase Specification](https://github.com/multiformats/multibase) - Encoding prefixes
- [AT Protocol DID Documentation](https://atproto.com/specs/did) - AT Protocol-specific DID usage

---

## Appendix: Base58 Alphabet Comparison

### Why Different Alphabets Exist

Different systems use different Base58 alphabets for historical reasons:

| Variant | Alphabet Start | Used By |
|---------|----------------|---------|
| **base58btc** | `123456789ABC...` | Bitcoin, IPFS, DIDs |
| **base58flickr** | `123456789abc...` | Flickr short URLs |
| **base58ripple** | `rpshnaf39wBUD...` | Ripple addresses |

**AT Protocol uses base58btc** (Bitcoin's alphabet) because:
- Most widely adopted in decentralized systems
- Consistent with multibase standard
- Uppercase before lowercase (preserves lexicographic ordering)

### Debugging Tip: Wrong Alphabet

If you get a DID that doesn't verify:
1. Check you're using base58**btc**, not base58flickr
2. Verify the alphabet string exactly matches Bitcoin's
3. Ensure uppercase letters come before lowercase

**Common error:**
```objc
// WRONG: Lowercase first
"123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"

// RIGHT: Uppercase first
"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
```

This subtle difference will produce completely different encodings!
