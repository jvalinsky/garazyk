# Chapter 8: Elliptic Curve Cryptography with secp256k1

Welcome to Part III! Cryptography is foundational to the AT Protocol—every commit is signed, every identity is a public key. This chapter covers integrating the `secp256k1` curve via the libsecp256k1 C library.

## Why secp256k1?

The AT Protocol uses secp256k1 (the same curve as Bitcoin) for:

- **Commit signing**: Every repository commit is signed by the owner
- **DID keys**: `did:key` identities encode secp256k1 public keys
- **PLC operations**: Account operations require cryptographic signatures
- **Service auth**: Inter-service JWTs use secp256k1 signing

> [!NOTE]
> Apple's Security framework doesn't natively support secp256k1 for ECDSA. We use the battle-tested `libsecp256k1` library from the Bitcoin project.

## Key Sizes

| Component | Size |
|-----------|------|
| Private key | 32 bytes |
| Uncompressed public key | 65 bytes (0x04 + x + y) |
| Compressed public key | 33 bytes (0x02/0x03 + x) |
| Signature | 64 bytes (r + s) |

## The C Wrapper

Since libsecp256k1 is pure C, we create a thin wrapper header:

```c
// secp256k1_wrapper_c.h
#pragma once
#include <stdint.h>

typedef enum {
    Secp256k1ErrorNone = 0,
    Secp256k1ErrorInvalidPrivateKey = 1,
    Secp256k1ErrorInvalidPublicKey = 2,
    Secp256k1ErrorSigningFailed = 3,
    Secp256k1ErrorVerificationFailed = 4,
    Secp256k1ErrorInvalidSignature = 5
} Secp256k1Error;

typedef struct { uint8_t data[32]; } Secp256k1PrivateKey;
typedef struct { uint8_t data[65]; } Secp256k1PublicKey;
typedef struct { uint8_t data[64]; } Secp256k1Signature;

Secp256k1Error secp256k1_wrapper_generate_key_pair(
    Secp256k1PrivateKey *privateKey,
    Secp256k1PublicKey *publicKey
);

Secp256k1Error secp256k1_wrapper_sign(
    const Secp256k1PrivateKey *privateKey,
    const uint8_t *hash32,
    Secp256k1Signature *signature
);

Secp256k1Error secp256k1_wrapper_verify(
    const Secp256k1PublicKey *publicKey,
    const uint8_t *hash32,
    const Secp256k1Signature *signature
);

void secp256k1_wrapper_public_key_serialize_compressed(
    const Secp256k1PublicKey *publicKey,
    uint8_t *output33
);

const char *secp256k1_error_string(Secp256k1Error error);
```

## The Objective-C Interface

```objc
// Secp256k1.h
@interface Secp256k1KeyPair : NSObject

@property (nonatomic, strong, readonly) NSData *privateKey;         // 32 bytes
@property (nonatomic, strong, readonly) NSData *publicKey;          // 65 bytes
@property (nonatomic, strong, readonly) NSData *compressedPublicKey; // 33 bytes

+ (nullable instancetype)generateKeyPair:(NSError **)error;
+ (nullable instancetype)keyPairWithPrivateKey:(NSData *)privateKey error:(NSError **)error;

- (nullable NSData *)signHash:(NSData *)hash error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature forHash:(NSData *)hash error:(NSError **)error;

@end

@interface Secp256k1 : NSObject

+ (instancetype)shared;

- (nullable Secp256k1KeyPair *)generateKeyPairWithError:(NSError **)error;
- (nullable NSData *)signHash:(NSData *)hash 
               withPrivateKey:(NSData *)privateKey 
                        error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)signature 
                forHash:(NSData *)hash 
          withPublicKey:(NSData *)publicKey 
                  error:(NSError **)error;

@end
```

## Key Generation

```objc
+ (nullable instancetype)generateKeyPair:(NSError **)error {
    Secp256k1PrivateKey privKey;
    Secp256k1PublicKey pubKey;

    Secp256k1Error result = secp256k1_wrapper_generate_key_pair(&privKey, &pubKey);
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:
                    secp256k1_error_string(result)]
            }];
        }
        return nil;
    }

    Secp256k1KeyPair *keyPair = [[Secp256k1KeyPair alloc] init];
    
    // Store 32-byte private key
    keyPair->_privateKey = [NSData dataWithBytes:privKey.data length:32];
    
    // Store 65-byte uncompressed public key
    keyPair->_publicKey = [NSData dataWithBytes:pubKey.data length:65];

    // Also store compressed form (33 bytes)
    uint8_t compressed[33];
    secp256k1_wrapper_public_key_serialize_compressed(&pubKey, compressed);
    keyPair->_compressedPublicKey = [NSData dataWithBytes:compressed length:33];

    return keyPair;
}
```

## Signing Messages

Always sign a 32-byte hash, never raw data:

