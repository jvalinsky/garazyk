# ATProto PDS Architecture Diagrams

Architecture diagrams and data flow documentation for the ATProto PDS implementation.

## Generated Diagrams

All diagrams are in **Graphviz DOT format**. Install Graphviz to generate PNG/SVG:

```bash
brew install graphviz
```

## Quick Start

Generate all diagrams as PNG:

```bash
cd /Users/jack/Software/objpds/docs/architecture

for dot_file in *.dot; do
    name="${dot_file%.dot}"
    dot -Tpng "$dot_file" -o "${name}.png"
done
```

## Available Diagrams

| Diagram | File | Description |
|---------|------|-------------|
| **High-Level Architecture** | `high_level_architecture.dot` | Complete system overview with all layers |
| **Request Flow** | `request_flow.dot` | HTTP request processing pipeline |
| **Database Schema** | `database_schema.dot` | SQLite schema with relationships |
| **Authentication Flow** | `authentication_flow.dot` | Multi-factor auth process |
| **Repository Engine** | `repository_engine.dot` | MST/CAR content-addressable storage |
| **Firehose & Sync** | `firehose_sync.dot` | Real-time event streaming |
| **Module Dependencies** | `module_dependencies.dot` | Inter-module dependencies |

## Visual Diagram Previews

### 1. High-Level Architecture

```
┌─────────────────┐     ┌─────────────────────────────────────────┐     ┌─────────────┐
│ Client Apps     │     │         ATProto PDS Server              │     │ PLC Server  │
├─────────────────┤     ├─────────────────────────────────────────┤     ├─────────────┤
│ • Bluesky App   │     │  ┌─────────────┐  ┌─────────────────┐  │     │             │
│ • Other Apps    │────▶│  │  Network    │  │  Application    │  │────▶│             │
└─────────────────┘     │  │  Layer      │  │  Layer          │  │     └─────────────┘
                        │  │  • Http     │  │  • PDSController│  │
                        │  │  • XRPC     │  │  • Services     │  │
                        │  │  • WS       │  │  • Auth         │  │
                        │  └─────────────┘  └─────────────────┘  │
                        │         │                  │            │
                        │         ▼                  ▼            │
                        │  ┌──────────────────────────────────────┐│
                        │  │         Repository Engine            │ │
                        │  │  • MST (Merkle Search Tree)          │ │
                        │  │  • CAR (Content Addressable Records) │ │
                        │  │  • CBOR Encoding                     │ │
                        │  └──────────────────────────────────────┘│
                        │         │                  │            │
                        │         ▼                  ▼            │
                        │  ┌──────────────────────────────────────┐│
                        │  │           Data Layer                 │ │
                        │  │  • SQLite Database                   │ │
                        │  │  • ActorStore (Per-user)             │ │
                        │  │  • Connection Pool                   │ │
                        │  └──────────────────────────────────────┘│
                        └─────────────────────────────────────────┘
```

### 2. Request Flow

```
HTTPS Request
      │
      ▼
┌─────────────────┐
│  HttpServer     │  (Port 2583)
│  Route Matching │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│  XrpcHandler    │────▶│  AuthMiddleware │  (JWT Validation)
│  NSID Routing   │     │  Session Check  │
└────────┬────────┘     └────────┬────────┘
         │                       │
         ▼                       ▼
┌─────────────────────────────────────────┐
│           PDSController                  │  (God Class)
│  • AccountService  • RecordService      │
│  • BlobService     • RepositoryService  │
│  • AdminService                          │
└────────┬────────────────────────────────┘
         │
         ▼
┌──────────────┐    ┌─────────────────┐
│ ActorStore   │───▶│  PDSDatabase    │  (SQLite)
│ (Per-user TX)│    │  ConnectionPool │
└──────────────┘    └─────────────────┘
```

### 3. Database Schema

```
┌─────────────┐       ┌─────────────┐       ┌─────────────┐
│   account   │       │    repo     │       │   record    │
├─────────────┤       ├─────────────┤       ├─────────────┤
│ • did (PK)  │◀────┐ │ • did (PK)  │       │ • uri (PK)  │
│ • handle    │     │ │ • rootCid   │       │ • collection│
│ • email     │     └│ • dataCid    │       │ • rkey      │
│ • password  │       └─────────────┘       │ • cid (FK)  │
│ • jwtKeys   │             │               └──────┬──────┘
│ • 2FA       │             │                      │
└─────────────┘             │                      ▼
              ┌─────────────┴─────────────┐    ┌─────────────┐
              │           block           │◀───│    blob     │
              ├───────────────────────────┤    ├─────────────┤
              │ • cid (PK)                │    │ • cid (PK)  │
              │ • data (binary)           │    │ • mimeType  │
              │ • contentType             │    │ • size      │
              └───────────────────────────┘    └─────────────┘
```

