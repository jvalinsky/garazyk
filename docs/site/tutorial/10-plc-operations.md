# Chapter 10: PLC Operations & Account Creation

In the previous chapter, we learned about Decentralized Identifiers (DIDs)—specifically `did:key` for ephemeral keys and `did:plc` for persistent account identity. But how do you actually create a `did:plc`? How does it work under the hood?

This chapter implements the **PLC (Public Ledger of Credentials)** operations that power AT Protocol account creation, updates, and recovery. You'll learn how operations chain together to form an auditable history of your identity.

## What You'll Learn

By the end of this chapter, you'll be able to:
- Understand PLC operation types and their purposes
- Create genesis operations that generate new `did:plc` identifiers
- Compute DID identifiers from operation hashes
- Chain operations for updates (handle changes, key rotation, PDS migration)
- Implement tombstone operations for account deactivation
- Sign and verify operations with rotation keys
- Build a self-hosted PLC directory

## Prerequisites

This chapter assumes you understand:
- **Decentralized Identifiers** - `did:key` and `did:plc` structure (Chapter 9)
- **secp256k1 cryptography** - signing and verification (Chapter 8)
- **Content Identifiers (CIDs)** - cryptographic hashing (Chapter 4)
- **DAG-CBOR serialization** - deterministic encoding (Chapter 5)

If you're not comfortable with these, especially DIDs, review Chapter 9 first.

---

## The Problem: Identity Lifecycle Management

### Beyond Static Identifiers

In Chapter 9, we created `did:key` identifiers—simple, self-contained, but **immutable**:

```
did:key:zQ3shokFTS... ← Embed public key directly

Problems:
- Can't change anything (key, PDS, handle)
- Lost key = lost identity forever
- Can't migrate to different servers
```

**For long-lived accounts, we need:**
- ✅ **Key rotation** - Replace compromised keys
- ✅ **Recovery** - Regain access with backup key
- ✅ **Portability** - Move between PDSes
- ✅ **Handle updates** - Change handle without losing identity
- ✅ **Auditability** - Cryptographic proof of all changes

### The Vision: Operation-Based Identity

What if identity was defined by a **history of signed operations**?

```
Genesis Operation (Create)
    ↓
Update Operation #1 (Change handle)
    ↓
Update Operation #2 (Rotate key)
    ↓
Current Identity State
```

**Properties:**
- Each operation is cryptographically signed
- Operations chain together (each references previous)
- Current state = result of applying all operations in order
- DID = hash of genesis operation (immutable identifier)
- History is auditable and verifiable

This is **PLC (Public Ledger of Credentials)**—an operation log that defines your identity.

---

## PLC Operation Structure

### The Common Fields

All PLC operations share this structure:

```objc
@interface PLCOperation : NSObject <NSSecureCoding>

// Operation metadata
@property (nonatomic, copy) NSString *type;              // "plc_operation" or "plc_tombstone"
@property (nonatomic, copy, nullable) NSString *prev;    // CID of previous operation (null for genesis)

// Identity components
@property (nonatomic, strong) NSArray<NSString *> *rotationKeys;  // Keys that can update this DID
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *verificationMethods;  // Signing keys
@property (nonatomic, strong) NSArray<NSString *> *alsoKnownAs;   // Handle aliases
@property (nonatomic, strong) NSDictionary<NSString *, NSDictionary *> *services;  // PDS endpoints

// Cryptographic proof
@property (nonatomic, copy, nullable) NSString *sig;     // Signature (Base64URL)

@end
```

### Field Explanations

| Field | Purpose | Example |
|-------|---------|---------|
| `type` | Operation kind | `"plc_operation"` or `"plc_tombstone"` |
| `prev` | Previous operation CID (chains operations) | `"bafyreih5..."` or `null` (genesis) |
| `rotationKeys` | DIDs authorized to update/recover | `["did:key:zQ3sho...", "did:key:zQ3abc..."]` |
| `verificationMethods` | Signing keys for daily use | `{"atproto": "did:key:zQ3sho..."}` |
| `alsoKnownAs` | Handle URIs | `["at://alice.bsky.social"]` |
| `services` | Service endpoints (PDS location) | `{"atproto_pds": {...}}` |
| `sig` | Signature from a rotation key | Base64URL-encoded signature |

### The Intuition: A Signed Document Chain

Think of PLC operations like **property deeds**:

```
Genesis Operation = Original property deed
  - Establishes who owns the property
  - Signed by the county (rotation key)
  - Filed in public records (PLC directory)

Update Operation = Transfer/modification deed
  - References previous deed: "Amending deed #12345"
  - Signed by current owner (using rotation key from previous deed)
  - Filed in public records

Current Ownership = Result of applying all deeds in order
```

