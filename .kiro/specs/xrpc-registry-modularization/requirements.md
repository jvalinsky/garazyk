# Requirements Document

## Introduction

This document specifies requirements for refactoring the XrpcMethodRegistry.m monolith (6,308 lines) into domain-specific modules. The refactoring addresses code duplication, maintainability issues, and testing complexity while preserving all existing functionality. This is Batch 5 from the refactor plan in docs/refactor-plan-2026-02-24.md, following completion of Batches 1-4 (spec compliance fixes).

## Glossary

- **XrpcMethodRegistry**: The current monolithic class responsible for registering all XRPC endpoint handlers
- **XRPC**: The RPC protocol used by AT Protocol for client-server communication
- **Domain Module**: A focused module handling endpoints for a specific AT Protocol namespace (e.g., com.atproto.server, com.atproto.repo)
- **Helper Module**: A shared utility module providing common functionality (auth, identity resolution, error handling)
- **DPoP**: Demonstration of Proof-of-Possession, an OAuth extension for binding tokens to cryptographic keys
- **Endpoint Handler**: A block of code that processes an XRPC method call
- **Auth Extraction**: The process of extracting and validating a DID from an Authorization header with JWT and DPoP verification
- **Handle Resolution**: The process of converting an AT Protocol handle to a DID
- **Lexicon**: AT Protocol schema definitions for XRPC methods

## Requirements

### Requirement 1: Extract Authentication Helper Module

**User Story:** As a developer, I want authentication logic centralized in a dedicated helper module, so that auth handling is consistent across all endpoints and easier to audit.

#### Acceptance Criteria

1. THE XrpcAuthHelper SHALL provide a method to extract and validate DIDs from Authorization headers
2. WHEN an Authorization header contains a valid JWT, THE XrpcAuthHelper SHALL return the authenticated DID
3. WHEN an Authorization header contains a DPoP proof, THE XrpcAuthHelper SHALL verify the proof and return the authenticated DID
4. WHEN DPoP verification fails due to missing nonce, THE XrpcAuthHelper SHALL set the appropriate challenge response headers
5. WHEN authentication fails, THE XrpcAuthHelper SHALL return nil and set appropriate error response status and body
6. THE XrpcAuthHelper SHALL support all three existing extractDIDFromAuthHeader method signatures
7. FOR ALL 44 call sites of extractDIDFromAuthHeader, replacing with XrpcAuthHelper SHALL produce identical authentication behavior

### Requirement 2: Extract Identity Resolution Helper Module

**User Story:** As a developer, I want handle-to-DID resolution logic centralized, so that identity resolution is consistent and I can easily update resolution logic in one place.

#### Acceptance Criteria

1. THE XrpcIdentityHelper SHALL provide a method to resolve handles to DIDs
2. WHEN a valid handle is provided, THE XrpcIdentityHelper SHALL return the corresponding DID
3. WHEN handle resolution fails, THE XrpcIdentityHelper SHALL return an appropriate error
4. THE XrpcIdentityHelper SHALL use the HandleResolver service for resolution
5. FOR ALL endpoints that perform handle resolution, replacing inline logic with XrpcIdentityHelper SHALL produce identical resolution behavior

### Requirement 3: Extract Error Response Helper Module

**User Story:** As a developer, I want standardized error response construction, so that all endpoints return consistent error formats that comply with XRPC specifications.

#### Acceptance Criteria

1. THE XrpcErrorHelper SHALL provide methods to construct standard XRPC error responses
2. WHEN an authentication error occurs, THE XrpcErrorHelper SHALL construct a response with status 401 and appropriate error JSON
3. WHEN an authorization error occurs, THE XrpcErrorHelper SHALL construct a response with status 403 and appropriate error JSON
4. WHEN a validation error occurs, THE XrpcErrorHelper SHALL construct a response with status 400 and appropriate error JSON
5. WHEN a not-found error occurs, THE XrpcErrorHelper SHALL construct a response with status 404 and appropriate error JSON
6. THE XrpcErrorHelper SHALL support custom error messages and error codes
7. FOR ALL error responses in XrpcMethodRegistry, replacing inline error construction with XrpcErrorHelper SHALL produce identical error response formats

### Requirement 4: Create Server Domain Module

