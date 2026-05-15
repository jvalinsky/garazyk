---
title: ATProto PLC Architecture
---

# ATProto PLC Architecture

This document describes the architecture and data flows for the Public Ledger of Credentials (PLC) operations in the PDS.

## 0. Server-Level Rotation Key

The PDS maintains a dedicated **PLCRotationKeyManager** for signing PLC operations. This key is distinct from individual account signing keys.

```
  +-----------------------+
  |  PLCRotationKeyManager|
  |                       |
  |  [ Server Key ]       |  <-- Generated once, persisted to disk
  |  did:key:zQ3sh...     |
  +-----------------------+
            |
            | Signs all PLC operations for this PDS
            v
  +-----------------------+
  |  Genesis / Update Ops |
  +-----------------------+
```

**Implementation Details:**
- One server rotation key per PDS instance.
- Persisted at `data/plc_rotation_key.bin`.
- Signs both genesis and update operations.
- Included in the `rotationKeys` array for all operations.

## 1. The Operation Chain (The Ledger)

The ledger is a linked list of signed operations. Each operation includes the CID (Content Identifier) of the previous operation, ensuring an immutable and verifiable history.

```
  OPERATION 0 (Genesis)      OPERATION 1 (Update)       OPERATION 2 (Rotation)
 +----------------------+   +----------------------+   +----------------------+
 | type: plc_operation  |   | type: plc_operation  |   | type: plc_operation  |
 | prev: null           |   | prev: Hash(Op 0) <-------| prev: Hash(Op 1) <---|-- (Next)
 | handle: alice.com    |   | handle: bob.com      |   | service: https://pds |
 | signingKey: K1       |   |                      |   | rotationKeys: [R2]   |
 | rotationKeys: [R1]   |   |                      |   |                      |
 +----------------------+   +----------------------+   +----------------------+
 | SIG: (By R1)         |   | SIG: (By R1)         |   | SIG: (By R1)         |
 +----------------------+   +----------------------+   +----------------------+
            |                          |                          |
            `--------------------------`--------------------------`---> [ AUDIT LOG ]
```

## 2. Submission Flow

How a PDS or user updates their identity on the network.

```
      [ PDS / USER ]                    [ PDS Backend ]
            |                                  |
    1. Create Op JSON                          |
    2. Sign with R-Key                         |
    3. POST /xrpc/com.atproto.identity.submitPlcOperation
            |                                  | 4. VALIDATE:
            |                                  |    - Server rotation key present?
            |                                  |    - service type matches?
            |                                  |    - service endpoint matches?
            |                                  |    - alsoKnownAs contains handle?
            |                                  |    - prev matches last op CID?
            |                                  |    - Signature valid?
            |                                  |          |
            |          202 ACCEPTED            | <--- [ YES ]
            |<---------------------------------|          |
            |                                  | 5. FORWARD to PLC Directory
```

## 3. Resolution Flow

How external services determine a PDS address or handle for a given DID.

```
      [ RESOLVER ]                      [ PDS Backend ]
            |                                  |
    1. GET /did:plc:123  --------------------->|
            |                                  | 2. Fetch full history from DB
            |                                  | 3. [ Op0, Op1, Op2 ]
            |       JSON Operation Log         |
            |<---------------------------------|
            |
    4. REPLAY LOG:
       - Start with empty document
       - Apply Op0 -> Doc { handle: alice.com, ... }
       - Apply Op1 -> Doc { handle: bob.com, ... }
       - Apply Op2 -> Doc { pds: https://pds, ... }
            |
    5. FINAL DID DOCUMENT:
       {
         "id": "did:plc:123",
         "alsoKnownAs": ["at://bob.com"],
         "service": [{ "id": "#atproto_pds", "type": "...", "endpoint": "..." }]
       }
```

## 4. Signing Flow (signPlcOperation)

The internal process for preparing a signed PLC operation for submission.

```
      [ AUTHENTICATED USER ]            [ PDS Backend ]
            |                                  |
    1. POST /xrpc/com.atproto.identity.signPlcOperation
            |     { token: "ABC123" }          |
            |                                  | 2. VALIDATE:
            |                                  |    - Token valid for DID?
            |                                  |          |
            |                                  | 3. FETCH AUDIT LOG:
            |                                  |    - Retrieve all operations for DID
            |                                  |    - Reject if tombstoned
            |                                  |          |
            |                                  | 4. CALCULATE PREV:
            |                                  |    - Get last operation CID
            |                                  |          |
            |                                  | 5. BUILD OPERATION:
            |                                  |    - rotationKeys: [ serverKey, ... ]
            |                                  |    - verificationMethods: { atproto: actorKey }
            |                                  |    - alsoKnownAs: [ at://handle ]
            |                                  |    - services: { atproto_pds: {...} }
            |                                  |    - prev: CID(lastOp)
            |                                  |          |
            |                                  | 6. SIGN:
            |                                  |    - CBOR encode operation
            |                                  |    - SHA-256 hash
            |                                  |    - Sign with server rotation key
            |                                  |          |
            |       { operation: {..., sig} }  |
            |<---------------------------------|
```

## 5. Security Considerations

### Rotation Key Management
- The server rotation key is critical. Losing it prevents any future identity updates for all accounts on this PDS.
- It is stored at `data/plc_rotation_key.bin`.

### Validation Gates
The PDS enforces these checks before forwarding operations to the PLC directory:
1. **Rotation Keys**: The server-level key must be included.
2. **Service Type**: Must be `AtprotoPersonalDataServer`.
3. **Service Endpoint**: Must match the configured PDS URL.
4. **Handle**: Must match the account's registered handle.
5. **Prev CID**: Must match the last known operation to prevent replay or fork attacks.
6. **Tombstone**: Rejects operations for deactivated accounts.

### DID Resolution Security
- `Accept` header strictly requires `application/did+ld+json` or `application/json`.
- Redirects are disabled during resolution to prevent SSRF.

## Related

### Architecture
- [PDS Architecture](01-getting-started/architecture-overview)
- [Diagrams](12-diagrams/index)
- [Data Models](02-core-concepts/cbor-and-car)

### Testing
- [Testing Guide](TESTING)
- [Identity & Auth Tests](11-reference/testing-map)

### Security
- [Monitoring](MONITORING)
- [Glossary](GLOSSARY)