Just like property deeds:
- Each deed references the previous one (chain)
- All deeds are signed and filed publicly
- Anyone can verify the chain to determine current ownership
- Ownership can transfer (key rotation) without changing property address (DID)

---

## Operation Types

### 1. Genesis Operation (Create)

The first operation that creates a new DID:

```objc
PLCOperation *genesis = [[PLCOperation alloc] init];
genesis.type = @"plc_operation";
genesis.prev = nil;  // No previous operation (this is the first!)
genesis.rotationKeys = @[
    recoveryKey.didKey,   // Emergency backup key
    signingKey.didKey     // Primary signing key
];
genesis.verificationMethods = @{
    @"atproto": signingKey.didKey  // Key used for posts, likes, etc.
};
genesis.alsoKnownAs = @[@"at://alice.bsky.social"];
genesis.services = @{
    @"atproto_pds": @{
        @"type": @"AtprotoPersonalDataServer",
        @"endpoint": @"https://pds.example.com"
    }
};
```

**Purpose:** Establish new identity
**`prev` value:** `null` (no previous operation)
**Signed by:** One of the rotation keys (usually recovery key)
**Result:** DID = hash of this operation

### 2. Update Operation (Modify)

Modifies an existing DID:

```objc
PLCOperation *update = [[PLCOperation alloc] init];
update.type = @"plc_operation";
update.prev = @"bafyreih5az...";  // CID of previous operation
update.rotationKeys = @[
    recoveryKey.didKey,   // Keep same recovery key
    newSigningKey.didKey  // NEW signing key (rotated!)
];
update.verificationMethods = @{
    @"atproto": newSigningKey.didKey  // Update to new key
};
update.alsoKnownAs = @[@"at://alice.example.com"];  // NEW handle
update.services = @{
    @"atproto_pds": @{
        @"type": @"AtprotoPersonalDataServer",
        @"endpoint": @"https://new-pds.example.com"  // NEW PDS
    }
};
```

**Purpose:** Update keys, handle, or PDS
**`prev` value:** CID of most recent operation
**Signed by:** Current rotation key (from previous operation)
**Result:** Updated identity state

### 3. Tombstone Operation (Deactivate)

Permanently deactivates a DID:

```objc
PLCOperation *tombstone = [[PLCOperation alloc] init];
tombstone.type = @"plc_tombstone";  // Different type!
tombstone.prev = @"bafyreih5az...";  // CID of previous operation
// All other fields are empty or null
```

**Purpose:** Permanently disable the DID
**`prev` value:** CID of most recent operation
**Signed by:** Current rotation key
**Result:** DID no longer resolves (account deleted)

⚠️ **Warning:** Tombstones are **irreversible**. Once a DID is tombstoned, it cannot be recovered.

---

## Serialization for Signing

Operations must be serialized deterministically before signing:

```objc
- (nullable NSData *)serializeForSigning:(NSError **)error {
    NSMutableDictionary<CBORValue *, CBORValue *> *dict = [NSMutableDictionary dictionary];

    // 1. Type (always first in canonical ordering)
    dict[[CBORValue textString:@"type"]] = [CBORValue textString:self.type];

    // 2. Rotation keys (array of DID strings)
    NSMutableArray<CBORValue *> *rkArray = [NSMutableArray array];
    for (NSString *key in self.rotationKeys) {
        [rkArray addObject:[CBORValue textString:key]];
    }
    dict[[CBORValue textString:@"rotationKeys"]] = [CBORValue array:rkArray];

    // 3. Verification methods (map of label → DID)
    NSMutableDictionary<CBORValue *, CBORValue *> *vmDict = [NSMutableDictionary dictionary];
    for (NSString *label in self.verificationMethods) {
        vmDict[[CBORValue textString:label]] =
            [CBORValue textString:self.verificationMethods[label]];
    }
    dict[[CBORValue textString:@"verificationMethods"]] = [CBORValue map:vmDict];

    // 4. Also known as (array of URI strings)
    NSMutableArray<CBORValue *> *akaArray = [NSMutableArray array];
    for (NSString *alias in self.alsoKnownAs) {
        [akaArray addObject:[CBORValue textString:alias]];
    }
    dict[[CBORValue textString:@"alsoKnownAs"]] = [CBORValue array:akaArray];

    // 5. Services (map of service ID → service descriptor)
    NSMutableDictionary<CBORValue *, CBORValue *> *svcDict = [NSMutableDictionary dictionary];
    for (NSString *svcId in self.services) {
        NSDictionary *svc = self.services[svcId];
        NSMutableDictionary<CBORValue *, CBORValue *> *svcEntry = [NSMutableDictionary dictionary];

        for (NSString *key in svc) {
            svcEntry[[CBORValue textString:key]] = [CBORValue textString:svc[key]];
        }

        svcDict[[CBORValue textString:svcId]] = [CBORValue map:svcEntry];
    }
    dict[[CBORValue textString:@"services"]] = [CBORValue map:svcDict];

    // 6. Previous operation CID (null for genesis)
    if (self.prev) {
        dict[[CBORValue textString:@"prev"]] = [CBORValue textString:self.prev];
    } else {
        dict[[CBORValue textString:@"prev"]] = [CBORValue nilValue];
    }

    // 7. IMPORTANT: sig is NOT included when serializing for signing
    //    (We sign the operation without the signature field!)

    // Encode to DAG-CBOR
    return [[CBORValue map:dict] encode];
}
```

