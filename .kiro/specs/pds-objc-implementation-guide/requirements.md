# PDS Objective-C Implementation Guide — Requirements

## Overview

Create a comprehensive, production-ready documentation guide that enables developers to understand and implement an ATProto Personal Data Server (PDS) in Objective-C from scratch. The guide must bridge the gap between high-level architecture concepts and practical implementation details.

## User Stories

### US-1: Developer Onboarding
As a new developer joining the project, I want a clear introduction to PDS architecture so that I can understand how components fit together.

**Acceptance Criteria:**
- Getting started section explains what a PDS is and why Objective-C
- High-level architecture diagram shows all major components
- Setup instructions work on both macOS and Linux/GNUstep
- Estimated time to first successful build: < 30 minutes

### US-2: Core Concepts Understanding
As a developer, I want to understand AT Protocol fundamentals so that I can implement protocol-compliant features.

**Acceptance Criteria:**
- DID and NSID concepts explained with examples
- DAG-CBOR serialization documented with code examples
- Merkle Search Tree (MST) structure and operations explained
- Cryptography (JWT, DPoP, ECDSA P-256) documented
- Each concept includes visual diagrams

### US-3: Application Layer Implementation
As a developer, I want to understand the service layer architecture so that I can add new features correctly.

**Acceptance Criteria:**
- PDSApplication facade documented with initialization flow
- Each service (Account, Record, Blob, Repository, Admin, Relay) has dedicated documentation
- Service responsibilities clearly defined
- Service interaction patterns documented
- Code examples show typical usage

### US-4: Network Layer Implementation
As a developer, I want to understand XRPC routing and method registration so that I can add new endpoints.

**Acceptance Criteria:**
- HTTP server setup documented
- XRPC dispatcher routing logic explained
- XrpcMethodRegistry pattern documented
- Domain-specific method handler pattern shown
- Auth verification flow documented
- Error handling standardization explained

### US-5: Database Layer Implementation
As a developer, I want to understand database architecture so that I can implement data persistence correctly.

**Acceptance Criteria:**
- SQLite architecture and design patterns documented
- Service database (shared) vs actor databases (per-user) explained
- Database pool management documented
- Migration strategy documented
- WAL mode benefits and usage explained
- Transaction handling patterns shown

### US-6: Authentication Implementation
As a developer, I want to understand authentication mechanisms so that I can implement secure token handling.

**Acceptance Criteria:**
- JWT token generation and verification documented
- OAuth 2.0 with DPoP flow documented
- Key rotation strategy documented
- TOTP and WebAuthn support documented
- Token refresh flow documented
- Security best practices included

### US-7: Repository and Protocol Implementation
As a developer, I want to understand repository structure and protocol details so that I can implement record operations correctly.

**Acceptance Criteria:**
- Repository structure documented
- CBOR serialization patterns shown
- CAR format explained with examples
- Content addressing (CID) documented
- Blob storage and retrieval documented
- MST commit processing explained

### US-8: Firehose and Sync Implementation
As a developer, I want to understand the firehose (subscribeRepos) so that I can implement real-time sync.

**Acceptance Criteria:**
- WebSocket server setup documented
- subscribeRepos endpoint implementation shown
- Commit broadcasting mechanism explained
- Backpressure and flow control documented
- Event streaming patterns shown

### US-9: Platform Compatibility
As a developer, I want to understand platform-specific considerations so that I can write cross-platform code.

**Acceptance Criteria:**
- macOS vs GNUstep differences documented
- Compatibility layer usage explained
- Platform-specific network I/O documented
- ARC runtime considerations explained
- Conditional compilation patterns shown

### US-10: Step-by-Step Tutorials
As a developer, I want hands-on tutorials so that I can learn by doing.

**Acceptance Criteria:**
- Tutorial 1: Minimal PDS with single endpoint
- Tutorial 2: Account creation and management
- Tutorial 3: Record CRUD operations
- Tutorial 4: OAuth and JWT integration
- Tutorial 5: WebSocket firehose implementation
- Tutorial 6: Production deployment
- Each tutorial is self-contained and runnable

### US-11: Reference Documentation
As a developer, I want comprehensive reference docs so that I can look up specific details.

**Acceptance Criteria:**
- Complete XRPC endpoint reference
- Configuration options documented
- CLI command reference (kaszlak)
- Troubleshooting guide with common issues
- Performance tuning guide

### US-12: Visual Diagrams
As a developer, I want visual representations so that I can understand complex flows quickly.

**Acceptance Criteria:**
- System architecture diagram
- Request flow diagram
- Database schema diagram
- Authentication flow diagram
- Firehose event flow diagram
- All diagrams are clear and labeled

## Functional Requirements

### FR-1: Documentation Structure
- Organize content into 12 progressive sections
- Each section builds on previous knowledge
- Clear navigation between sections
- Table of contents with links

### FR-2: Code Examples
- All examples extracted from actual codebase
- Examples are tested and working
- Examples include line references to source
- Examples progress from simple to complex
- Examples show both happy path and error handling

### FR-3: Architecture Diagrams
- System architecture showing all components
- Request flow from client to database
- Database schema and relationships
- Authentication flow (JWT, OAuth, DPoP)
- Firehose event broadcasting flow

### FR-4: Tutorial Implementation
- Each tutorial has clear learning objectives
- Tutorials are self-contained
- Tutorials include working code
- Tutorials show expected output
- Tutorials include troubleshooting tips

### FR-5: Reference Documentation
- XRPC endpoint reference with parameters
- Configuration file reference
- CLI command reference
- Error codes and meanings
- Performance tuning recommendations

### FR-6: Platform-Specific Guidance
- macOS-specific setup instructions
- Linux/GNUstep-specific setup instructions
- Platform differences clearly marked
- Compatibility layer usage documented
- Platform-specific code examples

## Non-Functional Requirements

### NFR-1: Maintainability
- Documentation must be easy to update
- Code examples must be linked to source (not copied)
- Diagrams must be in editable format (SVG)
- Documentation must version with releases

### NFR-2: Clarity
- Technical concepts explained in plain language
- Jargon defined on first use
- Examples before complex theory
- Visual aids for complex concepts

### NFR-3: Completeness
- All major components documented
- All XRPC endpoints covered
- All services explained
- All authentication mechanisms covered
- All database operations documented

### NFR-4: Accessibility
- Diagrams include text descriptions
- Code examples have syntax highlighting
- Content is searchable
- Mobile-friendly layout

### NFR-5: Performance
- Documentation loads quickly
- Diagrams render efficiently
- Search is responsive
- No external dependencies for core content

## Correctness Properties

### CP-1: Architectural Accuracy
The documentation accurately represents the actual codebase architecture. All diagrams and descriptions must match the current implementation.

### CP-2: Code Example Correctness
All code examples must compile and run without modification. Examples must follow the actual patterns used in the codebase.

### CP-3: Completeness of Coverage
All major components (services, handlers, database operations) must have documentation and examples.

### CP-4: Consistency
Terminology, naming conventions, and patterns must be consistent throughout the documentation.

### CP-5: Up-to-Date Information
Documentation must be updated when code changes. Version numbers and API details must be current.

## Constraints

- Documentation must work for both macOS and Linux/GNUstep developers
- Examples must use Objective-C (no Swift)
- Documentation must be self-contained (no external dependencies)
- Diagrams must be in SVG or Mermaid format
- Documentation must be version-controlled with code