### 4. Authentication Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Authentication Flow                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Client Credentials (Handle + Password)                         │
│            │                                                    │
│            ▼                                                    │
│   ┌─────────────────┐                                           │
│   │  AuthController │                                           │
│   └────────┬────────┘                                           │
│            │                                                    │
│    ┌───────┼───────┬─────────┐                                  │
│    │       │       │         │                                  │
│    ▼       ▼       ▼         ▼                                  │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                            │
│ │  JWT │ │OAuth2│ │ TOTP │ │WebAuthn│                           │
│ │(Sign)│ │(Auth)│ │(2FA) │ │(Passkeys)│                         │
│ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘                            │
│    │        │       │         │                                 │
│    └────────┴───────┴─────────┘                                 │
│            │                                                    │
│            ▼                                                    │
│   ┌─────────────────────────────────────┐                      │
│   │        Database (Session Store)      │                      │
│   └─────────────────────────────────────┘                      │
│            │                                                    │
│            ▼                                                    │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │  Output Tokens                                          │  │
│   │  • Access Token (JWT, 15min)                           │  │
│   │  • Refresh Token (JWT, 30days)                         │  │
│   │  • DID Token (Signed DID Doc)                          │  │
│   └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Repository Engine (MST + CAR)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Repository Engine                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    User Repository                          │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │ │
│  │  │    MST       │  │    CAR       │  │  Data Model      │  │ │
│  │  │  Merkle      │  │  Archive     │  │  • Records       │  │ │
│  │  │  Search      │  │  (Binary)    │  │  • Collections   │  │ │
│  │  │  Tree        │  │              │  │  • Keys (rkey)   │  │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────────────────┘  │ │
│  └─────────┼─────────────────┼───────────────────────────────────┘ │
│            │                 │                                    │
│            ▼                 ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Operations                              │ │
│  │  • getRecord(key) → CID → Block → CBOR → JSON             │ │
│  │  • putRecord(key, value) → CBOR → Block → CID → Update MST│ │
│  │  • deleteRecord(key) → Prune MST → Update Root CID        │ │
│  │  • exportCAR() → Serialize all blocks to binary           │ │
│  │  • importCAR() → Parse blocks → Rebuild MST               │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 6. Firehose & Sync

```
┌─────────────────────────────────────────────────────────────────┐
│                    Firehose & Sync                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Local Write  │  │ Import CAR   │  │ Admin Action │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              SubscribeReposHandler                          │ │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────────────────┐   │ │
│  │  │  Event    │  │  Stream   │  │  Cursor Manager       │   │ │
│  │  │  Encoder  │  │  Manager  │  │  (Event positions)    │   │ │
│  │  │(CBOR/JSON)│  │(WebSocket)│  │                       │   │ │
│  │  └───────────┘  └───────────┘  └───────────────────────┘   │ │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      Subscribers                            │ │
│  │  ┌─────────┐  ┌───────────┐  ┌─────────────────┐          │ │
│  │  │AppView  │  │ Relay PDS │  │ Third Party     │          │ │
│  │  │(Bsky)   │  │(Federa-   │  │ (Apps, Services)│          │ │
│  │  │         │  │  tion)    │  │                 │          │ │
│  │  └─────────┘  └───────────┘  └─────────────────┘          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Event Types: #commit, #handle, #account, #tombstone            │
└─────────────────────────────────────────────────────────────────┘
```

### 7. Module Dependencies

