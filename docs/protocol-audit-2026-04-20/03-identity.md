# Identity Protocol Compliance Report

**Date**: 2026-04-20
**Spec References**:
- https://atproto.com/specs/identity
- https://atproto.com/specs/handle
- `reference/did-method-plc/website/spec/v0.1/did-plc.md`

---

## Summary

| Area | Status | Notes |
|------|--------|-------|
| DID:PLC Format | ✅ Compliant | 24-char base32 identifier |
| PLC Operation Validation | ✅ Compliant | Signature, prev, rotation key hierarchy |
| 72-Hour Recovery Window | ✅ Compliant | kPLCRecoveryWindowSeconds = 72 * 60 * 60 |
| Tombstone Detection | ✅ Compliant | Blocking operations after tombstone |
| Operation Rate Limits | ✅ Compliant | 10/hour, 30/day, 100/week |
| Handle Validation | ✅ Compliant | DNS-compliant hostname validation |
| Handle Resolution | ✅ Compliant | HTTPS well-known + DNS TXT fallback |
| DID:Web Support | ⚠️ Partial | Placeholder exists, needs verification |
| Handle-DID Bidirectional | ⚠️ Gap | Need to verify bi-directional validation |

---

## ✅ Compliant Sections

### PLC Operation Chain Verification

**Spec**: Operations must have valid signatures, correct `prev` links, and respect rotation key hierarchy.

**Implementation** (`PLCAuditor.m`):

Genesis operation handling (lines 108-132):
```objc
PLCOperation *first = history.firstObject;
if (!first.prev || first.prev == (id)[NSNull null]) {
    // Genesis operation
    NSDictionary *normalized = [self normalizedDataForOperation:first error:&localError];
    NSArray<NSString *> *rotationKeys = normalized[@"rotationKeys"];
    if (![self verifySignatureForOperation:first allowedKeys:rotationKeys error:&localError]) {
        // Signature verification failed
        return NO;
    }
    // ...
}
```

Chain validation (lines 145-185):
```objc
for (PLCOperation *op in history) {
    // Verify prev links
    NSString *expectedPrev = [self cidStringForOperation:prevOp error:nil];
    if (![op.prev isEqualToString:expectedPrev]) {
        // Prev link broken
        return NO;
    }
    // Verify signature with current rotation keys
    if (![self verifySignatureForOperation:op allowedKeys:rotationKeys error:&localError]) {
        return NO;
    }
    // Update rotation keys for next iteration
    rotationKeys = normalized[@"rotationKeys"];
}
```

---

### 72-Hour Recovery Window

**Spec** (`did-plc.md:125-132`):
> The PLC server provides a 72hr window during which a higher authority rotation key can "rewrite" history...

**Implementation** (`PLCAuditor.m:21`):
```objc
static NSTimeInterval const kPLCRecoveryWindowSeconds = 72 * 60 * 60;
```

Recovery window enforcement (lines 331-370):
```objc
// Check if operation is within 72-hour recovery window
NSDate *firstNullifiedTime = [NSDate dateWithTimeIntervalSince1970:firstNullified.createdAt];
NSTimeInterval timeSinceNullification = [proposedDate timeIntervalSinceDate:firstNullifiedTime];

if (timeSinceNullification > kPLCRecoveryWindowSeconds) {
    if (error) {
        *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                     code:10
                                 userInfo:@{NSLocalizedDescriptionKey:
                @"Recovery window (72 hours) has expired"}];
    }
    return NO;
}

// Verify new signer has higher authority (lower index in rotationKeys)
NSUInteger signerIndex = [rotationKeys indexOfObject:signedKey];
NSUInteger newSignerIndex = [rotationKeys indexOfObject:newSignerKey];
if (newSignerIndex >= signerIndex) {
    // New signer must have higher authority (lower index)
    return NO;
}
```

---

### Operation Rate Limiting

**Spec**: Operations are rate-limited to prevent abuse.

**Implementation** (`PLCAuditor.m:561-592`):
```objc
- (BOOL)enforceRateLimitForHistory:(NSArray<PLCOperation *> *)history
                      proposedDate:(NSDate *)proposedDate
                             error:(NSError **)error {
    NSDate *hourAgo = [proposedDate dateByAddingTimeInterval:-3600];
    NSDate *dayAgo = [proposedDate dateByAddingTimeInterval:-86400];
    NSDate *weekAgo = [proposedDate dateByAddingTimeInterval:-(86400 * 7)];

    NSUInteger withinHour = 0;
    NSUInteger withinDay = 0;
    NSUInteger withinWeek = 0;

    for (PLCOperation *op in history) {
        NSDate *opTime = [NSDate dateWithTimeIntervalSince1970:op.createdAt];
        if ([opTime compare:hourAgo] == NSOrderedDescending) withinHour++;
        if ([opTime compare:dayAgo] == NSOrderedDescending) withinDay++;
        if ([opTime compare:weekAgo] == NSOrderedDescending) withinWeek++;
    }

    if (withinHour >= kPLCHourLimit || withinDay >= kPLCDayLimit || withinWeek >= kPLCWeekLimit) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                         code:11
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"Operation rate limit exceeded"}];
        }
        return NO;
    }
    return YES;
}
```

Limits defined (lines 22-24):
```objc
static NSUInteger const kPLCHourLimit = 10;
static NSUInteger const kPLCDayLimit = 30;
static NSUInteger const kPLCWeekLimit = 100;
```

---

### Tombstone Detection

