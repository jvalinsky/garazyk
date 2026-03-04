---
title: Architecture Documentation
---

# Architecture Documentation

Comprehensive architecture documentation for the ATProto PDS implementation, including system diagrams, data models, protocol references, and development workflows.

## Documentation Index

### Markdown Documents

| File | Title | Topic |
|------|-------|-------|
| [ARCHITECTURE_ANALYSIS.md](# Architecture analysis) | ATProto PDS Deep Code Analysis | System overview, component analysis, design patterns, data flows, security model, performance considerations, and refactoring recommendations |
| [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) | ATProto PDS Architecture Diagrams | Mermaid diagrams for system overview, OpenAPI generation, API endpoints, data flows, and component dependencies |
| [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID) | ATProto PDS Mermaid Diagrams | XRPC request flow, record creation protocol, data models, OAuth2 token flow, session management, WebSocket firehose, and blob storage |
| [atproto_data_models.md](atproto_data_models) | atproto Data Models Research | DID implementation, repository structure (MST), Lexicon schemas, record types, commit/signature verification, AT URI resolution, collections, and sync protocols |
| [atproto_pds_architecture.md](atproto_pds_architecture) | AT Protocol PDS Architecture and Specifications | PDS role in ecosystem, XRPC API endpoints, OAuth 2.1 authentication, data storage requirements, repository structure, event stream/firehose, and existing implementations |
| [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS) | Development Workflow Diagrams | Build/run process, test pyramid, code organization, debugging flowcharts, OAuth2 flow, database transactions, and quick reference commands |
| [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) | Diagram Quick Reference | Condensed guide to all diagrams with use-case mapping, color legend, and common Mermaid patterns |
| [XRPC_PROTOCOL_REFERENCE.md](XRPC_PROTOCOL_REFERENCE) | ATProto XRPC Protocol Reference | NSID naming, method patterns, Lexicon NSIDs, data types, error codes, and curl command examples |
| [2026-01-10-integration-test-findings.md](2026-01-10-integration-test-findings) | PDS Integration Test Results | Integration test findings, token format analysis, getRecord issues, CID format compliance, and resolved issues |

### Graphviz Diagrams (.dot files)

Generate PNGs with: `dot -Tpng <file>.dot -o <file>.png`

| File | Description |
|------|-------------|
| [high_level_architecture.dot](# Diagram: high_level_architecture.dot) | Complete system overview with all layers (client, network, application, repository, data) |
| [request_flow.dot](# Diagram: request_flow.dot) | HTTP request processing pipeline from server to database |
| [database_schema.dot](# Diagram: database_schema.dot) | SQLite schema with entity relationships |
| [authentication_flow.dot](# Diagram: authentication_flow.dot) | Multi-factor authentication process (JWT, OAuth2, TOTP, WebAuthn) |
| [repository_engine.dot](# Diagram: repository_engine.dot) | MST and CAR content-addressable storage engine |
| [firehose_sync.dot](# Diagram: firehose_sync.dot) | Real-time event streaming and WebSocket subscriptions |
| [module_dependencies.dot](# Diagram: module_dependencies.dot) | Inter-module dependency graph from Foundation to CLI |

## Quick Navigation by Task

### Understanding the System
1. [ARCHITECTURE_ANALYSIS.md](# Architecture analysis) - Start here for comprehensive overview
2. [high_level_architecture.dot](# Diagram: high_level_architecture.dot) - Visual system structure
3. [module_dependencies.dot](# Diagram: module_dependencies.dot) - Module relationships

### ATProto Protocol Development
1. [atproto_pds_architecture.md](atproto_pds_architecture) - PDS specifications
2. [atproto_data_models.md](atproto_data_models) - Data structures and models
3. [XRPC_PROTOCOL_REFERENCE.md](XRPC_PROTOCOL_REFERENCE) - Quick protocol reference

### Development Workflows
1. [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS) - Build, test, debug processes
2. [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) - Diagram selection guide

### Authentication & Security
1. [authentication_flow.dot](# Diagram: authentication_flow.dot) - Auth flow diagram
2. [atproto_pds_architecture.md](atproto_pds_architecture#3-authentication-and-authorization-mechanisms) - OAuth 2.1 profile

### Database & Storage
1. [database_schema.dot](# Diagram: database_schema.dot) - Schema relationships
2. [repository_engine.dot](# Diagram: repository_engine.dot) - MST/CAR storage

## Related Documentation

### Architecture Documents
| File | Description |
|------|-------------|
| [ARCHITECTURE_ANALYSIS.md](# Architecture analysis) | Deep code analysis, component details, and design patterns |
| [atproto_pds_architecture.md](atproto_pds_architecture) | PDS specifications, XRPC endpoints, and OAuth 2.1 profile |
| [atproto_data_models.md](atproto_data_models) | DID implementation, MST, Lexicon schemas, and CBOR encoding |
| [XRPC_PROTOCOL_REFERENCE.md](XRPC_PROTOCOL_REFERENCE) | Quick reference for XRPC methods and error codes |
| [DEVELOPMENT_WORKFLOWS.md](DEVELOPMENT_WORKFLOWS) | Build/test/debug workflow diagrams |

### Diagram Documents
| File | Description |
|------|-------------|
| [ARCHITECTURE_DIAGRAMS.md](ARCHITECTURE_DIAGRAMS) | System overview and component diagrams |
| [DIAGRAMS_MERMAID.md](DIAGRAMS_MERMAID) | Protocol flows and data model diagrams |
| [DIAGRAM_QUICK_REFERENCE.md](DIAGRAM_QUICK_REFERENCE) | Guide to selecting the right diagram |

### Other Directories
| Directory | Description |
|-----------|-------------|
| <!-- Link placeholder: ../guides/ --> | Development guides, Objective-C patterns, and how-to documentation |
| <!-- Link placeholder: ../security/ --> | Security documentation, audit skills, and hardening guides |
| <!-- Link placeholder: ../tests/ --> | Test documentation and coverage reports |
| <!-- Link placeholder: ../plans/ --> | Implementation plans and project roadmaps |
| <!-- Link placeholder: ../examples/ --> | Example code and usage patterns |

## Key Architecture Insights

1. **Layered Architecture**: Clear separation from Foundation → Core → Application
2. **Central Coordinator**: `PDSController` acts as a facade for all operations
3. **Content-Addressable Storage**: MST + CAR ensures cryptographic data integrity
4. **Real-time Sync**: WebSocket firehose enables live updates across federation
5. **Multi-Factor Auth**: JWT + OAuth2 + TOTP + WebAuthn for secure authentication
6. **Protocol Compliant**: Complete XRPC implementation for AT Protocol
