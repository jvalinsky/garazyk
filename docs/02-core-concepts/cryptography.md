---
title: Cryptography
---

# Cryptography

## Overview

September uses cryptography for a small number of concrete jobs:

- identify content by hash
- sign and verify tokens
- sign and verify repository or identity material
- generate nonces, keys, and protected secrets

This page is not a catalog of every algorithm in the tree. It is a map from
cryptographic role to the code that depends on it.

## Hashing And Content Addressing

SHA-256 is the foundational hash in the repository:

- blob CIDs are derived from content hashes
- repository blocks and related content-addressed structures depend on stable
  digests
- JWT and DPoP verification paths hash signing input before signature checks in
  the algorithms that require it

This is why the repo's storage and sync code talks so much about CIDs. Content
addressing is not an implementation detail layered on later. It is part of the
protocol model.

## Signing Keys In Practice

The repository uses more than one key story because ATProto itself does:

- secp256k1 actor keys are used for ES256K-style signing paths
- P-256 appears in DPoP and other ES256-oriented OAuth flows
- key-manager backed JWT flows can also verify algorithms such as ES256 or
  RS256 where configured

The useful mental model is "algorithm choice follows protocol role", not "one
algorithm rules the whole server."

## JWT And DPoP

`JWT`, `JWTVerifier`, and `JWTMinter` are the core token primitives.
`XrpcAuthHelper` uses them to validate access tokens and bind DPoP proofs to the
request that presented them.

Two important distinctions matter here:

- access-token and actor-key flows often rely on ES256K-style signing
- DPoP proofs are ES256/P-256 oriented and validated as request-bound proofs

That split is why the auth helper owns so much logic. Token verification is not
just "check a signature". It is "check the right signature for the right
protocol context."

## PLC And Identity Verification

PLC operation verification is another distinct crypto path. `PLCAuditor`
validates signed, hash-linked operations and accepts the rotation-key authority
model encoded in PLC history.

In practice that means the PLC layer cares about:

- operation hashes and CIDs
- valid `did:key` rotation keys
- signature verification for submitted operations
- replay safety across the history chain

This is identity cryptography, not just generic message signing.

## Utility Primitives

`CryptoUtils` provides the lower-level helpers used throughout the tree:

- HMAC-SHA1 and HMAC-SHA256
- SHA-256
- secure random bytes
- base64url helpers
- constant-time string comparison
- AES-256-CBC encryption and decryption
- PBKDF2-SHA256 key derivation

These utilities matter because they give the rest of the codebase one place to
share security-sensitive primitives instead of reimplementing them ad hoc.

## Why Contributors Should Care

Most contributors do not need to write new cryptographic code. They do need to
know when they are crossing a cryptographic boundary:

- changing blob or repository addressing
- changing token validation
- changing DPoP behavior
- changing DID or PLC update flows

Those are the places where "small" changes often become security or
interoperability regressions.

## Related Reading

- [ATProto Basics](./atproto-basics)
- [PLC Directory](./plc-directory)
- [DID Document Updates](./did-document-updates)
- [Auth Helpers](../04-network-layer/auth-helpers)
