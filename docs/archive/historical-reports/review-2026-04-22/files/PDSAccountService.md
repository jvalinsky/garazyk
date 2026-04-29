# PDSAccountService.m — Per-File Analysis

**File**: `Garazyk/Sources/Services/PDS/PDSAccountService.m`
**Lines**: ~600+

## Findings

### C1/C2: Account creation does not emit firehose events

**Location**: Lines 261-270

After creating an account, the service only logs a hosting event:
```objc
[self.serviceDatabases logHostingEvent:resolvedDid
                                  type:@"account_created"
                               details:details
                             createdBy:resolvedDid
                                 error:nil];
```

This is an internal audit trail only. No firehose `#identity` or `#account` events are broadcast.

**Root cause**: `PDSAccountService` has no reference to `SubscribeReposHandler` and cannot directly broadcast firehose events. The current pattern uses `PDSRecordDidChangeNotification` for commit events, but there's no equivalent notification for account lifecycle events.

### M4: `getAccountForDid:` returns email

**Location**: Lines 390-399

Returns `{did, handle, email}` but spec says only `{did, handle}`.

### Password hashing is OWASP-compliant

**Location**: Lines 496-526

PBKDF2 with 600,000 iterations and HMAC-SHA256. This meets OWASP 2023 recommendations.

### PLC DID generation is sans-I/O

**Location**: Lines 533-596

`_generateDIDWithHandle:signingKey:rotationKey:error:` is a pure function that generates a DID without network I/O. This is good for testability.

### Constant-time password comparison

**Location**: Lines 29-46

`PDSConstantTimeEqualData` implements proper constant-time comparison to prevent timing attacks.

## Cross-references

- [[../critical.md#C1]] — Missing `#account` events
- [[../critical.md#C2]] — Missing `#identity` on creation
- [[../medium.md#M4]] — Email in getAccount response
