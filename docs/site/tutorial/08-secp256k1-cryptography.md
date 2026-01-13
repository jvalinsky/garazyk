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

<script setup>
const smartMock = `#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

// --- Helper: SHA256 ---
NSData *sha256(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    return [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];
}
NSString *hex(NSData *d) {
    const unsigned char *bytes = (const unsigned char *)d.bytes;
    NSMutableString *str = [NSMutableString stringWithCapacity:d.length * 2];
    for (int i=0; i<d.length; i++) [str appendFormat:@"%02x", bytes[i]];
    return str;
}

// --- Smart Mock Secp256k1 ---
// Uses symmetric crypto (Pub = Priv) for simplicity in demo
// Signature = SHA256(Priv + Hash)
@interface Secp256k1KeyPair : NSObject
@property (readonly) NSData *privateKey;
@property (readonly) NSData *publicKey;
@property (readonly) NSData *compressedPublicKey;
+ (instancetype)generateKeyPair:(NSError **)error;
+ (instancetype)keyPairWithPriv:(NSData *)p;
- (NSData *)signHash:(NSData *)hash error:(NSError **)error;
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h error:(NSError **)error;
// Helper for verification without key instance
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h withPublicKey:(NSData *)pub error:(NSError **)error;
@end

@implementation Secp256k1KeyPair
+ (instancetype)generateKeyPair:(NSError **)error {
    // Randomish seed based on time
    NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
    NSData *seed = [NSData dataWithBytes:&t length:sizeof(t)];
    return [self keyPairWithPriv:sha256(seed)];
}
+ (instancetype)keyPairWithPriv:(NSData *)p {
    Secp256k1KeyPair *k = [Secp256k1KeyPair new];
    k->_privateKey = p;
    k->_publicKey = p; // Symmetric Mock
    k->_compressedPublicKey = p;
    return k;
}
- (NSData *)signHash:(NSData *)hash error:(NSError **)error {
    NSMutableData *d = [NSMutableData dataWithData:self.privateKey];
    [d appendData:hash];
    return sha256(d);
}
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h error:(NSError **)error {
    return [self verifySignature:sig forHash:h withPublicKey:self.publicKey error:error];
}
- (BOOL)verifySignature:(NSData *)sig forHash:(NSData *)h withPublicKey:(NSData *)pub error:(NSError **)error {
    NSMutableData *d = [NSMutableData dataWithData:pub]; // Use pub key for verification
    [d appendData:h];
    NSData *computed = sha256(d);
    return [computed isEqualToData:sig];
}
@end
`;

const cryptoRunnerCode = smartMock + `
int main() {
    @autoreleasepool {
        printf("--- Crypto Demo (Smart Mock) ---\\n");
        
        Secp256k1KeyPair *k1 = [Secp256k1KeyPair generateKeyPair:nil];
        printf("Key 1 Pub: %s\\n", hex(k1.publicKey).UTF8String);
        
        NSData *msg = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *h = sha256(msg);
        
        NSData *sig = [k1 signHash:h error:nil];
        printf("Signature: %s\\n", hex(sig).UTF8String);
        
        BOOL v = [k1 verifySignature:sig forHash:h error:nil];
        printf("Verify K1: %s\\n", v ? "YES" : "NO");
    }
    return 0;
}`;

const exercise1Code = smartMock + `
// --- EXERCISE 1: Cross-Verification Failure ---

void testWrongKeyRejected() {
    // TODO: 
    // 1. Generate KeyPair 1 and KeyPair 2
    // 2. Sign a hash with KeyPair 1
    // 3. Try to verify signature using KeyPair 2's public key
    // 4. Print PASS if verification fails (returns NO)
    
    printf("Running testWrongKeyRejected...\\n");
    
    Secp256k1KeyPair *k1 = [Secp256k1KeyPair generateKeyPair:nil];
    Secp256k1KeyPair *k2 = [Secp256k1KeyPair generateKeyPair:nil];
    
    NSData *h = sha256([@"test" dataUsingEncoding:NSUTF8StringEncoding]);
    NSData *sig = [k1 signHash:h error:nil];
    
    // Verify with k2 (Mock: manually check logic)
    // Note: Our mock class instance method uses its own pub key.
    // To verify with k2 against k2's pub key (which would be invalid for k1's sig):
    BOOL valid = [k2 verifySignature:sig forHash:h error:nil];
    
    if (valid == NO) {
        printf("PASS: Signature from K1 rejected by K2.\\n");
    } else {
        printf("FAIL: K2 accepted K1's signature! (Collision?)\\n");
    }
}

int main() {
    @autoreleasepool {
        testWrongKeyRejected();
    }
    return 0;
}`;

