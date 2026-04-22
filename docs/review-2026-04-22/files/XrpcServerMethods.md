# XrpcServerMethods.m — Per-File Analysis

**File**: `Garazyk/Sources/Network/XrpcServerMethods.m`
**Lines**: ~1329

## Findings

### H2: `getAccount` handler not wired

**Location**: `registerAccountLifecycleEndpoints:` (lines 1221-1325)

The method registers handlers for:
- `com.atproto.server.deleteAccount`
- `com.atproto.server.checkAccountStatus`
- `com.atproto.server.activateAccount`
- `com.atproto.server.deactivateAccount`

But does NOT register `com.atproto.server.getAccount` despite it being declared in `XrpcHandler.h:158` and registered on the dispatcher in `XrpcHandler.m:264`.

### H3: `deactivateAccount` uses `takeDownAccount` semantics

**Location**: Lines 1300-1324

```objc
BOOL success = [adminController takeDownAccount:did reason:reason ?: @"User deactivation" error:&error];
```

User deactivation calls the admin takedown method, which sets `"takendown"` status instead of `"deactivated"`.

### No firehose broadcasts after account lifecycle changes

**Location**: Lines 1277-1324

Both `activateAccount` and `deactivateAccount` handlers:
1. Call the admin controller method
2. Return success/failure response
3. **Do NOT broadcast any firehose events**

This means even if the `#account` broadcast method existed (C1), it wouldn't be called from these endpoints.

### Service auth token generation is present

**Location**: Lines ~1170-1219

`registerServiceAuthEndpoint:` correctly generates service auth tokens with:
- `iss` = account DID
- `aud` = service DID (from `lxm` parameter)
- `iat` and `exp` timestamps
- ES256K signing

## Cross-references

- [[../high.md#H2]] — getAccount not wired
- [[../high.md#H3]] — deactivateAccount semantics
- [[../critical.md#C1]] — Missing #account events
