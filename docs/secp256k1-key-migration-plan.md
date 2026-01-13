# Secp256k1 Key Migration Plan

## Problem

Current `ActorStore.generateSigningKeyWithError:` generates RSA-2048 keys, but ATProto requires secp256k1 keys for commit signing.

The signing flow is:
1. `PDSRepositoryService.getRecordWithProof:` calls `store.signingKeyPrivateBytesWithError:`
2. Returns RSA key bytes (PKCS#1 format, 1200+ bytes)
3. `RepoCommit.signWithPrivateKey:` expects secp256k1 key (32 bytes)
4. `Secp256k1.signHash:withPrivateKey:` fails because key is wrong size

## Solution

### Phase 1: Update ActorStore Key Generation

Modify `ActorStore` to:
1. Generate secp256k1 keys using existing `Secp256k1KeyPair` class
2. Store raw 32-byte private key in Keychain (as data, not SecKey)
3. Store 33-byte compressed public key separately for DID key generation

**Changes to ActorStore.m:**
- `generateSigningKeyWithError:` → use `Secp256k1KeyPair.generateKeyPair:`
- `storeSigningKey:` → store raw NSData instead of SecKeyRef
- `signingKeyWithError:` → return raw NSData from Keychain
- `signingKeyPrivateBytesWithError:` → simplified, just return stored data
- Remove SecKeyRef property (no longer needed)

### Phase 2: Update Key Storage Format

**Old format (RSA):**
- kSecClassGenericPassword with kSecValueRef (SecKeyRef)
- Key type: RSA-2048
- Size: ~1200 bytes in PKCS#1 format

**New format (secp256k1):**
- kSecClassGenericPassword with kSecValueData (NSData)
- Private key: 32 bytes raw
- Public key: 33 bytes compressed (stored separately)

### Phase 3: Handle Migration

For existing RSA keys:
- Detect RSA format by size (> 32 bytes)
- Log warning and generate new secp256k1 key
- Note: This will break any existing commit signatures

### Phase 4: Testing

1. Unit test: Key generation produces 32-byte private key
2. Unit test: Signing works with generated key
3. Integration: Build, run PDS, create account, verify commit signing

## Implementation Order

1. ✅ Add `#import "Auth/Secp256k1.h"` to ActorStore.m
2. ✅ Update `generateSigningKeyWithError:` to use Secp256k1KeyPair
3. ✅ Update `storeSigningKeyData:` to store raw bytes
4. ✅ Update `signingKeyPrivateBytesWithError:` to retrieve raw bytes
5. ✅ Build and test - All tests pass
6. ✅ Update documentation

## Status: COMPLETE

The migration from RSA to secp256k1 keys is complete. ActorStore now:
- Generates proper 32-byte secp256k1 private keys
- Stores raw key bytes in Keychain (not SecKeyRef)
- Returns keys that are compatible with RepoCommit.signWithPrivateKey:

## Files to Modify

- `ATProtoPDS/Sources/Database/ActorStore/ActorStore.m`
- `ATProtoPDS/Sources/Database/ActorStore/ActorStore.h` (if interface changes needed)
