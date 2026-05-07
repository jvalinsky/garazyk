# Cryptography

Garazyk uses cryptography for four primary tasks:
- Identifying content by hash (CIDs).
- Signing and verifying authentication tokens (JWT).
- Signing and verifying repository and identity material.
- Generating nonces, keys, and protected secrets.

## Hashing and Content Addressing
SHA-256 is the foundational hash for the repository. It is used for:
- Deriving blob CIDs from content.
- Addressing repository blocks and content-addressed structures.
- Hashing signing input for JWT and DPoP verification.

Content addressing is central to the protocol model, governing how storage and synchronization logic identify data.

## Signing Keys
Garazyk supports multiple key types as required by the AT Protocol:
- **secp256k1**: Used for ES256K signing. Signatures are verified for low-S form to prevent malleability.
- **P-256**: Used for DPoP and ES256 OAuth flows. Also enforces low-S signatures.
- **Key-manager backed JWT**: Verifies RS256 or ES256 where configured.

Algorithm choice is determined by the specific protocol role.

## JWT and DPoP
`JWT`, `JWTVerifier`, and `JWTMinter` are the core token primitives. `XrpcAuthHelper` uses these to validate tokens and bind DPoP proofs to requests.

Key distinctions:
- **Access tokens** and actor-key flows typically use ES256K.
- **DPoP proofs** use ES256/P-256 and are validated as request-bound proofs.

Verification involves checking the signature against the specific protocol context and requirements.

## PLC and Identity
`PLCAuditor` validates signed, hash-linked operations according to the PLC rotation-key authority model. The identity layer manages:
- Operation hashes and CIDs.
- `did:key` rotation key validity.
- Signature verification for submitted operations.
- Replay safety across the history chain.

## Utilities
`CryptoUtils` provides shared, lower-level primitives:
- HMAC-SHA1 and HMAC-SHA256.
- SHA-256 and secure random byte generation.
- Base64url and constant-time string comparison.
- AES-256-CBC encryption/decryption.
- PBKDF2-SHA256 key derivation.

## Impact Areas
Changes to the following areas require careful cryptographic review:
- Blob or repository addressing logic.
- Token validation and DPoP behavior.
- DID or PLC update flows.

## Related

- [ATProto Basics](./atproto-basics)
- [Cryptography In Practice](./cryptography-in-practice)
- [PLC Directory](./plc-directory)
- [DID Document Updates](./did-document-updates)
- [Auth Helpers](../04-network-layer/auth-helpers)
- [Documentation Map](../11-reference/documentation-map.md)