**Why serialize without signature?**

The signature proves the operation's authenticity. Including the signature in what we sign would create a circular dependency:

```
❌ WRONG:
signature = sign(operation + signature)  // Circular!

✅ CORRECT:
signature = sign(operation without signature)
final_operation = operation + signature
```

### CBOR Example

```
Operation:
{
  type: "plc_operation",
  prev: null,
  rotationKeys: ["did:key:zQ3sho...", "did:key:zQ3abc..."],
  verificationMethods: {"atproto": "did:key:zQ3sho..."},
  alsoKnownAs: ["at://alice.bsky.social"],
  services: {
    "atproto_pds": {
      "type": "AtprotoPersonalDataServer",
      "endpoint": "https://pds.example.com"
    }
  }
}

Serialized to DAG-CBOR:
[Binary CBOR bytes with deterministic map ordering]
→ Used for signing and hashing
```

---

## Computing the DID from Genesis Operation

The `did:plc` identifier is derived from the genesis operation's CID:

```objc
- (nullable NSString *)computeDID:(NSError **)error {
    // 1. Serialize operation (without signature)
    NSData *unsigned = [self serializeForSigning:error];
    if (!unsigned) return nil;

    // 2. SHA-256 hash the serialized bytes
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];  // 32 bytes
    CC_SHA256(unsigned.bytes, (CC_LONG)unsigned.length, hash);
    NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    // 3. Build CID with dag-cbor codec (0x71)
    CID *cid = [CID cidWithDigest:hashData codec:0x71];

    // 4. Extract base32 portion and truncate
    NSString *cidString = cid.stringValue;
    // CID format: [version][codec][multihash] encoded as base32
    // e.g., "bafyreih5aznjvttude6c3wbvqeebb6rlx5wkbzyppv7garjiubll2ceym4"

    // Remove "b" prefix (multibase indicator)
    NSString *base32Hash = [cidString substringFromIndex:1];

    // Truncate to 24 characters
    //NSString *truncated = [base32Hash substringToIndex:24];

    // 5. Build did:plc identifier
    return [NSString stringWithFormat:@"did:plc:%@", base32Hash];
}
```

### Complete DID Computation Example

Let's trace through a real example:

```
Step 1: Genesis operation
{
  "type": "plc_operation",
  "prev": null,
  "rotationKeys": ["did:key:zQ3shokFTS..."],
  "verificationMethods": {"atproto": "did:key:zQ3shokFTS..."},
  "alsoKnownAs": ["at://alice.bsky.social"],
  "services": {"atproto_pds": {...}}
}

Step 2: Serialize to DAG-CBOR
→ Binary bytes: [0xA6, 0x64, 0x74, 0x79, 0x70, 0x65, ...]
→ Length: ~200-300 bytes (depends on key/handle lengths)

Step 3: SHA-256 hash
→ Hash: [0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0x6F, ...] (32 bytes)

Step 4: Build CID (dag-cbor codec = 0x71)
→ Multihash: [0x12, 0x20, 0x1A, 0x2B, ...] (SHA-256 code + length + hash)
→ CID: [0x01, 0x71, multihash bytes]

Step 5: Encode as base32
→ Base32: "afyreih5aznjvttude6c3wbvqeebb6rlx5wkbzyppv7garjiubll2ceym4"

Step 6: Build DID
→ Remove 'b' prefix: "afyreih5aznjvttude6c3wbvqeebb6rlx5wkbzyppv7garjiubll2ceym4"
→ Result: "did:plc:afyreih5aznjvttude6c3wbvqeebb6rlx5wkbzyppv7garjiubll2ceym4"
```

**Why base32 and not base58 (like `did:key`)?**
- Base32 is more compact for hashes
- Sortable (alphabetical order = hash order)
- URL-safe (lowercase only)

