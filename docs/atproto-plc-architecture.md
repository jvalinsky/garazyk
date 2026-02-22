# ATProto PLC Architecture

This document describes the architecture and data flows for the PLC DID operations in the objpds PDS implementation.

## 0. Server-Level Rotation Key

The PDS maintains a dedicated **PLCRotationKeyManager** for signing PLC operations. This is distinct from per-account signing keys:

```text
  +-----------------------+
  |  PLCRotationKeyManager|
  |                       |
  |  [ Server Key ]       |  <-- Generated once, persisted to disk
  |  did:key:zQ3sh...     |
  +-----------------------+
            |
            | Signs ALL PLC operations for this PDS
            v
  +-----------------------+
  |  Genesis / Update Ops |
  +-----------------------+
```

**Key Points:**
- One server rotation key per PDS instance
- Stored in `data/plc_rotation_key.bin`
- Used to sign both genesis and update operations
- Must be included in `rotationKeys` array for all operations

## 1. The Operation Chain (The Ledger)
The "Log" is a linked list of signed operations. Each operation points to the hash of the previous one, making the history immutable and verifiable.

```text
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

## 2. Submission Flow (The Write Path)
How a PDS (or User) updates their identity.

```text
      [ PDS / USER ]                    [ objpds ]
            |                                  |
    1. Create Op JSON                          |
    2. Sign with R-Key                         |
    3. POST /xrpc/com.atproto.identity.submitPlcOperation
            |                                  | 4. VALIDATE:
            |                                  |    - Server rotation key in rotationKeys?
            |                                  |    - services.atproto_pds.type correct?
            |                                  |    - services.atproto_pds.endpoint matches?
            |                                  |    - alsoKnownAs contains handle?
            |                                  |    - prev matches last op CID?
            |                                  |    - Signature valid?
            |                                  |          |
            |          202 ACCEPTED            | <--- [ YES ]
            |<---------------------------------|          |
            |                                  | 5. FORWARD to PLC Directory
```

## 3. Resolution Flow (The Read Path)
How any server on the internet determines your current PDS address or handle.

```text
      [ RESOLVER ]                      [ objpds ]
            |                                  |
    1. GET /did:plc:123  --------------------->|
            |                                  | 2. Fetch full history from DB
            |                                  | 3. [ Op0, Op1, Op2 ]
            |       JSON Operation Log         |
            |<---------------------------------|
            |
    4. REPLAY LOG:
       - Start with Empty Doc
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
How the PDS prepares a signed PLC operation for submission.

```text
      [ AUTHENTICATED USER ]            [ objpds ]
            |                                  |
    1. POST /xrpc/com.atproto.identity.signPlcOperation
            |     { token: "ABC123" }          |
            |                                  | 2. VALIDATE:
            |                                  |    - Token valid for DID?
            |                                  |          |
            |                                  | 3. FETCH AUDIT LOG:
            |                                  |    - Get all operations for DID
            |                                  |    - Detect tombstone -> REJECT
            |                                  |          |
            |                                  | 4. CALCULATE PREV:
            |                                  |    - Get last operation
            |                                  |    - Calculate CID( lastOp )
            |                                  |          |
            |                                  | 5. BUILD OPERATION:
            |                                  |    - rotationKeys: [ serverKey, ... ]
            |                                  |    - verificationMethods: { atproto: actorKey }
            |                                  |    - alsoKnownAs: [ at://handle ]
            |                                  |    - services: { atproto_pds: {...} }
            |                                  |    - prev: CID( lastOp )
            |                                  |          |
            |                                  | 6. SIGN:
            |                                  |    - CBOR encode operation
            |                                  |    - SHA-256 hash
            |                                  |    - Sign with server rotation key
            |                                  |          |
            |       { operation: {..., sig} }  |
            |<---------------------------------|
```

## 5. Integration with PDS
How the PDS uses PLC operations.

```text
    +-----------------------+           +-----------------------+
    |  SEPTEMBER (PDS)      |           |  PLC DIRECTORY        |
    |                       |           |                       |
    |  [ Account Service ]--|---HTTP--->|  [ Remote Server ]    |
    |  [ Repo Service    ]  | (Update)  |                       |
    |  [ PLCRotationKey  ]  |           |                       |
    +-----------------------+           +-----------------------+
                ^                                   |
                |                                   |
                `------------- HTTP ----------------'
                           (Resolution)
```

## 6. Security Considerations

### Rotation Key Management
- Server rotation key is stored on disk at `data/plc_rotation_key.bin`
- Key is generated on first use if not present
- Loss of this key prevents future PLC operations for all accounts

### Validation Gates
The PDS enforces these validations before forwarding operations:
1. **Rotation Keys**: Server key must be present
2. **Service Type**: Must be `AtprotoPersonalDataServer`
3. **Service Endpoint**: Must match configured server URL
4. **Handle**: Must match account's current handle
5. **Prev CID**: Must match last operation (prevents replay)
6. **Tombstone**: Rejects operations on deactivated accounts

### DID Resolution Security
- `Accept` header includes `application/did+ld+json,application/json`
- Redirect following is disabled to prevent SSRF via malicious PLC servers

## Related Documentation

### Architecture
- [PDS Architecture](architecture/atproto_pds_architecture.md) - Overall PDS system design
- [Architecture Analysis](architecture/ARCHITECTURE_ANALYSIS.md) - Detailed architecture review
- [Data Models](architecture/atproto_data_models.md) - ATProto data structures
- [Architecture Diagrams](architecture/DIAGRAMS_MERMAID.md) - Visual architecture diagrams

### Testing
- [Identity & Auth Tests](tests/00-identity-auth/README.md) - DID resolution, JWT tests
- [Integration Tests](tests/06-integration/plc.md) - PLC integration testing

### OAuth & Security
- [OAuth 2.0 Overview](oauth2/README.md) - OAuth implementation details
- [Security Analysis](security/SECURITY_ANALYSIS_REPORT.md) - Security posture review