**User Story:** As a developer, I want com.atproto.server.* endpoints in a dedicated module, so that I can work on server-related functionality without navigating a 6,308-line file.

#### Acceptance Criteria

1. THE XrpcServerMethods SHALL register all com.atproto.server.* endpoint handlers
2. THE XrpcServerMethods SHALL use XrpcAuthHelper for authentication
3. THE XrpcServerMethods SHALL use XrpcIdentityHelper for handle resolution
4. THE XrpcServerMethods SHALL use XrpcErrorHelper for error responses
5. WHEN XrpcServerMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
6. THE XrpcServerMethods module SHALL be approximately 1200 lines or less

### Requirement 5: Create Repository Domain Module

**User Story:** As a developer, I want com.atproto.repo.* endpoints in a dedicated module, so that repository operations are isolated and easier to test.

#### Acceptance Criteria

1. THE XrpcRepoMethods SHALL register all com.atproto.repo.* endpoint handlers
2. THE XrpcRepoMethods SHALL use XrpcAuthHelper for authentication
3. THE XrpcRepoMethods SHALL use XrpcErrorHelper for error responses
4. WHEN XrpcRepoMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
5. THE XrpcRepoMethods module SHALL be approximately 800 lines or less

### Requirement 6: Create Sync Domain Module

**User Story:** As a developer, I want com.atproto.sync.* endpoints in a dedicated module, so that sync protocol implementation is clearly separated from other concerns.

#### Acceptance Criteria

1. THE XrpcSyncMethods SHALL register all com.atproto.sync.* endpoint handlers
2. THE XrpcSyncMethods SHALL use XrpcAuthHelper for authentication where required
3. THE XrpcSyncMethods SHALL use XrpcErrorHelper for error responses
4. WHEN XrpcSyncMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
5. THE XrpcSyncMethods module SHALL be approximately 600 lines or less

### Requirement 7: Create Identity Domain Module

**User Story:** As a developer, I want com.atproto.identity.* endpoints in a dedicated module, so that identity and PLC operations are clearly organized.

#### Acceptance Criteria

1. THE XrpcIdentityMethods SHALL register all com.atproto.identity.* endpoint handlers
2. THE XrpcIdentityMethods SHALL use XrpcAuthHelper for authentication
3. THE XrpcIdentityMethods SHALL use XrpcIdentityHelper for handle resolution
4. THE XrpcIdentityMethods SHALL use XrpcErrorHelper for error responses
5. WHEN XrpcIdentityMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
6. THE XrpcIdentityMethods module SHALL be approximately 400 lines or less

### Requirement 8: Create Admin Domain Module

**User Story:** As a developer, I want com.atproto.admin.* endpoints in a dedicated module, so that administrative operations are isolated and easier to secure.

#### Acceptance Criteria

1. THE XrpcAdminMethods SHALL register all com.atproto.admin.* endpoint handlers
2. THE XrpcAdminMethods SHALL use XrpcAuthHelper for authentication
3. THE XrpcAdminMethods SHALL enforce admin authorization checks
4. THE XrpcAdminMethods SHALL use XrpcErrorHelper for error responses
5. WHEN XrpcAdminMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
6. THE XrpcAdminMethods module SHALL be approximately 400 lines or less

### Requirement 9: Create Label Domain Module

**User Story:** As a developer, I want com.atproto.label.* and com.atproto.temp.* endpoints in a dedicated module, so that labeling functionality is clearly separated.

#### Acceptance Criteria

1. THE XrpcLabelMethods SHALL register all com.atproto.label.* endpoint handlers
2. THE XrpcLabelMethods SHALL register all com.atproto.temp.* endpoint handlers
3. THE XrpcLabelMethods SHALL use XrpcAuthHelper for authentication where required
4. THE XrpcLabelMethods SHALL use XrpcErrorHelper for error responses
5. WHEN XrpcLabelMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
6. THE XrpcLabelMethods module SHALL be approximately 200 lines or less

### Requirement 10: Create App.bsky Domain Module

**User Story:** As a developer, I want app.bsky.* endpoints in a dedicated module, so that Bluesky-specific functionality is clearly separated from core AT Protocol endpoints.

#### Acceptance Criteria