```objc
- (nullable NSData *)signHash:(NSData *)hash error:(NSError **)error {
    // Validate input
    if (hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorSigningFailed
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Hash must be 32 bytes"
            }];
        }
        return nil;
    }

    // Copy private key to C struct
    Secp256k1PrivateKey privKey;
    memcpy(privKey.data, self.privateKey.bytes, 32);

    // Sign
    Secp256k1Signature sig;
    Secp256k1Error result = secp256k1_wrapper_sign(&privKey, hash.bytes, &sig);
    
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:
                    secp256k1_error_string(result)]
            }];
        }
        return nil;
    }

    // Return 64-byte signature (r + s)
    return [NSData dataWithBytes:sig.data length:64];
}
```

## Verifying Signatures

```objc
- (BOOL)verifySignature:(NSData *)signature 
                forHash:(NSData *)hash 
          withPublicKey:(NSData *)publicKey 
                  error:(NSError **)error {
    // Validate inputs
    if (publicKey.length != 65) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidPublicKey
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Public key must be 65 bytes"
            }];
        }
        return NO;
    }

    if (signature.length != 64) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorInvalidSignature
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Signature must be 64 bytes"
            }];
        }
        return NO;
    }

    if (hash.length != 32) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:Secp256k1ErrorVerificationFailed
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Hash must be 32 bytes"
            }];
        }
        return NO;
    }

    // Copy to C structs
    Secp256k1PublicKey pubKey;
    memcpy(pubKey.data, publicKey.bytes, 65);

    Secp256k1Signature sig;
    memcpy(sig.data, signature.bytes, 64);

    // Verify
    Secp256k1Error result = secp256k1_wrapper_verify(&pubKey, hash.bytes, &sig);
    
    if (result != Secp256k1ErrorNone) {
        if (error) {
            *error = [NSError errorWithDomain:Secp256k1ErrorDomain
                                         code:result
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:
                    secp256k1_error_string(result)]
            }];
        }
        return NO;
    }

    return YES;
}
```

## Practical Example: Signing a Repository Commit

```objc
// 1. Generate signing key
Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
NSLog(@"Public key: %@", keyPair.compressedPublicKey);

// 2. Create commit data
NSDictionary *commitData = @{
    @"did": @"did:plc:abc123",
    @"version": @3,
    @"data": self.mstRootCID.stringValue,
    @"rev": [TID tid].stringValue,
    @"prev": @""
};
NSData *commitCBOR = [self serializeCommit:commitData];

// 3. Hash the commit (always sign hashes, not raw data)
NSData *hash = [CID rawSha256:commitCBOR];

// 4. Sign
NSError *error = nil;
NSData *signature = [keyPair signHash:hash error:&error];
if (!signature) {
    NSLog(@"Signing failed: %@", error);
    return;
}

// 5. Attach signature to commit
commitData[@"sig"] = signature;

// 6. Later, verify
BOOL valid = [keyPair verifySignature:signature forHash:hash error:&error];
NSLog(@"Signature valid: %@", valid ? @"YES" : @"NO");
```

## Building with libsecp256k1

The CMakeLists.txt includes secp256k1 as a subproject:

```cmake
option(BUILD_SECP256K1 "Build secp256k1 library" ON)

if(BUILD_SECP256K1)
  set(SECP256K1_BUILD_SHARED OFF CACHE BOOL "Build as static library" FORCE)
  set(SECP256K1_ENABLE_MODULE_RECOVERY ON CACHE BOOL "Enable recovery" FORCE)
  
  add_subdirectory(secp256k1)
  
  set(SECP256K1_LIBRARIES secp256k1)
  set(SECP256K1_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/secp256k1/include)
endif()

target_link_libraries(atprotopds-cli PRIVATE ${SECP256K1_LIBRARIES})
```

## Testing

```objc
- (void)testSignAndVerify {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(keyPair);
    
    NSData *message = [@"Hello, AT Protocol!" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hash = [CID rawSha256:message];
    
    NSError *error = nil;
    NSData *signature = [keyPair signHash:hash error:&error];
    XCTAssertNotNil(signature);
    XCTAssertEqual(signature.length, 64);
    
    BOOL valid = [keyPair verifySignature:signature forHash:hash error:&error];
    XCTAssertTrue(valid);
}

- (void)testInvalidSignatureRejected {
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    NSData *hash = [CID rawSha256:[@"data" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *signature = [keyPair signHash:hash error:nil];
    
    // Tamper with signature
    NSMutableData *tampered = [signature mutableCopy];
    ((uint8_t *)tampered.mutableBytes)[0] ^= 0xFF;
    
    NSError *error = nil;
    BOOL valid = [keyPair verifySignature:tampered forHash:hash error:&error];
    XCTAssertFalse(valid);
}
```

---

## Common Mistakes

### Mistake 1: Signing Raw Data Instead of Hashes

❌ **What people do:**
```objc
// WRONG: Signing raw message
NSData *message = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
NSData *sig = [keyPair signData:message error:nil];  // Won't work!
```

