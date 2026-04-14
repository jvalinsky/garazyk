---
title: Development Workflow Diagrams
---

# Development Workflow Diagrams

Visual guides for common development tasks in this project.

## Build and Run Process

```mermaid
flowchart TD
    A([Start Dev]) --> B[Generate Xcode project]
    B --> C[Build CLI tool]
    C --> D{Build success?}
    D -->|No| E[Fix compilation errors]
    E --> C
    D -->|Yes| F[Run tests]
    F --> G{Tests pass?}
    G -->|No| H[Fix failing tests]
    H --> F
    G -->|Yes| I[Start PDS server]
    I --> J[Server running on port 2583]
    J --> K([Ready for development])
    
    style A fill:#c8e6c9
    style K fill:#c8e6c9
    style D fill:#ffe0b2
    style G fill:#ffe0b2
    style E fill:#ffcdd2
    style H fill:#ffcdd2
```

## Test Pyramid

```mermaid
flowchart TD
    subgraph "Unit Tests [107 tests]"
        U1[Repository Tests]
        U2[Auth Tests]
        U3[Core Tests]
        U4[Database Tests]
    end
    
    subgraph "Integration Tests"
        I1[API Endpoint Tests]
        I2[OAuth2 Flow Tests]
    end
    
    subgraph "Fuzzing Tests"
        F1[XRPC Fuzzer]
        F2[CBOR Fuzzer]
        F3[HTTP Fuzzer]
    end
    
    U1 --> I1
    U2 --> I2
    U3 --> I1
    U4 --> I1
    I1 --> F1
    I2 --> F3
    
    style U1 fill:#bbdefb
    style U2 fill:#bbdefb
    style U3 fill:#bbdefb
    style U4 fill:#bbdefb
    style I1 fill:#ffe0b2
    style I2 fill:#ffe0b2
    style F1 fill:#ffcdd2
    style F2 fill:#ffcdd2
    style F3 fill:#ffcdd2
```

## Code Organization

```mermaid
graph TD
    subgraph "Garazyk/Sources"
        subgraph "App"
            PDS[PDSController]
        end
        
        subgraph "Admin"
            Admin[Admin APIs]
        end
        
        subgraph "Auth"
            JWT[JWT Signing]
            OAuth[OAuth2 Provider]
            Sessions[Session Mgmt]
        end
        
        subgraph "Repository"
            MST[Merkle Search Tree]
            CAR[CAR Encoding]
            Records[Record Ops]
        end
        
        subgraph "Network"
            HTTP[HTTP Server]
            XRPC[XRPC Handler]
            WebSocket[WS Handler]
        end
        
        subgraph "Database"
            SQLite[SQLite Wrapper]
            Migrations[Schema Migrations]
        end
        
        subgraph "Sync"
            Firehose[SubscribeRepos]
            Cursors[Cursor Manager]
        end
        
        subgraph "Blob"
            Storage[Blob Storage]
            Validation[MIME Validation]
        end
        
        subgraph "Identity"
            DID[DID Resolution]
            PLC[PLC Directory]
        end
        
        PDS --> Auth
        PDS --> Repository
        PDS --> Admin
        PDS --> Sync
        
        HTTP --> XRPC
        XRPC --> PDS
        
        Repository --> MST
        Repository --> CAR
        Repository --> Blob
        Repository --> Database
        
        Auth --> JWT
        Auth --> OAuth
        Auth --> Sessions
        
        Sync --> Firehose
        Sync --> Cursors
        
        Identity --> DID
        Identity --> PLC
    end
    
    style PDS fill:#c8e6c9
```

## Debugging Flowchart

```mermaid
flowchart TD
    A([Issue Detected]) --> B[Reproduce locally]
    B --> C{Can reproduce?}
    C -->|No| D[Check environment differences]
    C -->|Yes| E[Read error message]
    E --> F{Error type?}
    F -->|Crash| G[Gather crash logs]
    F -->|Test failure| H[Run failing test with output]
    F -->|Runtime bug| I[Add debug logging]
    
    G --> J[Analyze stack trace]
    H --> K[Check test expectations]
    I --> L[Trace execution path]
    
    J --> M{Found root cause?}
    K --> M
    L --> M
    
    M -->|Yes| N[Implement fix]
    M -->|No| O[Use debugger/step through]
    O --> L
    
    N --> P[Add/update test]
    P --> Q[Run full test suite]
    Q --> R([Done])
    
    style A fill:#c8e6c9
    style R fill:#c8e6c9
    style C fill:#ffe0b2
    style F fill:#ffe0b2
    style M fill:#ffe0b2
    style N fill:#c8e6c9
```

