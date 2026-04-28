---
title: Key Rotation
---

# Key Rotation

## Overview

In Garazyk, key rotation manages PLC rotation keys and the actor-scoped signing material for identity updates. It handles generating, storing, selecting, and using keys when the server signs PLC operations.

## Full Flow

```mermaid
flowchart TD
    Server["Load or generate server PLC rotation key"]
    Actor["Load optional per-DID rotation key"]
    Build["Build PLC operation with rotationKeys"]
    Sign["Sign update or handle operation"]
    Submit["Submit and persist resulting state"]
    Verify["Later reads validate did:key chain"]

    Server --> Build
    Actor --> Build
    Build --> Sign
    Sign --> Submit
    Submit --> Verify
```

## What Exists Today

The live rotation-key path spans a few concrete files:

- `Garazyk/Sources/PLC/PLCRotationKeyManager.m` loads or generates the server rotation key and persists it on disk, encrypting it when the master-secret path is available.
- `Garazyk/Sources/Database/ActorStore/ActorStore.m` can store and retrieve per-DID rotation keys in encrypted form.
- `Garazyk/Sources/Network/XrpcIdentityMethods.m` builds PLC operations, requires `rotationKeys` on update paths, and chooses whether to sign with the actor-specific key or the server-wide key.
- the PLC validation layer rejects malformed `did:key` material and verifies signature chains before accepting state.

The process loads keys, chooses the signer, produces a valid PLC operation, and keeps the state consistent with directory verification.

## Common Failure Modes

When this area breaks, the usual causes are:

- the server rotation key cannot be loaded or decrypted
- a per-DID rotation key exists but cannot be recovered from actor storage
- the request omits `rotationKeys` or provides invalid `did:key` entries
- the operation is signed with a key that does not match the declared rotation chain

These failures often appear as remote PLC rejections, but the root cause is usually local key state.

## Related Deep Dives

- [PLC Operation Walkthrough](../02-core-concepts/plc-operation-walkthrough)
- [DID Update Walkthrough](../02-core-concepts/did-update-walkthrough)
- [Cryptography in Practice](../02-core-concepts/cryptography-in-practice)

## Related Reading

- [PLC Directory](../02-core-concepts/plc-directory)
- [PLC Server Operations](../11-reference/plc-server-operations)
- [Cryptography](../02-core-concepts/cryptography)

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

