# did:plc Implementation Plan

## Current State

The codebase has:
- ✅ DID validation for `did:plc` format
- ✅ DID resolution from plc.directory (read-only)
- ✅ Random `did:plc` identifier generation (but NOT valid - just random strings)
- ❌ **Missing: PLC operation creation and submission**
- ❌ **Missing: Proper cryptographic signing for PLC operations**
- ❌ **Missing: DAG-CBOR encoding for operations**

## What's Needed to Register did:plc Identities

### 1. PLC Operation Data Structure

A genesis (creation) operation needs:
```json
{
  "type": "plc_operation",
  "rotationKeys": ["did:key:z..."],      // Recovery/rotation keys (1-5)
  "verificationMethods": {
    "atproto": "did:key:z..."            // Signing key for repo commits
  },
  "alsoKnownAs": ["at://handle.example.com"],
  "services": {
    "atproto_pds": {
      "type": "AtprotoPersonalDataServer",
      "endpoint": "https://pds.example.com"
    }
  },
  "prev": null,                          // null for genesis
  "sig": "<base64url signature>"
}
```

### 2. Key Requirements

Need to generate/manage:
- **Rotation Key(s)**: secp256k1 or P-256, controls DID updates
- **Signing Key**: For atproto repo commits (verificationMethods.atproto)

Both must be encoded as `did:key` format (multibase + multicodec).

### 3. Signing Process

1. Create operation object WITHOUT `sig` field
2. Encode as DAG-CBOR (not JSON!)
3. Sign bytes with ECDSA-SHA256 using rotation key
4. Canonicalize signature to "low-S" form
5. Encode signature as base64url (no padding)
6. Add `sig` field to operation

### 4. DID Derivation

```
did:plc:<base32(sha256(dag-cbor(signed_genesis_op)))[0:24]>
```

### 5. Submission

HTTP POST to `https://plc.directory/<did>` with JSON body of signed operation.

## Implementation Tasks

### Task 1: DAG-CBOR Encoding
- We have CBOR.m but need to verify DAG-CBOR compliance
- Key ordering must be deterministic (sorted)
- Need to handle `null` values correctly

### Task 2: did:key Encoding/Decoding
- Multibase (base58btc, prefix 'z')
- Multicodec for key type:
  - secp256k1: 0xe7
  - P-256: 0x1200
- Compressed public key format

### Task 3: PLC Operation Builder
New class: `PLCOperationBuilder`
```objc
@interface PLCOperationBuilder : NSObject
- (instancetype)initWithRotationKeys:(NSArray<NSData *> *)rotationKeys
                          signingKey:(NSData *)signingKey
                              handle:(NSString *)handle
                         pdsEndpoint:(NSString *)endpoint;
- (NSDictionary *)buildGenesisOperation:(NSError **)error;
- (NSDictionary *)buildUpdateOperation:(NSString *)prevCID error:(NSError **)error;
- (NSString *)computeDIDFromGenesisOperation:(NSDictionary *)op error:(NSError **)error;
@end
```

### Task 4: PLC Directory Client
New class: `PLCDirectoryClient`
```objc
@interface PLCDirectoryClient : NSObject
- (void)submitOperation:(NSDictionary *)operation
                 forDID:(NSString *)did
             completion:(void(^)(BOOL success, NSError *error))completion;
- (void)getOperationLog:(NSString *)did
             completion:(void(^)(NSArray *operations, NSError *error))completion;
@end
```

### Task 5: Key Management Integration
- Generate rotation key pair on account creation
- Store rotation private key securely (encrypted in DB or keychain)
- Use existing ActorStore signing key for verificationMethods.atproto

### Task 6: Account Creation Flow Update
1. Generate rotation key pair
2. Get/generate signing key
3. Build genesis operation
4. Compute DID from operation
5. Sign operation
6. Submit to plc.directory
7. If successful, store account with real DID

## Files to Create/Modify

### New Files:
- `ATProtoPDS/Sources/Identity/PLCOperationBuilder.m`
- `ATProtoPDS/Sources/Identity/PLCDirectoryClient.m`
- `ATProtoPDS/Sources/Identity/DIDKeyEncoder.m`

### Modify:
- `ATProtoPDS/Sources/App/Services/PDSAccountService.m` - Use PLC for account creation
- `ATProtoPDS/Sources/Core/CBOR.m` - Ensure DAG-CBOR compliance
- `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m` - Store rotation keys

## Testing

1. Unit tests for DAG-CBOR encoding
2. Unit tests for did:key encoding
3. Unit tests for operation signing
4. Integration test against plc.directory sandbox (if available)
5. Full account creation flow test

## Estimated Effort

- Task 1 (DAG-CBOR): 2-4 hours
- Task 2 (did:key): 2-3 hours  
- Task 3 (Operation Builder): 4-6 hours
- Task 4 (Directory Client): 2-3 hours
- Task 5 (Key Management): 3-4 hours
- Task 6 (Account Flow): 2-3 hours
- Testing: 4-6 hours

**Total: ~20-30 hours of work**

## References

- [did:plc spec](https://github.com/did-method-plc/did-method-plc)
- [DAG-CBOR spec](https://ipld.io/specs/codecs/dag-cbor/spec/)
- [did:key spec](https://w3c-ccg.github.io/did-key-spec/)
- [Multibase](https://github.com/multiformats/multibase)
- [Multicodec](https://github.com/multiformats/multicodec)