1. THE XrpcAppBskyMethods SHALL register all app.bsky.* endpoint handlers
2. THE XrpcAppBskyMethods SHALL use XrpcAuthHelper for authentication where required
3. THE XrpcAppBskyMethods SHALL use XrpcErrorHelper for error responses
4. WHEN XrpcAppBskyMethods registers its endpoints, THE behavior SHALL be identical to the original XrpcMethodRegistry implementation
5. THE XrpcAppBskyMethods module SHALL be approximately 500 lines or less

### Requirement 11: Maintain Registry Orchestration

**User Story:** As a developer, I want a simplified XrpcMethodRegistry that orchestrates domain module registration, so that the overall registration flow remains clear and maintainable.

#### Acceptance Criteria

1. THE XrpcMethodRegistry SHALL maintain its existing public interface defined in XrpcMethodRegistry.h
2. THE XrpcMethodRegistry SHALL instantiate all helper modules (Auth, Identity, Error)
3. THE XrpcMethodRegistry SHALL instantiate all domain modules (Server, Repo, Sync, Identity, Admin, Label, AppBsky)
4. THE XrpcMethodRegistry SHALL delegate endpoint registration to domain modules
5. WHEN registerMethodsWithDispatcherUsingServices is called, THE XrpcMethodRegistry SHALL invoke registration methods on all domain modules in the correct order
6. THE XrpcMethodRegistry SHALL be reduced to approximately 200-300 lines (orchestration only)

### Requirement 12: Preserve Backward Compatibility

**User Story:** As a developer, I want the refactoring to be transparent to callers, so that no changes are required in code that uses XrpcMethodRegistry.

#### Acceptance Criteria

1. THE XrpcMethodRegistry public interface SHALL remain unchanged
2. FOR ALL existing callers of XrpcMethodRegistry, THE refactored implementation SHALL work without modification
3. WHEN the refactored code is deployed, THE system SHALL handle all XRPC requests identically to the original implementation
4. THE XrpcMethodRegistry.h header file SHALL not require changes (except possibly adding forward declarations)

### Requirement 13: Maintain Test Coverage

**User Story:** As a developer, I want all existing tests to pass after refactoring, so that I have confidence the refactoring preserves functionality.

#### Acceptance Criteria

1. WHEN the AllTests target is built and run, THE test suite SHALL pass with 0 failures
2. WHEN the ATProtoPDS-CLI target is built, THE build SHALL succeed without errors
3. FOR ALL 1012 existing tests, THE refactored implementation SHALL produce identical test results
4. THE XrpcMethodRegistryTests test suite SHALL continue to pass without modification

### Requirement 14: Enable Incremental Migration

**User Story:** As a developer, I want to migrate endpoints incrementally, so that I can validate each step and minimize risk.

#### Acceptance Criteria

1. THE refactoring approach SHALL support extracting helper modules before splitting domain modules
2. THE refactoring approach SHALL support migrating one domain module at a time
3. WHEN a domain module is partially migrated, THE system SHALL continue to function correctly
4. THE XrpcMethodRegistry SHALL support a hybrid state where some endpoints use new modules and others use legacy code

### Requirement 15: Maintain Lexicon Loading

**User Story:** As a developer, I want lexicon file loading to remain functional, so that XRPC schema validation continues to work.

#### Acceptance Criteria

1. THE XrpcMethodRegistry SHALL continue to load lexicon files from the filesystem
2. WHEN lexicon files are loaded, THE ATProtoLexiconRegistry SHALL be populated correctly
3. THE registerServerDescribeAndResolveLexiconMethods functionality SHALL be preserved
4. WHEN an XRPC method is called, THE system SHALL validate requests against loaded lexicon schemas

### Requirement 16: Document Module Boundaries

**User Story:** As a developer, I want clear documentation of module responsibilities, so that I know where to add new endpoints or modify existing ones.

#### Acceptance Criteria

1. THE XrpcAuthHelper header SHALL document its authentication responsibilities
2. THE XrpcIdentityHelper header SHALL document its identity resolution responsibilities
3. THE XrpcErrorHelper header SHALL document its error response construction responsibilities
4. EACH domain module header SHALL document which XRPC namespaces it handles
5. THE XrpcMethodRegistry header SHALL document the overall registration orchestration flow