```
                    ┌─────────────────────────────────────────┐
                    │           Foundation Layer              │
                    │  ┌──────────┐  ┌──────────┐  ┌───────┐ │
                    │  │Foundation│  │ Security │  │Network│ │
                    │  └────┬─────┘  └────┬─────┘  └───┬───┘ │
                    └───────┼─────────────┼────────────┘     │
                            │            │                   │
                            ▼            ▼                   ▼
                    ┌─────────────────────────────────────────────┐
                    │              External Dependencies          │
                    │  ┌──────────┐  ┌───────────────────────┐   │
                    │  │ SQLite3  │  │ secp256k1 (ECC)       │   │
                    │  └──────────┘  └───────────────────────┘   │
                    └───────────────────┬─────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Core Modules                                    │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────────┐  │
│  │ Identity │ ──▶│   Core   │ ◀──│   Auth   │ ◀──│      Security        │  │
│  │(DID/Hndl)│    │(CID/DID) │    │(JWT/OAuth│    │(SQLi, Authz)         │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────────────────┘  │
│         │            │              │                  │                     │
│         │            ▼              ▼                  ▼                     │
│         │    ┌────────────────────────────────────────────────────────────┐ │
│         │    │                   Repository Layer                         │ │
│         │    │  ┌──────────┐    ┌──────────┐    ┌──────────────────────┐ │ │
│         └───▶│  │Repository│ ◀──│   MST    │ ◀──│   CAR Archive        │ │ │
│              │  │(Records) │    │(Merkle)  │    │(Content Addressable) │ │ │
│              │  └──────────┘    └──────────┘    └──────────────────────┘ │ │
│              │         │                                       │          │ │
│              │         ▼                                       ▼          │ │
│              │    ┌────────────────────────────────────────────────────┐ │ │
│              │    │                  Blob Layer                        │ │ │
│              │    │  ┌──────────────────────────────────────────────┐ │ │ │
│              │    │  │                   Blob                       │ │ │ │
│              │    │  │  (Binary storage, MIME validation, sizing)   │ │ │ │
│              │    │  └──────────────────────────────────────────────┘ │ │ │
│              │    └─────────────────────────┬────────────────────────┘ │ │
│              └──────────────────────────────┼──────────────────────────┘ │
│                                             │                              │
│                                             ▼                              │
│              ┌───────────────────────────────────────────────────────────┐│
│              │                    Database Layer                          ││
│              │  ┌──────────────────────────────────────────────────────┐ ││
│              │  │                  PDSDatabase                         │ ││
│              │  │  (Connection pool, transactions, CRUD operations)    │ ││
│              │  └─────────────────────────┬────────────────────────────┘ ││
│              └────────────────────────────┼──────────────────────────────┘│
│                                            │                               │
│                                            ▼                               │
│              ┌───────────────────────────────────────────────────────────┐│
│              │                   Application Layer                        ││
│              │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐││
│              │  │  App   │ │ AppView│ │ Admin  │ │ Sync   │ │Federation│││
│              │  │(Main)  │ │(Bsky)  │ │(Mod)   │ │(Fireh.)│ │(Relay)   │││
│              │  └────────┘ └────────┘ └────────┘ └────────┘ └──────────┘││
│              └─────────────────────────┬─────────────────────────────────┘│
│                                        │                                   │
│                                        ▼                                   │
│              ┌───────────────────────────────────────────────────────────┐│
│              │                    CLI Layer                              ││
│              │  ┌──────────────────────────────────────────────────────┐ ││
│              │  │                     CLI                              │ ││
│              │  │  (atprotopds-cli: serve, health, account management) │ ││
│              │  └──────────────────────────────────────────────────────┘ ││
│              └───────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

## Detailed Documentation

See `ARCHITECTURE_ANALYSIS.md` for:
- Complete component descriptions
- Design patterns used
- Data flow examples
- Security model
- Performance considerations
- Refactoring recommendations

## Quick Navigation

- **[Full Analysis](ARCHITECTURE_ANALYSIS.md)** - Component descriptions, data flows, and security model
- **[Mermaid Diagrams](ARCHITECTURE_DIAGRAMS.md)** - Visual system overview
- **[Mermaid Diagrams Extended](DIAGRAMS_MERMAID.md)** - ATProto protocols & models
- **[Development Workflows](docs/guides/DEVELOPMENT_WORKFLOWS.md)** - Dev process diagrams
- **[XRPC Protocol Reference](docs/guides/XRPC_PROTOCOL_REFERENCE.md)** - Protocol quick reference
- **[Diagram Quick Reference](DIAGRAM_QUICK_REFERENCE.md)** - All diagrams index
- **[Data Models](atproto_data_models.md)** - ATProto data model details
- **[Objective-C Implementation Patterns](docs/guides/objective_c_tips.md)** - Advanced GCD, SQLite, and Networking patterns used in this project

## Key Insights

1. **Layered Architecture**: Clear separation from Foundation → Core → Application
2. **Central Coordinator**: `PDSController` acts as a facade for all operations
3. **Content-Addressable Storage**: MST + CAR ensures data integrity
4. **Real-time Sync**: WebSocket firehose enables live updates
5. **Multi-Factor Auth**: JWT + TOTP + WebAuthn for secure authentication
6. **Protocol Compliant**: Complete XRPC implementation for AT Protocol

## File Locations

```
objpds/
├── docs/architecture/
│   ├── README.md                    ← You are here
│   ├── ARCHITECTURE_ANALYSIS.md     ← Full documentation
│   ├── high_level_architecture.dot  ← System overview
│   ├── request_flow.dot             ← Request pipeline
│   ├── database_schema.dot          ← SQLite schema
│   ├── authentication_flow.dot      ← Auth process
│   ├── repository_engine.dot        ← MST/CAR engine
│   ├── firehose_sync.dot            ← Real-time sync
│   └── module_dependencies.dot      ← Dependency graph
└── ATProtoPDS/Sources/
    ├── App/PDSController.h/m        ← Central coordinator
    ├── Database/PDSDatabase.h/m     ← Database layer
    ├── Repository/MST.h/m           ← Merkle Search Tree
    ├── Network/XrpcHandler.h/m      ← XRPC dispatcher
    └── Sync/SubscribeReposHandler.h/m ← Firehose handler
```