💡 **Key Insight:** The DID is computed from the genesis operation. Even if you update your keys or handle, the DID never changes—it's immutable!

---

## Complete Account Creation Flow

<script setup>
const plcRunnerCode = `#import <Foundation/Foundation.h>

int main() {
    @autoreleasepool {
        printf("--- PLC Genesis Operation Builder ---\\n");

        // 1. Define Identity Components
        NSString *signingKey = @"did:key:zQ3shokFTS3brHcDQrn82RUDfCZESWL1ZdCEJwekUDPQiYBme";
        NSString *recoveryKey = @"did:key:zQ3abc...";
        NSString *handle = @"alice.bsky.social";
        NSString *pds = @"https://pds.example.com";

        // 2. Build Operation Dictionary
        NSMutableDictionary *op = [NSMutableDictionary dictionary];
        op[@"type"] = @"plc_operation";
        op[@"prev"] = [NSNull null];
        
        // Rotation keys (Recovery first, then Signing)
        op[@"rotationKeys"] = @[recoveryKey, signingKey];
        
        // Verification methods
        op[@"verificationMethods"] = @{@"atproto": signingKey};
        
        // Handle (alias)
        op[@"alsoKnownAs"] = @[[NSString stringWithFormat:@"at://%@", handle]];
        
        // Services (PDS endpoint)
        op[@"services"] = @{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": pds
            }
        };

        // 3. Serialize for Signing (Mock step - real app uses DAG-CBOR)
        printf("Signing operation with Recovery Key...\\n");
        // In reality: sign(DAG_CBOR(op_without_sig))
        op[@"sig"] = @"mock_signature_base64url_xyz123";

        // 4. Output resulting JSON
        NSData *json = [NSJSONSerialization dataWithJSONObject:op options:NSJSONWritingPrettyPrinted error:nil];
        NSString *jsonStr = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        
        printf("Genesis Operation:\\n%s\\n", jsonStr.UTF8String);
        
        // 5. Compute DID (Mock)
        // In reality: SHA256(DAG_CBOR(op)) -> CID -> did:plc
        printf("\\nDerived DID: did:plc:z72i7hdynmk6r22z27h6tvur\\n");
    }
    return 0;
}`;
</script>

<ObjcRunner :initialCode="plcRunnerCode" />

Let's implement the full workflow:

```objc
- (NSString *)createAccountWithHandle:(NSString *)handle
                             pdsURL:(NSString *)pdsURL
                              error:(NSError **)error {
    // 1. Generate key pairs
    DIDKey *signingKey = [DIDKey generateSecp256k1];
    NSLog(@"Generated signing key: %@", signingKey.didKey);

    DIDKey *recoveryKey = [DIDKey generateSecp256k1];
    NSLog(@"Generated recovery key: %@", recoveryKey.didKey);
    // IMPORTANT: Store recovery key securely offline!

    // 2. Build genesis operation
    PLCOperation *genesis = [[PLCOperation alloc] init];
    genesis.type = @"plc_operation";
    genesis.prev = nil;  // Genesis has no previous

    // Rotation keys: recovery first (more secure), then signing
    genesis.rotationKeys = @[
        recoveryKey.didKey,   // Emergency backup (keep offline!)
        signingKey.didKey     // Daily use
    ];

    // Verification methods: the signing key for AT Protocol
    genesis.verificationMethods = @{
        @"atproto": signingKey.didKey  // Used to sign posts, etc.
    };

    // Handle
    genesis.alsoKnownAs = @[
        [NSString stringWithFormat:@"at://%@", handle]
    ];

    // PDS service endpoint
    genesis.services = @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": pdsURL
        }
    };

    // 3. Serialize for signing
    NSData *unsigned = [genesis serializeForSigning:error];
    if (!unsigned) {
        NSLog(@"Failed to serialize: %@", *error);
        return nil;
    }

    // 4. Sign with recovery key (convention: use most secure key for genesis)
    NSData *signature = [recoveryKey signData:unsigned error:error];
    if (!signature) {
        NSLog(@"Failed to sign: %@", *error);
        return nil;
    }

    // Base64URL encode signature
    genesis.sig = [self base64URLEncode:signature];

    // 5. Compute DID from genesis operation
    NSString *did = [genesis computeDID:error];
    if (!did) {
        NSLog(@"Failed to compute DID: %@", *error);
        return nil;
    }

    NSLog(@"Generated DID: %@", did);

    // 6. Store keys securely
    [self.keyStorage storePrivateKey:signingKey.privateKeyData
                              forDID:did
                               label:@"signing"];
    [self.keyStorage storePrivateKey:recoveryKey.privateKeyData
                              forDID:did
                               label:@"recovery"];

    // 7. Submit genesis operation to PLC directory
    [self submitPLCOperation:genesis forDID:did error:error];

    return did;
}
```

