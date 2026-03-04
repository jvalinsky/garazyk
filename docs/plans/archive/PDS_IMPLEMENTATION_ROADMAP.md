---
title: ATProto PDS Implementation Roadmap
---

# ATProto PDS Implementation Roadmap

## Overview

This roadmap defines the remaining features required to transform the current ATProto PDS implementation into a production-ready Personal Data Server. The implementation is structured in 4 phases with defined priorities, dependencies, and success criteria.

**Current Status**: Basic PDS with authentication, repository operations, and blob storage
**Target**: Production-grade PDS with federation, moderation, and enterprise features

---

## Phase 0: Core Repository & Performance
**Priority**: HIGH | **Timeline**: 4-6 weeks | **Risk**: Medium | **Dependencies**: Current blob storage

### 0.1 Advanced Repository Operations
- **applyWrites** (`com.atproto.repo.applyWrites`)
  - Batch record operations (create, update, delete)
  - Transaction safety and rollback
  - Optimistic concurrency control
- **putRecord** (`com.atproto.repo.putRecord`)
  - Update existing records
  - Version conflict resolution
- **batch operations** for multiple records

### 0.2 Query & Search Improvements
- **describeRepo** (`com.atproto.repo.describeRepo`)
  - Repository metadata and statistics
  - Collection counts and size information
- **listRecords** pagination improvements
  - Cursor-based pagination
  - Indexed database queries
- **searchPosts** basic implementation (optional)

### 0.3 Repository Import/Export
- **importRepo** (`com.atproto.sync.importRepo`)
  - CAR file import with validation
  - Repository state synchronization
- **export CAR** improvements
  - Incremental exports
  - Compression and streaming

### 0.4 Performance Optimizations
- **Database indexing** improvements
  - Composite indexes for common queries
  - Query plan optimization
- **Connection pooling** for SQLite
- **Request caching** for frequently accessed data
- **Memory management** for large repositories

### 0.5 Error Handling & Validation
- **Error codes** (per ATProto spec)
- **Input validation** improvements
- **Rate limiting** basic implementation
- **Request logging** and monitoring

---

## Phase 1: Advanced Sync & Federation
**Priority**: HIGH | **Timeline**: 6-8 weeks | **Risk**: High | **Dependencies**: Phase 0

### 1.1 Firehose & Event Streaming
- **subscribeRepos** (`com.atproto.sync.subscribeRepos`)
  - WebSocket-based event streaming
  - Real-time repository change notifications
  - Event filtering and cursor management
- **Firehose client** implementation
  - Connect to upstream relays
  - Event processing and storage

### 1.2 Relay Integration
- **Relay discovery** and connection
  - Bootstrap peer discovery
  - Relay selection algorithms
- **Event forwarding** to relays
  - Repository change broadcasting
  - Conflict resolution
- **Relay synchronization**
  - State synchronization
  - Event replay capabilities

### 1.3 Federation Features
- **DID document resolution** improvements
  - PLC directory integration
  - DID caching and validation
- **Cross-PDS communication**
  - Remote repository access
  - Federated identity verification
- **Network partitioning** handling

### 1.4 Sync Protocol Improvements
- **getLatestCommit** (`com.atproto.sync.getLatestCommit`)
- **getBlocks** for  sync
- **Merkle tree** optimizations
- **Delta synchronization**

---

## Phase 2: Moderation & Safety
**Priority**: MEDIUM | **Timeline**: 8-12 weeks | **Risk**: Medium | **Dependencies**: Phase 1

### 2.1 Content Moderation
- **Moderation reporting** (`com.atproto.moderation.*`)
  - Report creation and management
  - Appeal processes
- **Labeling system** (`com.atproto.label.*`)
  - Content labeling and filtering
  - Label subscription management

### 2.2 Account Management
- **Account status** management
  - Deactivation/reactivation
  - Account deletion workflows
- **Email verification** improvements
- **Password policies** and security

### 2.3 Privacy & Consent
- **Data export** (`com.atproto.sync.getRepo` improvements)
- **Account migration** support
- **Data retention** policies
- **Privacy controls**

### 2.4 Safety Features
- **Rate limiting** advanced implementation
- **Spam detection** basic algorithms
- **Abuse prevention** measures
- **Content filtering** at ingestion

---

## Phase 3: Enterprise & Admin Features
**Priority**: LOW | **Timeline**: 12-16 weeks | **Risk**: Medium | **Dependencies**: Phase 2

### 3.1 Administration Tools
- **Admin API** (`com.atproto.admin.*`)
  - User management
  - Content moderation tools
  - System configuration
- **Metrics and monitoring**
  - Prometheus integration
  - Health check endpoints
  - Performance dashboards

### 3.2 Scalability Features
- **Database sharding** support
- **CDN integration** for blobs
- **Load balancing** configuration
- **Horizontal scaling** capabilities

### 3.3 Compliance & Audit
- **Audit logging** 
- **Data retention** compliance
- **GDPR compliance** features
- **Legal hold** capabilities

### 3.4 Advanced Security
- **OAuth 2.0** full implementation
- **JWT improvements** with proper signing
- **API key management**
- **Multi-factor authentication**

---

## Implementation Details

### Priority Classification
- **P0 (Critical)**: Blocks basic functionality
- **P1 (High)**: Core user experience features
- **P2 (Medium)**: Important but not blocking
- **P3 (Low)**: Nice-to-have enterprise features

### Success Criteria
- **Phase 0**: Full repository CRUD operations with good performance
- **Phase 1**: Real-time sync and basic federation
- **Phase 2**: Safe, moderated platform for users
- **Phase 3**: Enterprise-grade reliability and features

### Technical Considerations
- **Backward Compatibility**: Maintain API compatibility
- **Performance Benchmarks**: Target <100ms for common operations
- **Testing Coverage**: >90% code coverage,  integration tests
- **Security Review**: External security audit before production

### Risk Mitigation
- **Incremental Deployment**: Each phase can be deployed independently
- **Feature Flags**: Enable/disable features without redeployment
- **Rollback Plans**: Clear rollback procedures for each phase
- **Monitoring**: os_log integration with structured logging

---

## Implementation Schedule

### Week 1: Immediate Actions
- Complete Phase 0.1 repository operations
- Implement testing framework
- Set up CI/CD pipeline with automated testing

### Weeks 2-4: Short-term Goals
- Complete Phase 0 features
- Begin Phase 1 sync protocol implementation
- Performance optimization and benchmarking

### Weeks 5-12: Medium-term Goals
- Complete Phases 1 & 2
- Security hardening and compliance
- Production deployment preparation

### Weeks 13+: Long-term Objectives
- Enterprise features and scaling
- Advanced moderation and safety
- Ecosystem integration and partnerships

This roadmap provides a structured path to production-ready ATProto PDS implementation with realistic timelines and controlled risk exposure.

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation