# Chapter 9: Decentralized Identifiers (DIDs)

Decentralized Identifiers (DIDs) are the foundation of identity in the AT Protocol. They provide cryptographically verifiable, self-sovereign identities without relying on central authorities. This chapter covers implementing `did:key` and understanding `did:plc`.

## What is a DID?

A DID is a globally unique identifier that:
- Is controlled by its subject (self-sovereign)
- Can be resolved to a DID Document
- Is cryptographically verifiable
- Doesn't require a central registry

**Format:**
```
did:method:method-specific-identifier
```

**AT Protocol uses two methods:**
| Method | Purpose | Example |
|--------|---------|---------|
| `did:key` | Ephemeral/embedded keys | `did:key:zQ3...` |
| `did:plc` | Persistent account identity | `did:plc:z72i...` |

## did:key Structure

A `did:key` encodes a public key directly in the identifier:

```
did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK
        │ └──────────────────────────────────────────────┘
        │                   Base58-BTC encoded
        │                   multicodec + public key
        └── Multibase prefix 'z' (base58btc)
```

### Multicodec Prefixes

| Code | Varint | Key Type |
|------|--------|----------|
| `0xe7` | `0xe7 0x01` | secp256k1 public (33 bytes compressed) |
| `0xed` | `0xed 0x01` | Ed25519 public (32 bytes) |
| `0x1200` | `0x80 0x24` | P-256 public (33 bytes compressed) |

## Implementing did:key

### The DIDKey Interface

```objc
// DIDKey.h
@interface DIDKey : NSObject <NSSecureCoding>

@property (nonatomic, copy, readonly) NSString *didKey;
@property (nonatomic, strong, readonly) NSData *publicKeyData;
@property (nonatomic, strong, readonly, nullable) NSData *privateKeyData;

+ (nullable instancetype)parse:(NSString *)didKeyString error:(NSError **)error;
+ (instancetype)generateSecp256k1;

- (nullable NSData *)signData:(NSData *)data error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data error:(NSError **)error;

@end
```

### Generating a did:key

```objc
+ (instancetype)generateSecp256k1 {
    // 1. Generate secp256k1 key pair
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    
    NSData *privateKey = keyPair.privateKey;          // 32 bytes
    NSData *publicKey = keyPair.compressedPublicKey;  // 33 bytes
    
    // 2. Build multicodec-prefixed data
    // secp256k1-pub multicodec is 0xe7 (varint: 0xe7 0x01)
    NSMutableData *multicodecData = [NSMutableData data];
    uint8_t multicodecBytes[2] = {0xe7, 0x01};
    [multicodecData appendBytes:multicodecBytes length:2];
    [multicodecData appendData:publicKey];
    
    // 3. Base58-BTC encode
    NSString *encoded = [self base58Encode:multicodecData];
    
    // 4. Add multibase prefix and did:key prefix
    NSString *didKey = [NSString stringWithFormat:@"did:key:z%@", encoded];
    
    return [[DIDKey alloc] initWithPublicKeyData:publicKey
                                    privateKeyData:privateKey
                                      didKeyString:didKey];
}
```

### Parsing a did:key

```objc
+ (nullable instancetype)parse:(NSString *)didKeyString error:(NSError **)error {
    // 1. Validate prefix
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
    
    NSString *encoded = [didKeyString substringFromIndex:prefix.length];
    
    // 2. Check multibase prefix ('z' = base58btc)
    if ([encoded characterAtIndex:0] != 'z') {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorInvalidMultibase
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"DID key must use base58btc encoding"}];
        }
        return nil;
    }
    
    // 3. Decode base58
    NSString *base58Data = [encoded substringFromIndex:1];
    NSData *decodedData = [self base58Decode:base58Data];
    
    // 4. Parse multicodec prefix
    uint8_t multicodec = ((const uint8_t *)decodedData.bytes)[0];
    NSData *keyData = [decodedData subdataWithRange:
        NSMakeRange(2, decodedData.length - 2)];  // Skip varint
    
    // 5. Handle by key type
    switch (multicodec) {
        case 0xe7:  // secp256k1
            if (keyData.length != 33) {
                // Error: wrong key length
                return nil;
            }
            return [[DIDKey alloc] initWithPublicKeyData:keyData 
                                            didKeyString:didKeyString];
        default:
            // Unsupported key type
            return nil;
    }
}
```

## Base58-BTC Encoding

Base58 is like Base64 but removes ambiguous characters (0, O, I, l):

