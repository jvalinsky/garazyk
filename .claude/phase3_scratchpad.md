# Phase 3 & 4: Cleanup & Deprecation

## Phase 3: Remove Non-Standard Methods

**3.1 Remove `com.atproto.server.getAccount`**
- File: `XrpcServerMethods.m` ~line 1205
- Status: [x] Remove handler and registration

**3.2 Remove `com.atproto.repo.updateRecord`**
- File: `XrpcRepoMethods.m` ~line 923
- Status: [x] Remove handler and registration

**3.3 Remove `com.atproto.repo.deleteBlob`**
- File: `XrpcRepoMethods.m` ~line 334
- Status: [x] Remove handler and registration

**3.4 Keep `com.atproto.repo.getBlob` (delegate to sync.getBlob)**
- File: `XrpcRepoMethods.m` ~line 584
- Status: [x] Update to delegate to shared Range handler

**3.5 Relabel `com.atproto.label.createLabel` + `getLabels`**
- File: `XrpcLabelMethods.m`
- Status: [x] Add documentation that these are non-standard internal extensions

**3.6 Remove `app.bsky.user.getUserStats`**
- File: `XrpcHandler.m`, `XrpcHandler.h`
- Status: [x] Remove handler registration and declaration

## Phase 4: Deprecate Pre-Ozone Moderation

**Deprecate to HTTP 410 Gone:**
- `com.atproto.admin.getAccountTakedown`
- `com.atproto.admin.moderateAccount`
- `com.atproto.admin.moderateRecord`
- `com.atproto.admin.getModerationReports`
- `com.atproto.admin.resolveReport`
- `com.atproto.admin.takeDownAccount`

File: `XrpcAdminMethods.m`
Message: "This method was removed. Moderation has moved to tools.ozone.* - please contact your moderation service administrator."

**Status:** [x] Update all 6 handlers to return 410

### Implementation Details
**4.1 Added HttpStatusGone constant**
- File: `HttpResponse.h` ~line 34
- Added `HttpStatusGone = 410` to HttpStatusCode enum

**4.2 Deprecated getAccountTakedown**
- File: `XrpcAdminMethods.m` ~line 690
- Status: [x] Handler replaced with 410 Gone response

**4.3 Deprecated moderateAccount**
- File: `XrpcAdminMethods.m` ~line 846
- Status: [x] Handler replaced with 410 Gone response

**4.4 Deprecated moderateRecord**
- File: `XrpcAdminMethods.m` ~line 856
- Status: [x] Handler replaced with 410 Gone response

**4.5 Deprecated takeDownAccount**
- File: `XrpcAdminMethods.m` ~line 866
- Status: [x] Handler replaced with 410 Gone response

**4.6 Added getModerationReports handler (new)**
- File: `XrpcAdminMethods.m` ~line 876
- Status: [x] Handler added with 410 Gone response

**4.7 Added resolveReport handler (new)**
- File: `XrpcAdminMethods.m` ~line 886
- Status: [x] Handler added with 410 Gone response

All deprecated handlers return standardized error response with `error: "MethodNotSupported"`

## FINAL STATUS: ✅ COMPLETE

**Commit:** 135c5802  
**Date Completed:** 2026-04-11  
**Deliverables:**
- Removed 6 non-standard methods
- Kept and refactored repo.getBlob to delegate to sync.getBlob
- Documented label methods as non-standard internal extensions

**Files Modified:** 4
- XrpcServerMethods.m (removed getAccount)
- XrpcRepoMethods.m (removed updateRecord, deleteBlob; refactored getBlob)
- XrpcAppBskyMethods.m (removed getUserStats)
- XrpcLabelMethods.m (documented non-standard)

All deprecated methods deleted. Spec hygiene improved.

### Phase 4 Status: ✅ COMPLETE

**Commit:** 135c5802 (same commit as Phase 3)  
**Date Completed:** 2026-04-11  
**Deliverables:**
- Deprecated 6 pre-Ozone moderation methods to HTTP 410 Gone
- Added HttpStatusGone constant to HttpResponse.h
- Clear error message directs clients to tools.ozone.*

**Files Modified:** 2
- HttpResponse.h (added 410 constant)
- XrpcAdminMethods.m (6 handlers → 410 responses)

**Impact:** Clients get meaningful deprecation instead of stale handlers
