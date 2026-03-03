# DID Document Updates

This guide explains how DID documents are updated in the PLC directory, including the operation workflow, verification process, and propagation mechanisms.

## Overview

DID documents in the PLC (Public Ledger of Credentials) directory are updated through a chain of cryptographically signed operations. Each operation references the previous operation, forming an immutable audit log that can be replayed to compute the current DID state.

## Operation Chain Structure

### Hash-Linked Chain

PLC operations form a hash-linked chain similar to a blockchain:

```
Genesis Operation (prev: null)
    ↓ (CID: bafyreiabc...)
Update Operation #1 (prev: bafyreiabc...)
    ↓ (CID: bafyreidef...)
Update Operation #2 (prev: bafyreidef...)
    ↓ (CID: bafyreighi...)
Current State
```

Each operation contains:
- `did`: The DID this operation belongs to
- `prev`: CID of the previous operation (null for genesis)
- `sig`: Base64-encoded signature of the operation hash
- `data`: Operation payload (rotation keys, services, etc.)
- `type`: Operation type (`plc_operation`)

### Operation Structure

```objective-c
@interface PLCOperation : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy, nullable) NSString *prev;
@property (nonatomic, copy) NSString *sig;
@property (nonatomic, copy) NSDictionary *data;
@property (nonatomic, copy, nullable) NSString *cid;
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, assign) BOOL nullified;

@end
```

## DID Creation (Genesis Operation)

### Step 1: Generate Keys

```objective-c
#import "Auth/Secp256k1.h"

// Generate secp256k1 key pair for signing
Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
NSString *didKey = [keyPair didKeyString];
// Example: "did:key:zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX"
```

### Step 2: Create Genesis Operation Data

```objective-c
NSDictionary *createData = @{
    @"type": @"plc_operation",
    @"rotationKeys": @[didKey],                    // Keys that can sign updates
    @"verificationMethods": @{
        @"atproto": didKey                         // Key for AT Protocol operations
    },
    @"alsoKnownAs": @[@"at://alice.bsky.social"], // Handle
    @"services": @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": @"https://pds.example.com"
        }
    },
    @"prev": [NSNull null]                         // Genesis has no previous operation
};
```

### Step 3: Calculate DID

The DID is deterministically derived from the genesis operation data:

```objective-c
NSString *did = [PLCOperation calculateDIDForData:createData];
// Example: "did:plc:z72i7hdynmk6r22z27h6tvur"
```

**DID Calculation Process**:
1. Encode operation data as DAG-CBOR
2. Compute SHA-256 hash of CBOR bytes
3. Encode hash as base32
4. Take first 24 characters
5. Prepend `did:plc:` prefix

### Step 4: Sign Operation

```objective-c
#import "Core/ATProtoCBORSerialization.h"
#import "Auth/CryptoUtils.h"

// Encode operation as CBOR
NSError *error = nil;
NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:createData error:&error];

// Hash the CBOR bytes
NSData *hash = [CryptoUtils sha256:cbor];

// Sign the hash
NSData *signature = [keyPair signHash:hash error:&error];

// Encode signature as base64
NSString *sigBase64 = [signature base64EncodedStringWithOptions:0];
```

### Step 5: Create Operation Object

```objective-c
PLCOperation *createOp = [[PLCOperation alloc] init];
createOp.did = did;
createOp.prev = nil;
createOp.sig = sigBase64;
createOp.data = createData;
```

### Step 6: Submit to PLC Server

```objective-c
DIDPLCResolver *resolver = [[DIDPLCResolver alloc] 
    initWithPlcUrl:@"https://plc.directory"];

NSInteger statusCode = 0;
NSData *response = [resolver submitOperation:[createOp toDictionary]
                                         did:did
                                  statusCode:&statusCode
                                       error:&error];

if (statusCode == 200) {
    NSLog(@"DID created successfully: %@", did);
} else {
    NSLog(@"Failed to create DID: %ld", (long)statusCode);
}
```

