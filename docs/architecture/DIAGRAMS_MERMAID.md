# ATProto PDS - Mermaid Diagrams

This file contains supplementary diagrams in Mermaid format for easier rendering in markdown viewers that support Mermaid.

## XRPC Request Flow (Protocol Diagram)

```mermaid
sequenceDiagram
    participant Client
    participant HTTP as HTTP Server
    participant XRPC as XRPC Handler
    participant Auth as Auth Middleware
    participant PDS as PDS Controller
    participant DB as Database
    
    Client->>HTTP: GET /xrpc/com.atproto.server.createSession
    HTTP->>XRPC: Route to XRPC Handler
    XRPC->>Auth: Validate request
    Auth-->>XRPC: Auth OK
    XRPC->>PDS: Dispatch to createSession
    PDS->>DB: Query account
    DB-->>PDS: Account data
    PDS->>PDS: Generate tokens
    PDS-->>XRPC: {accessJwt, refreshJwt, did}
    XRPC-->>HTTP: JSON response
    HTTP-->>Client: 200 OK
```

## Record Creation Protocol

```mermaid
sequenceDiagram
    participant C as Client
    participant P as PDS
    participant PLC as PLC Directory
    participant S as Storage
    
    C->>P: POST /xrpc/com.atproto.repo.createRecord
    Note over P: Validate collection exists
    P->>PLC: Resolve DID document
    PLC-->>P: DID doc with signing key
    P->>P: Validate authorization (signed by DID)
    P->>S: Store record data (CBOR encoded)
    S-->>P: Content CID
    P->>P: Update repository MST
    P->>S: Commit new root CID
    P-->>C: {uri: "at://did:example/collection/rkey", cid: "bafy..."}
```

## ATProto Data Models

```mermaid
classDiagram
    class Repository {
        +String did
        +String rootCid
        +Collection[] collections
        +createRecord(collection, record)
        +getRecord(collection, rkey)
    }
    
    class Collection {
        +String name
        +Record[] records
    }
    
    class Record {
        +String cid
        +String collection
        +String rkey
        +Object value
        +Date createdAt
    }
    
    class Blob {
        +String cid
        +String mimeType
        +Integer size
        +String storagePath
    }
    
    class DIDDocument {
        +String id
        +String[] verificationMethods
        +Object[] services
    }
    
    Repository "1" --> "*" Collection : contains
    Collection "1" --> "*" Record : holds
    Repository "1" --> "1" DIDDocument : identified by
    Record --> Blob : references
```

## OAuth2 Token Flow

```mermaid
sequenceDiagram
    participant U as User
    participant C as Client
    participant A as Auth Server
    participant R as Resource Server
    
    C->>A: Authorization Request<br/>(client_id, redirect_uri, scope)
    A-->>U: Login screen
    U->>A: Enter credentials
    A-->>C: Authorization Code (redirect)
    C->>A: Exchange code for token<br/>(client_id, client_secret)
    A-->>C: Access Token + Refresh Token
    C->>R: API Request<br/>(Authorization: Bearer token)
    R-->>C: Resource Data
    
    Note over C,R: Later...
    C->>A: Refresh token request
    A-->>C: New Access Token
```

## Record Lifecycle Flow

```mermaid
flowchart TD
    A([Record Create]) --> B[Validate collection]
    B --> C[Check authorization]
    C --> D{Authorized?}
    D -->|No| E[Return 403]
    D -->|Yes| F[CBOR encode value]
    F --> G[Create content block]
    G --> H[Store in CAR archive]
    H --> I[Generate CID]
    I --> J[Update MST]
    J --> K[Commit new root]
    K --> L[Return URI + CID]
    E --> M([End])
    L --> M
    
    style A fill:#c8e6c9
    style M fill:#c8e6c9
    style C fill:#ffe0b2
    style E fill:#ffcdd2
```

## Session Management Flow

```mermaid
flowchart TD
    A([Login Request]) --> B{Valid credentials?}
    B -->|No| C[Return 401]
    B -->|Yes| D{2FA required?}
    D -->|Yes| E[Prompt 2FA]
    E --> F{Valid 2FA?}
    F -->|No| G[Return 401]
    F -->|Yes| H[Create session]
    D -->|No| H
    H --> I[Generate access token<br/>15min expiry]
    I --> J[Generate refresh token<br/>30day expiry]
    J --> K[Store session in DB]
    K --> L[Return tokens]
    C --> M([End])
    G --> M
    L --> M
    
    style A fill:#c8e6c9
    style M fill:#c8e6c9
    style B fill:#ffe0b2
    style D fill:#ffe0b2
    style F fill:#ffe0b2
    style C fill:#ffcdd2
    style G fill:#ffcdd2
```

## WebSocket Firehose Subscription

```mermaid
sequenceDiagram
    participant C as Client
    participant P as PDS
    participant Sub as SubscribeRepos
    participant DB as Database
    
    C->>P: WebSocket Upgrade<br/>/xrpc/com.atproto.sync.subscribeRepos
    P->>Sub: Create subscription
    Sub-->>C: WebSocket Connected
    Sub-->>C: Cursor position
    
    Note over P: Repo commit happens
    P->>DB: Get changed records
    DB-->>P: Record changes
    P->>Sub: Encode event (CBOR)
    
    Sub-->>C: #commit event<br/>(repo, commit, ops)
    C->>Sub: Acknowledge
    Sub-->>C: Next event
    
    C->>P: Close WebSocket
    P->>Sub: End subscription
```

## Rate Limiting Logic

```mermaid
flowchart LR
    A[Request] --> B{Has quota?}
    B -->|No| C[Return 429<br/>Too Many Requests]
    B -->|Yes| D{Valid auth?}
    D -->|No| E[Return 401<br/>Unauthorized]
    D -->|Yes| F[Process request]
    F --> G[Decrement quota]
    G --> H[Return 200<br/>OK]
    
    C --> I([End])
    E --> I
    H --> I
    
    style B fill:#ffe0b2
    style D fill:#ffe0b2
    style C fill:#ffcdd2
    style E fill:#ffcdd2
    style H fill:#c8e6c9
```

## Blob Storage Flow

```mermaid
flowchart TD
    A([Upload Blob]) --> B[Validate content-type]
    B --> C{Valid type?}
    C -->|No| D[Return 400<br/>Invalid type]
    C -->|Yes| E[Check size]
    E --> F{Under limit?}
    F -->|No| G[Return 413<br/>Too large]
    F -->|Yes| H[Store blob<br/>Generate CID]
    H --> I[SHA-256 digest]
    I --> J[Create blob record]
    J --> K[Return CID]
    D --> L([End])
    G --> L
    K --> L
    
    style B fill:#ffe0b2
    style C fill:#ffe0b2
    style E fill:#ffe0b2
    style F fill:#ffe0b2
    style D fill:#ffcdd2
    style G fill:#ffcdd2
    style K fill:#c8e6c9
```

## Quick Reference

| Diagram Type | Mermaid Syntax | Use For |
|--------------|----------------|---------|
| Protocol | `sequenceDiagram` | Request/response flows |
| Data Model | `classDiagram` | Object relationships |
| Control Flow | `flowchart TD` | Decision processes |
| Architecture | `graph TB` | Component diagrams |
| State | `stateDiagram-v2` | State machines |

## Related Documentation

### Architecture Documents
- [README.md](README) - Architecture documentation index
- [ARCHITECTURE_ANALYSIS.md](ARCHITECTURE_ANALYSIS) - Component analysis referenced in diagrams
- [atproto_pds_architecture.md](atproto_pds_architecture) - Protocol specifications for flows above
- [atproto_data_models.md](atproto_data_models) - Data model class diagram details

### Diagram Documents
- [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) - System overview diagrams
- [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) - Diagram selection guide
- [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS) - Development process diagrams