```objc
static const char *alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

+ (NSString *)base58Encode:(NSData *)data {
    if (data.length == 0) return @"";
    
    const uint8_t *input = data.bytes;
    NSUInteger inputLength = data.length;
    
    // Count leading zeros
    NSUInteger zeroCount = 0;
    while (zeroCount < inputLength && input[zeroCount] == 0) {
        zeroCount++;
    }
    
    // Convert to base58
    NSMutableData *result = [NSMutableData dataWithCapacity:inputLength * 138 / 100 + 1];
    uint8_t *resultBytes = result.mutableBytes;
    NSUInteger resultLength = 1;
    resultBytes[0] = 0;
    
    for (NSUInteger i = zeroCount; i < inputLength; i++) {
        uint16_t carry = input[i];
        for (NSUInteger j = 0; j < resultLength; j++) {
            uint32_t digit = (uint32_t)(resultBytes[j] * 256 + carry);
            resultBytes[j] = digit % 58;
            carry = digit / 58;
        }
        while (carry > 0) {
            resultBytes[resultLength++] = carry % 58;
            carry /= 58;
        }
    }
    
    // Build string (reversed)
    NSMutableString *string = [NSMutableString string];
    for (NSUInteger i = resultLength; i > 0; i--) {
        [string appendFormat:@"%c", alphabet[resultBytes[i - 1]]];
    }
    
    // Add leading '1's for zero bytes
    for (NSUInteger i = 0; i < zeroCount; i++) {
        [string insertString:@"1" atIndex:0];
    }
    
    return [string copy];
}
```

## Signing and Verifying with did:key

```objc
- (nullable NSData *)signData:(NSData *)data error:(NSError **)error {
    if (!self.privateKeyData) {
        if (error) {
            *error = [NSError errorWithDomain:DIDKeyErrorDomain
                                         code:DIDKeyErrorSigningFailed
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Cannot sign: no private key"}];
        }
        return nil;
    }
    
    // Hash then sign
    NSData *hash = [self hashForSigning:data];
    return [[Secp256k1 shared] signHash:hash 
                         withPrivateKey:self.privateKeyData 
                                  error:error];
}

- (BOOL)verifySignature:(NSData *)signature 
                forData:(NSData *)data 
                  error:(NSError **)error {
    NSData *hash = [self hashForSigning:data];
    return [[Secp256k1 shared] verifySignature:signature 
                                       forHash:hash 
                                 withPublicKey:self.publicKeyData 
                                         error:error];
}

- (NSData *)hashForSigning:(NSData *)data {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
```

## did:plc Overview

`did:plc` is AT Protocol's primary identity method for persistent accounts:

```
did:plc:z72i7hdynmk6r22z27h6tvur
        └─────────────────────────┘
              Base32-sortable hash
              of genesis operation
```

**Key features:**
- **Recoverable**: Rotation keys allow recovery
- **Updatable**: Handle and PDS can change
- **Portable**: Move between PDSes
- **Directory-based**: Operations stored in PLC directory

### PLC Operations

| Operation | Purpose |
|-----------|---------|
| `create` | Genesis operation, establishes identity |
| `update` | Modify handle, keys, or PDS location |
| `tombstone` | Deactivate the DID |

**Create operation structure:**
```json
{
  "type": "create",
  "signingKey": "did:key:z...",
  "recoveryKey": "did:key:z...",
  "handle": "alice.bsky.social",
  "service": "https://pds.example.com",
  "prev": null,
  "sig": "<signature>"
}
```

## Practical Example: Account Creation Flow

```objc
// 1. Generate signing key pair
DIDKey *signingKey = [DIDKey generateSecp256k1];
NSLog(@"Signing key: %@", signingKey.didKey);

// 2. Generate recovery key (store safely!)
DIDKey *recoveryKey = [DIDKey generateSecp256k1];

// 3. Build PLC create operation
NSDictionary *createOp = @{
    @"type": @"create",
    @"signingKey": signingKey.didKey,
    @"recoveryKey": recoveryKey.didKey,
    @"handle": @"alice.bsky.social",
    @"service": @"https://my-pds.example.com",
    @"prev": [NSNull null]
};

// 4. Sign the operation
NSData *opData = [NSJSONSerialization dataWithJSONObject:createOp options:0 error:nil];
NSError *error = nil;
NSData *signature = [signingKey signData:opData error:&error];

// 5. Submit to PLC directory
// Response contains the generated did:plc identifier
```

## Summary

In this chapter, you learned:

- ✅ DID structure and purpose
- ✅ `did:key` format with multicodec and multibase
- ✅ Generating and parsing `did:key` identifiers
- ✅ Base58-BTC encoding/decoding
- ✅ Signing and verification with DIDs
- ✅ `did:plc` overview and operations

## Next Steps

In **Chapter 10**, we'll implement **PLC Operations & Account Creation**—the full workflow for creating and managing AT Protocol accounts.

---

**Files Referenced in This Chapter:**
- [DIDKey.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/DIDKey.h)
- [DIDKey.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/DIDKey.m)