## Updating DID Documents

### Common Update Scenarios

#### 1. Update Handle

```objective-c
// Fetch current DID document to get latest state
NSDictionary *currentDoc = [resolver resolveDID:did error:&error];

// Get audit log to find latest operation CID
NSArray *auditLog = [resolver resolveAuditLogForDID:did error:&error];
PLCOperation *latestOp = [PLCOperation operationFromDictionary:auditLog.lastObject 
                                                         error:&error];
NSString *prevCid = latestOp.cid;

// Create update operation
NSDictionary *updateData = @{
    @"type": @"plc_operation",
    @"rotationKeys": currentDoc[@"rotationKeys"],
    @"verificationMethods": currentDoc[@"verificationMethods"],
    @"alsoKnownAs": @[@"at://alice-new.bsky.social"],  // New handle
    @"services": currentDoc[@"services"],
    @"prev": prevCid
};

// Sign and submit (same process as genesis)
NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:updateData error:&error];
NSData *hash = [CryptoUtils sha256:cbor];
NSData *signature = [keyPair signHash:hash error:&error];

PLCOperation *updateOp = [[PLCOperation alloc] init];
updateOp.did = did;
updateOp.prev = prevCid;
updateOp.sig = [signature base64EncodedStringWithOptions:0];
updateOp.data = updateData;

[resolver submitOperation:[updateOp toDictionary]
                      did:did
               statusCode:&statusCode
                    error:&error];
```

#### 2. Update PDS Endpoint

```objective-c
NSDictionary *updateData = @{
    @"type": @"plc_operation",
    @"rotationKeys": currentDoc[@"rotationKeys"],
    @"verificationMethods": currentDoc[@"verificationMethods"],
    @"alsoKnownAs": currentDoc[@"alsoKnownAs"],
    @"services": @{
        @"atproto_pds": @{
            @"type": @"AtprotoPersonalDataServer",
            @"endpoint": @"https://new-pds.example.com"  // New PDS
        }
    },
    @"prev": prevCid
};
```

#### 3. Rotate Keys

```objective-c
// Generate new key pair
Secp256k1KeyPair *newKeyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
NSString *newDidKey = [newKeyPair didKeyString];

NSDictionary *updateData = @{
    @"type": @"plc_operation",
    @"rotationKeys": @[newDidKey],                     // New rotation key
    @"verificationMethods": @{
        @"atproto": newDidKey                          // New verification key
    },
    @"alsoKnownAs": currentDoc[@"alsoKnownAs"],
    @"services": currentDoc[@"services"],
    @"prev": prevCid
};

// IMPORTANT: Sign with OLD key (the one in current rotationKeys)
// The new key becomes active only after this operation is accepted
NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:updateData error:&error];
NSData *hash = [CryptoUtils sha256:cbor];
NSData *signature = [oldKeyPair signHash:hash error:&error];  // Use OLD key
```

## State Replay and Verification

### Computing Current State

The PLC server and clients compute the current DID state by replaying the operation history:

```objective-c
@interface PLCStateReplayer : NSObject

+ (nullable PLCDIDState *)replayHistory:(NSArray<PLCOperation *> *)history 
                                  error:(NSError **)error;

@end
```

### Replay Process

```objective-c
// Fetch complete audit log
NSArray *auditLog = [resolver resolveAuditLogForDID:did error:&error];

// Parse operations
NSMutableArray *operations = [NSMutableArray array];
for (NSDictionary *entry in auditLog) {
    PLCOperation *op = [PLCOperation operationFromDictionary:entry error:&error];
    if (op) [operations addObject:op];
}

// Replay to compute current state
PLCDIDState *state = [PLCStateReplayer replayHistory:operations error:&error];

// Convert to DID document
NSDictionary *didDocument = [state toDIDDocument];
```

### Verification Steps

During replay, the system verifies:

