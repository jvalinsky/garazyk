# ATProto PLC Architecture

This document describes the architecture and data flows for the `atproto-plc` utility, an Objective-C implementation of the DID:PLC protocol.

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
      [ PDS / USER ]                    [ atproto-plc ]
            |                                  |
    1. Create Op JSON                          |
    2. Sign with R-Key                         |
    3. POST /did:plc:123  -------------------->|
            |                                  | 4. VALIDATE:
            |                                  |    - Prev hash matches tail?
            |                                  |    - Signature valid for R-Keys?
            |                                  |    - Monotonic sequence?
            |                                  |          |
            |          202 ACCEPTED            | <--- [ YES ]
            |<---------------------------------|          |
            |                                  | 5. APPEND to SQLite/Disk
```

## 3. Resolution Flow (The Read Path)
How any server on the internet determines your current PDS address or handle.

```text
      [ RESOLVER ]                      [ atproto-plc ]
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

## 4. Integration with PDS
How the PDS (`september`) uses `atproto-plc`.

```text
   +-----------------------+           +-----------------------+
   |  SEPTEMBER (PDS)      |           |  ATPROTO-PLC          |
   |                       |           |                       |
   |  [ Account Service ]--|---HTTP--->|  [ MockLogProvider ]  |
   |  [ Repo Service    ]  | (Update)  |  [ SQLite Store    ]  |
   +-----------------------+           +-----------------------+
               ^                                   |
               |                                   |
               `------------- HTTP ----------------'
                          (Resolution)
```