**Why this fails:**
- secp256k1 ECDSA expects exactly 32 bytes
- Raw messages vary in length
- Hashing provides fixed-size, collision-resistant input

✅ **Correct approach:**
```objc
// RIGHT: Hash first, then sign
NSData *message = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
NSData *hash = [CID rawSha256:message];  // Always 32 bytes
NSData *sig = [keyPair signHash:hash error:nil];  // Works!
```

### Mistake 2: Using Uncompressed Keys in DIDs

❌ **What people do:**
```objc
// WRONG: Using 65-byte uncompressed key for DID
NSString *didKey = [NSString stringWithFormat:@"did:key:%@",
    [self base58Encode:keyPair.publicKey]];  // Too long!
```

**Why this fails:**
- `did:key` with secp256k1 uses compressed form (33 bytes)
- Uncompressed keys bloat URIs and aren't spec-compliant
- Interoperability issues with other AT Protocol implementations

✅ **Correct approach:**
```objc
// RIGHT: Use compressed public key
NSString *didKey = [NSString stringWithFormat:@"did:key:%@",
    [self base58Encode:keyPair.compressedPublicKey]];  // 33 bytes
```

### Mistake 3: Not Securing Private Keys

❌ **What people do:**
```objc
// WRONG: Logging private keys
NSLog(@"Generated key: %@", keyPair.privateKey);

// WRONG: Storing in plaintext
[[NSUserDefaults standardUserDefaults] setObject:keyPair.privateKey
                                          forKey:@"privateKey"];
```

**Why this fails:**
- Private keys in logs can leak to observability systems
- User defaults are readable by other processes
- Key compromise means identity theft

✅ **Correct approach:**
```objc
// RIGHT: Store in Keychain with appropriate access controls
SecAccessControlRef access = SecAccessControlCreateWithFlags(NULL,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    kSecAccessControlPrivateKeyUsage,
    NULL);

NSDictionary *query = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassKey,
    (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
    (__bridge id)kSecValueData: keyPair.privateKey,
    (__bridge id)kSecAttrAccessControl: (__bridge id)access
};
SecItemAdd((__bridge CFDictionaryRef)query, NULL);
```

---

## Exercises

📝 **Exercise 1: Verify Different Key's Signature**

Create a test that verifies a signature using a different public key fails:

```objc
- (void)testWrongKeyRejected {
    // Generate two key pairs
    // Sign with keyPair1
    // Verify with keyPair2's public key
    // Assert verification fails
}
```

- Hint: Both keys should successfully sign, but cross-verification must fail

<details>
<summary>Solution</summary>

```objc
- (void)testWrongKeyRejected {
    Secp256k1KeyPair *keyPair1 = [Secp256k1KeyPair generateKeyPair:nil];
    Secp256k1KeyPair *keyPair2 = [Secp256k1KeyPair generateKeyPair:nil];
    
    NSData *hash = [CID rawSha256:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *sig = [keyPair1 signHash:hash error:nil];
    
    // Verify with wrong key should fail
    BOOL valid = [[Secp256k1 shared] verifySignature:sig
                                             forHash:hash
                                       withPublicKey:keyPair2.publicKey
                                               error:nil];
    XCTAssertFalse(valid);
}
```

</details>

📝 **Exercise 2: Implement Key Pair from Seed**

Create a deterministic key generator from a seed phrase:

```objc
+ (nullable instancetype)keyPairFromSeed:(NSData *)seed error:(NSError **)error;
```

- Hint: Hash the seed to get 32 bytes, validate it's a valid private key scalar
- Challenge: Implement BIP-39 mnemonic (12/24 words) → seed

📝 **Exercise 3: Batch Signature Verification**

Implement efficient batch verification of multiple signatures:

```objc
- (NSArray<NSNumber *> *)verifyBatch:(NSArray<NSDictionary *> *)items;
// Each item: @{@"signature": NSData, @"hash": NSData, @"publicKey": NSData}
// Returns array of @YES/@NO for each item
```

- Consider: How can you fail fast on invalid inputs?
- Bonus: Could batch verification be parallelized?

---

## Summary

In this chapter, you learned:

- ✅ Why secp256k1 is used in AT Protocol
- ✅ Key sizes for private keys, public keys, and signatures
- ✅ Wrapping libsecp256k1 for Objective-C
- ✅ Key generation, signing, and verification
- ✅ Always sign hashes, not raw data

## Key Takeaways

1. **Always hash before signing** - ECDSA requires fixed 32-byte input.

2. **Use compressed public keys** - 33 bytes for `did:key`, not 65.

3. **Secure private keys properly** - Keychain, not UserDefaults or logs.

## Next Steps

In **Chapter 9**, we'll use these cryptographic primitives to implement **Decentralized Identifiers (DIDs)**—the foundation of AT Protocol identity.

---

**Files Referenced in This Chapter:**
- [Secp256k1.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/Secp256k1.h)
- [Secp256k1.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/Secp256k1.m)
- [secp256k1_wrapper_c.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Auth/secp256k1_wrapper_c.h)