1. **Chain Integrity**: Each operation's `prev` field matches the CID of the previous operation
2. **Signature Validity**: Each operation is signed by a key in the previous state's `rotationKeys`
3. **Format Validation**: All fields conform to PLC specification
4. **Size Limits**: CBOR encoding does not exceed 7500 bytes

```objective-c
// Verify operation chain
for (NSInteger i = 1; i < operations.count; i++) {
    PLCOperation *current = operations[i];
    PLCOperation *previous = operations[i - 1];
    
    // Verify prev link
    NSString *expectedPrev = [PLCOperation calculateCIDForOperation:[previous toDictionary] 
                                                              error:&error];
    if (![current.prev isEqualToString:expectedPrev]) {
        NSLog(@"Chain integrity violation at operation %ld", (long)i);
        return nil;
    }
    
    // Verify signature (simplified - actual implementation more complex)
    NSData *cbor = [ATProtoCBORSerialization encodeDataWithJSONObject:current.data 
                                                                error:&error];
    NSData *hash = [CryptoUtils sha256:cbor];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:current.sig 
                                                            options:0];
    
    // Extract public key from previous state's rotationKeys
    // Verify signature with that key
    // (Implementation details omitted for brevity)
}
```

## DID Document Format

### Computed DID Document

After replaying operations, the resulting DID document follows the W3C DID Core specification:

```json
{
  "@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/multikey/v1",
    "https://w3id.org/security/suites/secp256k1-2019/v1"
  ],
  "id": "did:plc:z72i7hdynmk6r22z27h6tvur",
  "alsoKnownAs": [
    "at://alice.bsky.social"
  ],
  "verificationMethod": [
    {
      "id": "did:plc:z72i7hdynmk6r22z27h6tvur#atproto",
      "type": "Multikey",
      "controller": "did:plc:z72i7hdynmk6r22z27h6tvur",
      "publicKeyMultibase": "zDnaeRSYs7c2NpcNA5NRAUqS8DCkLWDyNLnATi28D6w7no7hX"
    }
  ],
  "service": [
    {
      "id": "#atproto_pds",
      "type": "AtprotoPersonalDataServer",
      "serviceEndpoint": "https://pds.example.com"
    }
  ]
}
```

### DID State Object

```objective-c
@interface PLCDIDState : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, strong) NSArray<NSString *> *rotationKeys;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *verificationMethods;
@property (nonatomic, strong) NSArray<NSString *> *alsoKnownAs;
@property (nonatomic, strong) NSDictionary *services;
@property (nonatomic, assign) BOOL tombstoned;

- (NSDictionary *)toDIDDocument;

@end
```

## Propagation and Caching

### PLC Server Propagation

When an operation is submitted to the PLC server:

1. **Validation**: Server validates signature, chain integrity, and format
2. **Storage**: Operation is appended to the DID's audit log
3. **Indexing**: Current state is recomputed and indexed
4. **Response**: Server returns 200 OK with operation CID

### Client-Side Caching

September's `DIDPLCResolver` caches resolved DID documents:

```objective-c
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *cache;

- (NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error {
    // Check cache first
    NSDictionary *cached = [self.cache objectForKey:did];
    if (cached) return cached;
    
    // Fetch from PLC server
    NSDictionary *doc = [self fetchFromPLC:did error:error];
    
    // Cache on success
    if (doc) {
        [self.cache setObject:doc forKey:did];
    }
    
    return doc;
}
```

**Cache Considerations**:
- Cache has no TTL (entries persist until evicted by LRU policy)
- Cache is memory-only (lost on restart)
- No invalidation mechanism for stale entries

**Production Recommendation**: Implement cache TTL or periodic refresh for frequently-accessed DIDs.

### Propagation Delays

Updates to DID documents may take time to propagate:

1. **PLC Server**: Immediate (operation accepted and indexed)
2. **PDS Instances**: Depends on cache TTL and refresh strategy
3. **Clients**: Depends on local cache and resolution frequency