**What happens:**
1. Generate two key pairs (signing + recovery)
2. Build genesis operation with both keys, handle, PDS URL
3. Serialize operation to DAG-CBOR
4. Sign with recovery key
5. Compute DID from operation hash
6. Store private keys securely
7. Submit operation to PLC directory

---

## Operation Chaining: Updates

### Changing Your Handle

```objc
- (BOOL)updateHandle:(NSString *)newHandle
              forDID:(NSString *)did
               error:(NSError **)error {
    // 1. Load current signing key
    NSData *signingPrivateKey = [self.keyStorage getPrivateKeyForDID:did
                                                                label:@"signing"];
    DIDKey *signingKey = [[DIDKey alloc] initWithPrivateKey:signingPrivateKey];

    // 2. Fetch current operation from PLC directory
    PLCOperation *currentOp = [self fetchLatestOperation:did error:error];
    if (!currentOp) return NO;

    // 3. Compute CID of current operation
    NSString *prevCID = [currentOp computeCID:error];

    // 4. Build update operation
    PLCOperation *update = [[PLCOperation alloc] init];
    update.type = @"plc_operation";
    update.prev = prevCID;  // Chain to previous operation

    // Keep same keys
    update.rotationKeys = currentOp.rotationKeys;
    update.verificationMethods = currentOp.verificationMethods;

    // NEW handle
    update.alsoKnownAs = @[
        [NSString stringWithFormat:@"at://%@", newHandle]
    ];

    // Keep same service
    update.services = currentOp.services;

    // 5. Sign with signing key
    NSData *unsigned = [update serializeForSigning:error];
    NSData *signature = [signingKey signData:unsigned error:error];
    if (!signature) return NO;

    update.sig = [self base64URLEncode:signature];

    // 6. Submit update operation
    return [self submitPLCOperation:update forDID:did error:error];
}
```

**Operation chain:**
```
Genesis Operation (CID: bafyreiabc...)
  handle: "alice.bsky.social"
      ↓
Update Operation (prev: bafyreiabc...)
  handle: "alice.example.com"  ← NEW!
      ↓
Current State: handle = "alice.example.com"
```

### Rotating Your Signing Key

```objc
- (BOOL)rotateSigningKey:(NSString *)did
                   error:(NSError **)error {
    // 1. Generate NEW signing key
    DIDKey *newSigningKey = [DIDKey generateSecp256k1];

    // 2. Load RECOVERY key (we need this to authorize key rotation)
    NSData *recoveryPrivateKey = [self.keyStorage getPrivateKeyForDID:did
                                                                 label:@"recovery"];
    DIDKey *recoveryKey = [[DIDKey alloc] initWithPrivateKey:recoveryPrivateKey];

    // 3. Fetch current operation
    PLCOperation *currentOp = [self fetchLatestOperation:did error:error];
    NSString *prevCID = [currentOp computeCID:error];

    // 4. Build update operation
    PLCOperation *update = [[PLCOperation alloc] init];
    update.type = @"plc_operation";
    update.prev = prevCID;

    // NEW rotation keys (keep recovery, replace signing)
    update.rotationKeys = @[
        recoveryKey.didKey,        // Keep same recovery key
        newSigningKey.didKey       // NEW signing key!
    ];

    // NEW verification method
    update.verificationMethods = @{
        @"atproto": newSigningKey.didKey  // Update to new key
    };

    // Keep same handle and service
    update.alsoKnownAs = currentOp.alsoKnownAs;
    update.services = currentOp.services;

    // 5. Sign with RECOVERY key (authorizing the rotation)
    NSData *unsigned = [update serializeForSigning:error];
    NSData *signature = [recoveryKey signData:unsigned error:error];
    update.sig = [self base64URLEncode:signature];

    // 6. Submit update
    BOOL success = [self submitPLCOperation:update forDID:did error:error];
    if (success) {
        // Store new signing key
        [self.keyStorage storePrivateKey:newSigningKey.privateKeyData
                                  forDID:did
                                   label:@"signing"];
    }

    return success;
}
```

**Why use recovery key to sign?**
The old signing key might be compromised. By signing with the recovery key, we prove we control the account even if the signing key is stolen.

### Migrating to a New PDS