**Spec**: A tombstone operation permanently deactivates a DID.

**Implementation** (`PLCAuditor.m:50-69`):
```objc
- (BOOL)isTombstoneOperation:(PLCOperation *)op {
    NSDictionary *data = [op operationData];
    if (!data) return NO;

    id typeValue = data[@"type"];
    if ([typeValue isKindOfClass:[NSString class]]) {
        return [typeValue isEqualToString:@"plc_tombstone"];
    }
    return NO;
}

- (BOOL)isTombstoned {
    return [self isTombstoneOperation:self.lastOperation];
}
```

Blocking operations on tombstoned DIDs (`PLCAuditor.m:261-269`):
```objc
PLCOperation *mostRecent = history.lastObject;
if ([self isTombstoneOperation:mostRecent]) {
    if (error) {
        *error = [NSError errorWithDomain:@"PLCAuditorErrorDomain"
                                     code:4
                                 userInfo:@{NSLocalizedDescriptionKey:
                @"DID is tombstoned"}];
    }
    return NO;
}
```

---

### Handle Validation

**Spec**: Handles must be valid DNS hostnames, lowercased.

**Implementation** (`ATProtoHandleValidator.m`):
- DNS hostname format validation
- Lowercase normalization
- Domain TLD validation
- Maximum length (253 chars for FQDN)

---

### Handle Resolution

**Spec**: Resolve handle to DID via HTTPS `/.well-known/atproto-did` with DNS TXT fallback.

**Implementation** (`HandleResolver.m`):

HTTPS resolution (lines 82-180):
```objc
- (void)resolveHandle:(NSString *)handle
           completion:(void (^)(NSString *did, NSError *error))completion {
    // Validate handle format first
    if (![ATProtoHandleValidator validateHandle:handle error:&error]) {
        completion(nil, error);
        return;
    }

    // Try HTTPS resolution
    NSString *urlString = [NSString stringWithFormat:@"https://%@/.well-known/atproto-did", handle];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];

    [self executeHandleHTTPSRequest:request attempt:0 completion:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        if (response.statusCode == 200) {
            // Parse DID from response
            NSString *did = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            completion(did, nil);
            return;
        }

        // Fall back to DNS TXT
        [self resolveHandleViaDNS:handle completion:completion];
    }];
}
```

DNS TXT fallback (lines 200-250):
```objc
- (void)resolveHandleViaDNS:(NSString *)handle
                  completion:(void (^)(NSString *, NSError *))completion {
    // Query _atproto TXT record
    NSString *txtDomain = [NSString stringWithFormat:@"_atproto.%@", handle];
    // ... DNS resolver code using res_query()
}
```

SSRF Protection (`HandleResolver.m`):
- Validates against private IP ranges
- Blocks resolution of localhost, internal networks
- Rate limiting per handle

---

## ⚠️ Gaps

### DID:Web Implementation

**Location**: `Garazyk/Sources/Identity/DID/`

**Status**: DID:web resolver exists but needs verification against spec:

**Spec Requirements**:
- DID document fetched from `https://<domain>/.well-known/did.json`
- CID verification for content-addressed variants
- Proper error handling for HTTP failures

**Files to verify**:
- `DIDWebResolver.m` - HTTP resolution
- `DIDWebValidator.m` - Document validation

---

### Bi-directional Handle-DID Validation

**Spec**: Handle-DID mapping must be verified bi-directionally:
1. Handle resolves to DID
2. DID document contains matching handle in `alsoKnownAs`

**Current Implementation**:
- `HandleResolver` resolves handle → DID ✅
- Need to verify DID → handle consistency check

**Location**: `Garazyk/Sources/Identity/DIDResolver.m`

**Gap**: Verify that when resolving a DID, the handle is cross-validated.

---

### PLC Operation Signing Format

**Spec** (`did-plc.md:76-88`):
> For signatures, the object is first encoded as DAG-CBOR *without* the `sig` field...
> The signature is canonicalized in "low-S" form...

**Status**: Implementation uses low-S form. Need to verify DAG-CBOR encoding matches spec exactly.

**Potential Issue**: Verify that `normalizedDataForOperation:` produces identical DAG-CBOR bytes as reference.

---

## 🔴 Violations

**None identified** in Identity Protocol area.

---

## Test Coverage

| Test File | Coverage Area |
|-----------|---------------|
| `PLCAuditorTests.m` | Operation chain validation |
| `PLCOperationTests.m` | Operation serialization |
| `HandleResolverTests.m` | Handle → DID resolution |
| `HandleValidatorTests.m` | Handle format validation |
| `DIDResolverTests.m` | DID resolution |

**Recommendation**: Add tests for:
1. Cross-validation of handle ↔ DID bidirectional consistency
2. DID:web resolution against reference test vectors
3. Recovery window edge cases (exactly 72 hours, 71 hours 59 minutes)

---

## Code References

- **PLC Auditor**: `Garazyk/Sources/PLC/PLCAuditor.m` (1,013 lines)
- **PLC Operation**: `Garazyk/Sources/PLC/PLCOperation.m`
- **Handle Resolver**: `Garazyk/Sources/Identity/HandleResolver.m`
- **Handle Validator**: `Garazyk/Sources/Identity/ATProtoHandleValidator.m`

---

## Reference Files

- `reference/did-method-plc/website/spec/v0.1/did-plc.md`
- `reference/did-method-plc/packages/lib/src/` - TypeScript reference
- `reference/atproto/packages/pds/src/identity/` - Handle resolution