**Best Practice**: After updating a DID document, wait a few seconds before relying on the new state being visible to all clients.

## Error Handling

### Common Errors

#### Invalid Signature

```objective-c
// Error: Signature verification failed
// Cause: Operation signed with wrong key or corrupted signature
// Solution: Ensure operation is signed with current rotation key
```

#### Chain Integrity Violation

```objective-c
// Error: prev field does not match previous operation CID
// Cause: Concurrent updates or incorrect prev value
// Solution: Fetch latest audit log and use correct prev CID
```

#### Size Limit Exceeded

```objective-c
// Error: Operation exceeds 7500 bytes DAG-CBOR limit
// Cause: Too much data in operation (e.g., large service endpoints)
// Solution: Reduce operation size or split into multiple updates
```

#### Invalid DID Format

```objective-c
// Error: DID must be exactly 32 characters long
// Cause: Malformed DID string
// Solution: Validate DID format before submission
if (![PLCOperation isValidDidPlc:did]) {
    NSLog(@"Invalid DID format: %@", did);
    return;
}
```

## Security Considerations

### Key Management

- **Rotation Keys**: Store securely, never commit to version control
- **Key Rotation**: Rotate keys periodically (recommended: annually)
- **Backup**: Maintain secure backups of rotation keys (loss = permanent DID loss)

### Signature Verification

Always verify signatures when processing operations:

```objective-c
// Verify operation signature before accepting
BOOL verified = [self verifyOperationSignature:operation 
                                    withPubKey:rotationKey 
                                         error:&error];
if (!verified) {
    NSLog(@"Invalid signature, rejecting operation");
    return;
}
```

### Replay Attacks

The `prev` field prevents replay attacks:
- Each operation references the previous operation's CID
- Operations cannot be reordered or replayed
- Concurrent updates are detected (conflicting `prev` values)

## Testing

### Unit Test Example

```objective-c
- (void)testHandleUpdate {
    // Generate key pair
    Secp256k1KeyPair *keyPair = [[Secp256k1 shared] generateKeyPairWithError:nil];
    NSString *didKey = [keyPair didKeyString];
    
    // Create genesis operation
    NSDictionary *createData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://oldhandle.bsky.social"],
        @"services": @{},
        @"prev": [NSNull null]
    };
    
    NSString *did = [PLCOperation calculateDIDForData:createData];
    
    PLCOperation *createOp = [[PLCOperation alloc] init];
    createOp.did = did;
    createOp.prev = nil;
    createOp.sig = @"test_sig";
    createOp.data = createData;
    
    // Calculate CID for prev link
    NSString *prevCid = [PLCOperation calculateCIDForOperation:[createOp toDictionary] 
                                                         error:nil];
    
    // Create update operation
    NSDictionary *updateData = @{
        @"type": @"plc_operation",
        @"rotationKeys": @[didKey],
        @"verificationMethods": @{@"atproto": didKey},
        @"alsoKnownAs": @[@"at://newhandle.bsky.social"],
        @"services": @{},
        @"prev": prevCid
    };
    
    PLCOperation *updateOp = [[PLCOperation alloc] init];
    updateOp.did = did;
    updateOp.prev = prevCid;
    updateOp.sig = @"test_sig";
    updateOp.data = updateData;
    
    // Replay history
    PLCDIDState *state = [PLCStateReplayer replayHistory:@[createOp, updateOp] 
                                                   error:nil];
    
    // Verify handle was updated
    XCTAssertEqualObjects(state.alsoKnownAs.firstObject, @"at://newhandle.bsky.social");
}
```

## Related Documentation

- [PLC Directory Concepts](plc-directory)
- [PLC Server Operations](../11-reference/plc-server-operations)
- [PLC Failover Strategies](../11-reference/plc-failover)
- [Cryptography Overview](cryptography)
- [CBOR Serialization](cbor-and-car)
