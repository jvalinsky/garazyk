# PDSController Refactoring Plan

## Overview
The PDSController has grown into a monolithic class handling 8+ different responsibilities. This refactoring breaks it down into focused service classes while maintaining backward compatibility.

## Current Issues
- **Single Responsibility Violation**: PDSController handles accounts, records, blobs, admin, moderation, labeling, and health
- **Maintainability**: Large class (199+ lines in header) makes changes risky
- **Testability**: Complex interdependencies make unit testing difficult

## Refactoring Approach
**Minimal Complexity Strategy**: Extract focused services but maintain the same public interface. This avoids breaking existing code while improving internal organization.

### Phase 1: Extract Core Services
1. **PDSAccountService** - Account lifecycle (create, login, refresh, delete)
2. **PDSRecordService** - Record operations (get, list, put, delete)  
3. **PDSBlobService** - Blob operations (get, upload, list, delete)
4. **PDSAdminService** - Admin/moderation operations (keep in controller for now)

### Phase 2: Service Integration
- PDSController becomes a facade that delegates to services
- Services receive necessary dependencies (database pools, etc.)
- Maintain exact same public API

## Implementation Plan

### Task 1: Create PDSAccountService
**Files:**
- Create: `ATProtoPDS/Sources/App/Services/PDSAccountService.h`
- Create: `ATProtoPDS/Sources/App/Services/PDSAccountService.m`

**Methods to extract:**
- `createAccountForEmail:password:handle:did:error:`
- `loginWithHandle:password:error:`
- `refreshAccessToken:error:`
- `deleteAccount:password:error:`

### Task 2: Create PDSRecordService  
**Files:**
- Create: `ATProtoPDS/Sources/App/Services/PDSRecordService.h`
- Create: `ATProtoPDS/Sources/App/Services/PDSRecordService.m`

**Methods to extract:**
- `getRecord:forDid:error:`
- `listRecords:forDid:limit:cursor:error:`
- `putRecord:rkey:value:forDid:error:`
- `deleteRecord:rkey:forDid:error:`

### Task 3: Create PDSBlobService
**Files:**
- Create: `ATProtoPDS/Sources/App/Services/PDSBlobService.h`
- Create: `ATProtoPDS/Sources/App/Services/PDSBlobService.m`

**Methods to extract:**
- `getBlob:forDid:error:`
- `uploadBlob:forDid:mimeType:error:`
- `getBlobWithCID:did:error:`
- `listBlobsForDID:limit:cursor:error:`
- `deleteBlobWithCID:did:error:`

### Task 4: Update PDSController
**Files:**
- Modify: `ATProtoPDS/Sources/App/PDSController.m`

**Changes:**
- Add service properties
- Initialize services in `initWithDirectory:serviceMaxSize:userDatabaseSize:`
- Delegate method calls to appropriate services
- Maintain exact same public interface

## Testing Strategy
- Existing tests should pass without modification (API unchanged)
- Add integration tests for each service
- Verify no functional regressions

## Backward Compatibility
✅ **100% maintained** - No breaking changes to public API

---

## Related Documentation

- [Archive Index](./README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation</content>
<parameter name="filePath">docs/plans/2026-01-09-pdscontroller-refactor.md