---
title: Cryptography and Digital Identity
description: Repository commits, DID keys, P-256, and secp256k1 verification
---

AT Protocol cryptography connects a repository state to the account DID. The PDS
signs repository commits, and consumers verify those signatures with the account
signing key published in the DID document.

Individual records are content-addressed but are not each signed by the client.
The signed commit references the MST root, which in turn references record
blocks. Verifying the commit and every CID link authenticates the repository
snapshot.

## Repository commits

A version 3 repository commit contains:

- the repository DID
- a revision identifier
- the MST root CID
- the previous commit CID, when one exists
- a signature over the unsigned DAG-CBOR commit

Garazyk's `RepoCommit` path hashes the unsigned commit with SHA-256 and signs it
with the account's secp256k1 key. The signed DAG-CBOR block receives its own CID
and becomes the root of repository CAR exports.

Verification must establish all of the following:

1. The signed block decodes as a valid repository commit.
2. The commit DID matches the repository being imported.
3. The signature verifies with the DID document's account signing key.
4. The commit's data CID identifies the supplied MST root.
5. Every referenced block matches its CID.

A successful ECDSA operation alone does not validate the surrounding repository
structure.

## Other signature contexts

Garazyk also verifies P-256 or secp256k1 signatures in PLC operations, OAuth
DPoP proofs, service JWTs, and WebAuthn assertions. These protocols use
different messages and canonicalization rules. Keep their verification policies
separate.

In particular:

- JOSE, DPoP, and WebAuthn P-256 verification accepts both low-S and high-S
  signatures.
- did:plc operation signatures require low-S canonicalization for both P-256 and
  secp256k1.
- Repository commit verification follows the repository signing-key path.

Applying one global low-S rule breaks valid JOSE and WebAuthn signatures.
Omitting the PLC-specific rule accepts non-canonical PLC operations.

## Key resolution

The verifier selects the account signing method from the DID document rather
than accepting an arbitrary key supplied with the request. The method
identifier, multicodec prefix, curve, and key length must agree.

Key rotation changes the DID document, not historical commit bytes. Import and
audit code therefore needs the DID state appropriate to the object being
verified when the protocol requires historical resolution.

## Native resource handling

OpenSSL and libsecp256k1 objects are C resources. ARC does not release them.
Code must free every context and key on success and failure paths:

```objc
EVP_MD_CTX *context = EVP_MD_CTX_new();
if (context == NULL) {
    return NO;
}

BOOL valid = NO;
@try {
    if (EVP_DigestVerifyInit(context, NULL, EVP_sha256(), NULL, publicKey) == 1 &&
        EVP_DigestVerifyUpdate(context, data.bytes, data.length) == 1) {
        valid = EVP_DigestVerifyFinal(context, signature.bytes, signature.length) == 1;
    }
} @finally {
    EVP_MD_CTX_free(context);
}
return valid;
```

Production code must also validate key construction, signature encoding, and
every OpenSSL return value. Error messages may identify the failed stage but
must not log private keys, access tokens, or raw authentication proofs.