const exercise2Code = smartMock + `
// --- EXERCISE 2: Deterministic Key Gen ---

@interface Secp256k1KeyPair (Seed)
+ (instancetype)keyPairFromSeed:(NSData *)seed;
@end

@implementation Secp256k1KeyPair (Seed)
+ (instancetype)keyPairFromSeed:(NSData *)seed {
    // TODO: Implement deterministic generation
    // Hint: Use sha256(seed) as the private key
    // Use [self keyPairWithPriv:...] from the mock
    
    return nil; // Replace this
}
@end

int main() {
    @autoreleasepool {
        NSData *seed = [@"my_secret_seed" dataUsingEncoding:NSUTF8StringEncoding];
        
        Secp256k1KeyPair *k1 = [Secp256k1KeyPair keyPairFromSeed:seed];
        if (!k1) { printf("Not implemented yet.\\n"); return 0; }
        
        Secp256k1KeyPair *k2 = [Secp256k1KeyPair keyPairFromSeed:seed];
        
        printf("K1 Pub: %s\\n", hex(k1.publicKey).UTF8String);
        printf("K2 Pub: %s\\n", hex(k2.publicKey).UTF8String);
        
        if ([k1.publicKey isEqualToData:k2.publicKey]) {
            printf("PASS: Keys are deterministic.\\n");
        } else {
            printf("FAIL: Keys differ for same seed.\\n");
        }
    }
    return 0;
}`;

const exercise3Code = smartMock + `
// --- EXERCISE 3: Batch Verification ---

// Item: @{@"sig": NSData, @"hash": NSData, @"pub": NSData}
NSArray<NSNumber *> * verifyBatch(NSArray<NSDictionary *> *items) {
    NSMutableArray *results = [NSMutableArray array];
    
    // TODO: Loop through items and verify each
    // Hint: Create temp key pair to reuse verify logic? 
    // Or add a static verify helper to the mock.
    // (Added verifySignature:forHash:withPublicKey: to mock for you)
    
    Secp256k1KeyPair *verifier = [Secp256k1KeyPair new];
    for (NSDictionary *item in items) {
        BOOL v = [verifier verifySignature:item[@"sig"] 
                                   forHash:item[@"hash"] 
                             withPublicKey:item[@"pub"] 
                                     error:nil];
        [results addObject:@(v)];
    }
    
    return results;
}

int main() {
    @autoreleasepool {
        // Setup Success Case
        Secp256k1KeyPair *k1 = [Secp256k1KeyPair generateKeyPair:nil];
        NSData *h1 = sha256([@"msg1" dataUsingEncoding:NSUTF8StringEncoding]);
        NSData *s1 = [k1 signHash:h1 error:nil];
        
        // Setup Fail Case (Wrong Key)
        Secp256k1KeyPair *k2 = [Secp256k1KeyPair generateKeyPair:nil];
        
        NSArray *batch = @[
            @{ @"sig": s1, @"hash": h1, @"pub": k1.publicKey }, // Valid
            @{ @"sig": s1, @"hash": h1, @"pub": k2.publicKey }  // Invalid
        ];
        
        NSArray *res = verifyBatch(batch);
        printf("Results: %s, %s\\n", 
               res[0].boolValue ? "YES" : "NO", 
               res[1].boolValue ? "YES" : "NO");
               
        if (res[0].boolValue && !res[1].boolValue) {
            printf("PASS: Batch verification correct.\\n");
        } else {
            printf("FAIL.\\n");
        }
    }
    return 0;
}`;
</script>


<ObjcRunner :initialCode="cryptoRunnerCode" />


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

<ObjcRunner :initialCode="exercise1Code" />



📝 **Exercise 2: Implement Key Pair from Seed**

Create a deterministic key generator from a seed phrase:

```objc
+ (nullable instancetype)keyPairFromSeed:(NSData *)seed error:(NSError **)error;
```

- Hint: Hash the seed to get 32 bytes
- Challenge: Ensure multiple calls with same seed return same key

<ObjcRunner :initialCode="exercise2Code" />

📝 **Exercise 3: Batch Signature Verification**

Implement efficient batch verification of multiple signatures:

```objc
- (NSArray<NSNumber *> *)verifyBatch:(NSArray<NSDictionary *> *)items;
```

- Consider: How can you fail fast on invalid inputs?

<ObjcRunner :initialCode="exercise3Code" />


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
