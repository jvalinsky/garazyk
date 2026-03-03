# Phase 0 Implementation Plan: Core Repository Features

## Overview

Phase 0 implements core repository functionality required for basic PDS operations. This phase covers advanced CRUD operations, bulk processing, and performance optimization.

## 0.1 Advanced Repository Operations

### 0.1.1 applyWrites Implementation
**Endpoint**: `com.atproto.repo.applyWrites`
**Priority**: P0 | **Complexity**: High | **Risk**: Medium

#### Requirements
- Accept array of write operations (create, update, delete)
- Atomic transaction processing
- Proper error handling and rollback
- Optimistic concurrency control with sequence numbers

#### Implementation Steps
1. **API Handler** (`XrpcMethodRegistry.m`):
   ```objc
   [dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
       // Parse writes array, validate permissions, execute in transaction
   }];
   ```

2. **Controller Method** (`PDSController.m`):
   ```objc
   - (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                 repo:(NSString *)repo
                               error:(NSError **)error;
   ```

3. **Database Transaction** (`PDSDatabase.m`):
   - Batch insert/update/delete operations
   - Foreign key constraint handling
   - Rollback on partial failures

4. **Validation Logic**:
   - Record schema validation
   - Permission checks per operation
   - Reference integrity

#### Testing
- Unit tests for transaction safety
- Integration tests for batch operations
- Error handling edge cases

### 0.1.2 putRecord Implementation
**Endpoint**: `com.atproto.repo.putRecord`
**Priority**: P0 | **Complexity**: Medium | **Risk**: Low

#### Requirements
- Update existing records by URI
- Handle record versioning
- Validate record structure

#### Implementation
1. Parse record URI to extract collection/rkey
2. Load existing record for comparison
3. Update record with new data
4. Update repository MST

### 0.1.3 Bulk Operations Support
**Priority**: P1 | **Complexity**: Medium | **Risk**: Medium

#### Features
- Multiple record operations in single request
- Batch processing with progress callbacks
- Progress reporting for large operations

## 0.2 Query & Search Improvements

### 0.2.1 describeRepo Implementation
**Endpoint**: `com.atproto.repo.describeRepo`
**Priority**: P0 | **Complexity**: Low | **Risk**: Low

#### Response Format
```json
{
  "did": "did:web:user.example.com",
  "collections": {
    "app.bsky.feed.post": {
      "count": 42
    },
    "app.bsky.feed.like": {
      "count": 156
    }
  },
  "handle": "user.example.com",
  "didDoc": { /* DID document */ }
}
```

#### Implementation
1. Query database for collection counts
2. Fetch current DID document
3. Aggregate repository statistics

### 0.2.2 listRecords Pagination
**Priority**: P0 | **Complexity**: Medium | **Risk**: Low

#### Improvements
- Cursor-based pagination with TID ordering
- Reverse chronological ordering
- Proper limit enforcement (max 100)

#### Database Optimization
```sql
CREATE INDEX idx_records_collection_created ON records(collection, created_at DESC);
```

### 0.2.3 Record Validation
**Priority**: P0 | **Complexity**: Medium | **Risk**: Medium

#### Features
- Lexicon schema validation
- Record size limits
- Content type verification

## 0.3 Repository Import/Export

### 0.3.1 CAR Import Implementation
**Endpoint**: `com.atproto.sync.importRepo`
**Priority**: P1 | **Complexity**: High | **Risk**: High

#### Requirements
- Parse CAR file format
- Validate repository structure
- Merge with existing repository
- Conflict resolution

#### Implementation
1. **CAR Parser**: Extend existing CAR.m with import functionality
2. **Repository Merger**: Handle MST merging and conflict resolution
3. **Validation**: Verify all blocks and references

### 0.3.2 CAR Export Improvements
**Priority**: P1 | **Complexity**: Medium | **Risk**: Low

#### Features
- Incremental exports (since specific commit)
- Compression options
- Streaming for large repositories

## 0.4 Performance Optimizations