## OAuth2 Authorization Flow

```mermaid
sequenceDiagram
    participant U as User
    participant C as Client App
    participant A as PDS Auth
    participant R as Resource Server
    
    C->>A: Authorization Request<br/>(client_id, scope, state)
    A-->>U: Login & Consent Screen
    U->>A: Approve access
    A-->>C: Authorization Code (redirect)
    
    Note over C,A: Client exchanges code for tokens
    
    C->>A: Token Request<br/>(grant_type=authorization_code)
    A-->>C: {access_token, refresh_token, scope}
    
    Note over C,R: Client protected resource
    
    C->>R accesses: API Request<br/>(Authorization: Bearer token)
    R-->>C: Resource Data
    
    Note over C,R: Access token expires
    
    C->>A: Refresh Token Request<br/>(grant_type=refresh_token)
    A-->>C: {new_access_token}
```

## Database Transaction Flow

```mermaid
flowchart TD
    A[API Request] --> B[Begin Transaction]
    B --> C[Acquire lock on ActorStore]
    C --> D[Perform operations]
    D --> E{All succeed?}
    E -->|No| F[Rollback transaction]
    F --> G[Release lock]
    G --> H[Return error]
    E -->|Yes| I[Commit transaction]
    I --> J[Release lock]
    J --> K[Return success]
    
    style A fill:#bbdefb
    style B fill:#ffe0b2
    style C fill:#ffe0b2
    style D fill:#bbdefb
    style E fill:#ffe0b2
    style F fill:#ffcdd2
    style I fill:#c8e6c9
    style K fill:#c8e6c9
```

## Quick Reference Commands

```mermaid
flowchart LR
    subgraph "Commands"
        G[xcodegen generate] --> B[xcodebuild build]
        B --> T[./build/tests/AllTests]
        G --> F[xcodebuild -scheme Fuzzers build]
    end
    
    subgraph "Quick Tests"
        T1[Unit tests]
        T2[API tests]
        T3[Fuzzers]
    end
    
    B --> T1
    B --> T2
    F --> T3
    
    style G fill:#c8e6c9
    style T fill:#c8e6c9
    style F fill:#c8e6c9
```

## File Structure Overview

```mermaid
graph TD
    root[objpds/]
    
    root --> src[Garazyk/]
    root --> docs[docs/]
    root --> scripts[scripts/]
    root --> config[config files]
    
    src --> app[App/]
    src --> admin[Admin/]
    src --> auth[Auth/]
    src --> repo[Repository/]
    src --> net[Network/]
    src --> db[Database/]
    src --> sync[Sync/]
    src --> blob[Blob/]
    src --> identity[Identity/]
    
    docs --> arch[architecture/]
    docs --> guides[guides/]
    docs --> analysis[analysis/]
    
    scripts --> test[test_*.sh]
    scripts --> build[build_*.sh]
    scripts --> seed[seed_*.py]
    
    style root fill:#c8e6c9
    style src fill:#bbdefb
    style docs fill:#ffe0b2
```

## Related Documentation

### Architecture Documents
- [README.md](README) - Architecture documentation index
- [ARCHITECTURE_ANALYSIS.md](# Architecture analysis) - Component analysis and build system details

### Diagram Documents
- [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) - System overview diagrams
- [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID) - Protocol flow diagrams
- [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) - Diagram selection guide

### Related Guides
- [../guides/DEVELOPER_GUIDE.md](../guides/development/DEVELOPER_GUIDE) - Developer onboarding guide
- [../guides/DEVELOPMENT_WORKFLOWS.md](../guides/DEVELOPMENT_WORKFLOWS) - Duplicate guide version
- [../guides/SETUP_GUIDE.md](../guides/SETUP_GUIDE) - Environment setup guide