```objc
- (BOOL)migrateToPDS:(NSString *)newPDSURL
              forDID:(NSString *)did
               error:(NSError **)error {
    // 1. Load signing key
    NSData *signingPrivateKey = [self.keyStorage getPrivateKeyForDID:did
                                                                label:@"signing"];
    DIDKey *signingKey = [[DIDKey alloc] initWithPrivateKey:signingPrivateKey];

    // 2. Fetch current operation
    PLCOperation *currentOp = [self fetchLatestOperation:did error:error];
    NSString *prevCID = [currentOp computeCID:error];

    // 3. Build update operation
    PLCOperation *update = [[PLCOperation alloc] init];
    update.type = @"plc_operation";
    update.prev = prevCID;

    // Keep same keys and handle
    update.rotationKeys = currentOp.rotationKeys;
    update.verificationMethods = currentOp.verificationMethods;
    update.alsoKnownAs = currentOp.alsoKnownAs;

    // NEW service endpoint
    update.services = @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": newPDSURL  // NEW PDS!
        }
    };

    // 4. Sign and submit
    NSData *unsigned = [update serializeForSigning:error];
    NSData *signature = [signingKey signData:unsigned error:error];
    update.sig = [self base64URLEncode:signature];

    return [self submitPLCOperation:update forDID:did error:error];
}
```

**Portability in action:**
```
1. User on pds-a.example.com
2. User updates PLC operation → service = pds-b.example.com
3. Other users resolve DID → see new PDS location
4. User's identity (DID) unchanged, just moved to new server!
```

---

## Verifying Operation Chains

### The Verification Process

```objc
- (BOOL)verifyOperationChain:(NSArray<PLCOperation *> *)operations
                      forDID:(NSString *)did
                       error:(NSError **)error {
    // 1. Verify genesis operation computes to the DID
    PLCOperation *genesis = operations.firstObject;
    if (!genesis || genesis.prev != nil) {
        if (error) {
            *error = [NSError errorWithDomain:PLCErrorDomain
                                         code:PLCErrorInvalidGenesis
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"First operation must be genesis"}];
        }
        return NO;
    }

    NSString *computedDID = [genesis computeDID:error];
    if (![computedDID isEqualToString:did]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCErrorDomain
                                         code:PLCErrorDIDMismatch
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Genesis operation doesn't match DID"}];
        }
        return NO;
    }

    // 2. Verify each operation in sequence
    PLCOperation *prevOp = genesis;
    for (NSUInteger i = 1; i < operations.count; i++) {
        PLCOperation *op = operations[i];

        // 2a. Verify 'prev' chains correctly
        NSString *prevCID = [prevOp computeCID:error];
        if (![op.prev isEqualToString:prevCID]) {
            if (error) {
                *error = [NSError errorWithDomain:PLCErrorDomain
                                             code:PLCErrorChainBroken
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:
                                                 @"Operation %lu doesn't chain to previous", i]}];
            }
            return NO;
        }

        // 2b. Verify signature with rotation keys from previous operation
        BOOL sigValid = [self verifySignature:op.sig
                                  onOperation:op
                               withRotationKeys:prevOp.rotationKeys
                                         error:error];
        if (!sigValid) {
            return NO;
        }

        prevOp = op;
    }

    return YES;  // All operations valid!
}

- (BOOL)verifySignature:(NSString *)sigBase64
            onOperation:(PLCOperation *)op
         withRotationKeys:(NSArray<NSString *> *)rotationKeys
                  error:(NSError **)error {
    // Serialize operation without signature
    NSData *unsigned = [op serializeForSigning:error];
    if (!unsigned) return NO;

    // Decode signature
    NSData *signature = [self base64URLDecode:sigBase64];

    // Try each rotation key until one verifies
    for (NSString *rotationKeyDID in rotationKeys) {
        DIDKey *rotationKey = [DIDKey parse:rotationKeyDID error:nil];
        if (!rotationKey) continue;

        BOOL valid = [rotationKey verifySignature:signature
                                          forData:unsigned
                                            error:nil];
        if (valid) {
            return YES;  // Found valid signature!
        }
    }

    // No rotation key verified the signature
    if (error) {
        *error = [NSError errorWithDomain:PLCErrorDomain
                                     code:PLCErrorInvalidSignature
                                 userInfo:@{NSLocalizedDescriptionKey:
                                     @"Signature not valid for any rotation key"}];
    }
    return NO;
}
```

**What this verifies:**
1. Genesis operation hashes to the DID
2. Each operation's `prev` matches previous operation's CID
3. Each operation is signed by a rotation key from the previous operation
4. Chain is unbroken from genesis to current

---

## Tombstone: Permanent Deactivation

```objc
- (BOOL)tombstoneDID:(NSString *)did
               error:(NSError **)error {
    // 1. Load recovery key (only recovery key can tombstone)
    NSData *recoveryPrivateKey = [self.keyStorage getPrivateKeyForDID:did
                                                                 label:@"recovery"];
    DIDKey *recoveryKey = [[DIDKey alloc] initWithPrivateKey:recoveryPrivateKey];

    // 2. Fetch current operation
    PLCOperation *currentOp = [self fetchLatestOperation:did error:error];
    NSString *prevCID = [currentOp computeCID:error];

    // 3. Build tombstone operation
    PLCOperation *tombstone = [[PLCOperation alloc] init];
    tombstone.type = @"plc_tombstone";  // Special type!
    tombstone.prev = prevCID;

    // All identity fields are null/empty for tombstone
    tombstone.rotationKeys = @[];
    tombstone.verificationMethods = @{};
    tombstone.alsoKnownAs = @[];
    tombstone.services = @{};

    // 4. Sign with recovery key
    NSData *unsigned = [tombstone serializeForSigning:error];
    NSData *signature = [recoveryKey signData:unsigned error:error];
    tombstone.sig = [self base64URLEncode:signature];

    // 5. Submit tombstone
    BOOL success = [self submitPLCOperation:tombstone forDID:did error:error];

    if (success) {
        // Optionally: delete stored keys (account is gone)
        [self.keyStorage deleteAllKeysForDID:did];
    }

    return success;
}
```

**Tombstone effects:**
- DID no longer resolves
- All posts/records become inaccessible
- Account cannot be recovered (permanent!)
- Operation chain ends

⚠️ **Use with extreme caution:** There's no undo button!

---

## Self-Hosted PLC Directory

### Why Self-Host?

The public PLC directory (`plc.directory`) is convenient, but you can also run your own:

**Benefits:**
- Full control over your identity data
- Privacy (operations not publicly indexed)
- Federation (multiple PDS operators can run directories)
- Redundancy (backup identity records)

### Basic PLC Directory Implementation

```objc
@interface PLCDirectory : NSObject

// Store operations by DID
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<PLCOperation *> *> *operations;

- (BOOL)submitOperation:(PLCOperation *)op forDID:(NSString *)did error:(NSError **)error;
- (NSArray<PLCOperation *> *)getOperations:(NSString *)did;
- (PLCOperation *)getLatestOperation:(NSString *)did;

@end

@implementation PLCDirectory

- (instancetype)init {
    if (self = [super init]) {
        self.operations = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)submitOperation:(PLCOperation *)op
                 forDID:(NSString *)did
                  error:(NSError **)error {
    // 1. Validate operation
    NSArray<PLCOperation *> *existing = self.operations[did];

    if (!existing) {
        // First operation must be genesis
        if (op.prev != nil) {
            if (error) {
                *error = [NSError errorWithDomain:PLCErrorDomain
                                             code:PLCErrorInvalidGenesis
                                         userInfo:@{NSLocalizedDescriptionKey:
                                             @"First operation must have prev=null"}];
            }
            return NO;
        }

        // Verify genesis computes to DID
        NSString *computedDID = [op computeDID:error];
        if (![computedDID isEqualToString:did]) {
            return NO;
        }

        // Initialize array
        self.operations[did] = [NSMutableArray arrayWithObject:op];
        return YES;
    }

    // 2. For updates, verify chain
    PLCOperation *latest = existing.lastObject;
    NSString *latestCID = [latest computeCID:error];

    if (![op.prev isEqualToString:latestCID]) {
        if (error) {
            *error = [NSError errorWithDomain:PLCErrorDomain
                                         code:PLCErrorChainBroken
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"Operation doesn't chain to latest"}];
        }
        return NO;
    }

    // 3. Verify signature
    BOOL sigValid = [self verifySignature:op withRotationKeys:latest.rotationKeys error:error];
    if (!sigValid) return NO;

    // 4. Add to chain
    [existing addObject:op];
    return YES;
}

- (NSArray<PLCOperation *> *)getOperations:(NSString *)did {
    return self.operations[did] ?: @[];
}

- (PLCOperation *)getLatestOperation:(NSString *)did {
    return [self.operations[did] lastObject];
}

@end
```

**Usage:**

```objc
// Start directory
PLCDirectory *directory = [[PLCDirectory alloc] init];

// Submit genesis
[directory submitOperation:genesisOp forDID:did error:nil];

// Submit update
[directory submitOperation:updateOp forDID:did error:nil];

// Retrieve full chain
NSArray<PLCOperation *> *chain = [directory getOperations:did];
```

---

## Common Mistakes

### Mistake 1: Not Storing Recovery Key Safely