### 0.4.1 Database Indexing
**Priority**: P0 | **Complexity**: Low | **Risk**: Low

#### Required Indexes
```sql
-- Records table
CREATE INDEX idx_records_repo_collection_rkey ON records(repo_did, collection, rkey);
CREATE INDEX idx_records_repo_created ON records(repo_did, created_at DESC);

-- Blocks table
CREATE INDEX idx_blocks_repo_cid ON blocks(repo_did, cid);

-- Accounts table
CREATE INDEX idx_accounts_handle ON accounts(handle);
CREATE INDEX idx_accounts_created ON accounts(created_at);
```

### 0.4.2 Query Optimization
**Priority**: P0 | **Complexity**: Medium | **Risk**: Low

#### Improvements
- Prepared statements caching
- Connection pooling
- Query result pagination
- Row-by-row result processing to avoid large allocations

### 0.4.3 Caching Layer
**Priority**: P1 | **Complexity**: Medium | **Risk**: Medium

#### Features
- DID document caching
- Record metadata caching
- Repository statistics caching
- Cache invalidation on updates

## 0.5 Error Handling & Validation

### 0.5.1 Standardized Error Responses
**Priority**: P0 | **Complexity**: Low | **Risk**: Low

#### Error Format
```json
{
  "error": "InvalidRequest",
  "message": "Record validation failed",
  "details": {
    "field": "text",
    "issue": "exceeds maximum length"
  }
}
```

### 0.5.2 Input Validation
**Priority**: P0 | **Complexity**: Medium | **Risk**: Low

#### Validation Rules
- DID format validation
- Record size limits (100KB)
- Collection name restrictions
- RKey format validation

### 0.5.3 Rate Limiting
**Priority**: P1 | **Complexity**: Medium | **Risk**: Medium

#### Implementation
- Token bucket algorithm
- Per-user limits
- Configurable thresholds
- Proper error responses

## Technical Implementation Notes

### Database Schema Updates
```sql
-- Add sequence numbers for optimistic concurrency
ALTER TABLE records ADD COLUMN seq INTEGER DEFAULT 0;

-- Add indexes for performance
CREATE INDEX idx_records_seq ON records(repo_did, seq);
CREATE INDEX idx_records_updated ON records(repo_did, updated_at DESC);
```

### API Handler Pattern
```objc
[dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
    NSDictionary *body = request.jsonBody;
    NSString *repo = body[@"repo"];
    NSArray *writes = body[@"writes"];

    // Validate authentication
    // Execute writes in transaction
    // Return results or errors
}];
```

### Testing Strategy
- **Unit Tests**: Individual component testing
- **Integration Tests**: End-to-end API testing
- **Performance Tests**: Load testing and benchmarks
- **Edge Case Tests**: Error conditions and boundary cases

## Success Criteria

### Functional Requirements
- All basic repository operations working
- Proper error handling and validation
- Pagination with TID cursors
- CAR import/export functionality

### Performance Requirements
- <100ms average response time
- <10MB memory usage for typical operations
- Proper database connection pooling
- Query execution with prepared statements

### Quality Requirements
- >90% test coverage
- Error handling with rollback on failure
- Proper logging and monitoring
- Backward API compatibility

## Dependencies
- Current blob storage implementation (Complete)
- Basic authentication system (Complete)
- Core repository operations (Complete)
- Database schema stability

## Risk Assessment
- **High Risk**: CAR import/export (complex binary formats)
- **Medium Risk**: Transaction handling (concurrency issues)
- **Low Risk**: Query optimization (well-understood patterns)

## Timeline Estimate
- **Week 1-2**: Repository operations (applyWrites, putRecord)
- **Week 3**: Query improvements and pagination
- **Week 4**: Performance optimization and testing
- **Week 5-6**: CAR import/export and advanced features

This Phase 0 plan provides foundation for production-ready PDS core functionality.

---

## Related Documentation

- [Archive Index](./README.md) - Index of all archived plans
- [Current Plans](../README.md) - Active implementation plans
- [Architecture Docs](../../architecture/README.md) - System architecture documentation