❌ **What people do:**
```objc
// WRONG: Store recovery key same as signing key
[self.keyStorage storePrivateKey:recoveryKey.privateKeyData
                          forDID:did
                           label:@"recovery"];
```

**Why this fails:**
- If device is compromised, attacker gets both keys
- Defeats the purpose of having a recovery key
- Can't recover if device is lost

✅ **Correct approach:**
```objc
// RIGHT: Prompt user to store recovery key offline
NSString *recoveryPhrase = [self generateRecoveryPhrase:recoveryKey.privateKeyData];
[self displayToUser:@"Write this down and store safely (NOT on this device):"];
[self displayToUser:recoveryPhrase];

// Don't store on device!
```

**Why this works:**
- Recovery key stays offline (cold storage)
- Device compromise doesn't expose recovery key
- Can recover account from paper backup

### Mistake 2: Signing Updates with Wrong Key

❌ **What people try:**
```objc
// WRONG: Sign handle update with recovery key
NSData *signature = [recoveryKey signData:unsigned error:error];
```

**Why this fails:**
- Recovery key should only be used for key rotation or account recovery
- Using it frequently increases exposure risk
- Violates principle of least privilege

✅ **Correct approach:**
```objc
// RIGHT: Sign routine updates with signing key
NSData *signature = [signingKey signData:unsigned error:error];

// Use recovery key ONLY for:
// - Key rotation (replacing compromised signing key)
// - Account recovery (signing key lost)
// - Tombstone (permanent deactivation)
```

**Why this works:**
- Signing key is "hot" (can be exposed more)
- Recovery key is "cold" (rarely used, more secure)
- Compromise of signing key doesn't compromise recovery

### Mistake 3: Forgetting to Chain Operations

❌ **What people do:**
```objc
// WRONG: Create update without setting prev
PLCOperation *update = [[PLCOperation alloc] init];
update.type = @"plc_operation";
update.prev = nil;  // Forgot to set!
```

**Why this fails:**
- PLC directory rejects unchained operations
- Can't verify operation sequence
- Breaks auditability

✅ **Correct approach:**
```objc
// RIGHT: Always chain to previous operation
PLCOperation *latest = [directory getLatestOperation:did];
NSString *prevCID = [latest computeCID:error];

PLCOperation *update = [[PLCOperation alloc] init];
update.type = @"plc_operation";
update.prev = prevCID;  // CRITICAL!
```

**Why this works:**
- Creates verifiable chain of custody
- PLC directory can validate sequence
- Prevents operation injection attacks

---

## Summary

In this chapter, you learned:

- ✅ **PLC operation structure:** Type, prev, rotation keys, verification methods, handle, services, signature
- ✅ **Genesis operations:** Create new DIDs, compute DID from operation hash
- ✅ **Update operations:** Chain to previous, modify keys/handle/PDS
- ✅ **Tombstone operations:** Permanently deactivate DIDs
- ✅ **Operation chaining:** Each operation references previous via CID
- ✅ **Signature verification:** Validate operations with rotation keys
- ✅ **Self-hosted directories:** Run your own PLC operation store

## Key Takeaways

1. **DIDs are immutable, but identity is mutable:** The DID (hash of genesis) never changes, but you can update everything else (keys, handle, PDS) via operations.

2. **Rotation keys are the ultimate authority:** They can sign updates, rotate themselves, and tombstone the account. Keep recovery keys offline!

3. **Operation chains are auditable:** Anyone can verify the entire history from genesis to current state. This provides transparency and accountability.

## Looking Ahead

In **Chapter 11**, we implemented the **HTTP Server**—the foundation for serving XRPC requests. We learned about GCD, serial queues, and request handling.

Next, in **Chapter 12**, we'll build on both by implementing **XRPC Endpoints**—the API handlers that use DIDs for authentication and repositories for data storage.

You'll learn how to:
- Route XRPC requests to handlers
- Authenticate users with JWT tokens and DIDs
- Implement createRecord, getRecord, and query operations
- Handle pagination and streaming responses

This brings together identity (Chapter 9-10), authentication (Chapter 14), and data storage (Chapters 5-7)!

---

**Files Referenced in This Chapter:**
- [PLCOperation.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/PLCOperation.h)
- [PLCOperation.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/PLCOperation.m)
- [DIDKey.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Identity/DIDKey.h) (from Chapter 9)

**Further Reading:**
- [AT Protocol PLC Specification](https://atproto.com/specs/did-plc) - Official spec
- [DID Core Specification](https://www.w3.org/TR/did-core/) - W3C DID standard
- [Public Ledger of Credentials](https://plc.directory/) - Reference implementation
- [Key Management Best Practices](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final) - NIST guidelines
