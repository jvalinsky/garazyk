# Identity Resolution Tests

Tests for handle resolution, DID resolution, and identifier validation.

## Test Classes

### HandleResolverTests
**File:** `Tests/Identity/HandleResolverTests.m`

**Purpose:** ATProto handle-to-DID resolution via HTTPS well-known and DNS TXT.

#### How It Works

**Mock URL session** for controlled testing:

```objc
@interface MockURLSession : NSObject
@property (nonatomic, strong) NSDictionary *mockResponse;
@property (nonatomic, strong) NSError *mockError;
@end

MockURLSession *mockSession = [[MockURLSession alloc] 
    initWithResponse:@{@"statusCode": @200, @"body": @"did:plc:abc"}
                   error:nil
                   delay:0];
resolver.session = mockSession;
```

**Resolution methods tested:**

1. **HTTPS well-known:**
   ```
   GET https://example.com/.well-known/atproto-did
   → did:plc:abc
   ```

2. **DNS TXT fallback:**
   ```
   dig TXT _atproto.example.com
   → "did=did:plc:abc"
   ```

#### Why It Matters

| Check | Purpose |
|-------|---------|
| Handle format validation | Prevents injection |
| HTTPS first, DNS fallback | Reliability |
| Timeout enforcement | Prevents hanging |

| Method | What It Verifies |
|--------|------------------|
| `testHandleValidationEmpty` | Error 1001 for empty |
| `testHandleValidationNoDot` | Error 1004 for single segment |
| `testHandleResolverInitialization` | Correct timeout values |

---

### HandleResolverSSRFTests
**File:** `Tests/Identity/HandleResolverSSRFTests.m`

**Purpose:** SSRF (Server-Side Request Forgery) protection blocks private IP ranges.

#### How It Works

**IP range detection** via regex patterns:

```objc
// Test private IP detection
XCTAssertTrue([HandleResolver isPrivateIP:@"10.0.0.1"]);      // Class A
XCTAssertTrue([HandleResolver isPrivateIP:@"172.16.0.1"]);     // Class B
XCTAssertTrue([HandleResolver isPrivateIP:@"192.168.1.1"]);    // Class C
XCTAssertTrue([HandleResolver isPrivateIP:@"127.0.0.1"]);      // Loopback
XCTAssertTrue([HandleResolver isPrivateIP:@"169.254.1.1"]);    // Link-local

// Test public IPs allowed
XCTAssertFalse([HandleResolver isPrivateIP:@"8.8.8.8"]);       // Google DNS
XCTAssertFalse([HandleResolver isPrivateIP:@"1.1.1.1"]);       // Cloudflare
```

#### Why It Matters

**SSRF attacks** attempt to make the server access internal resources:
- `http://localhost/admin` → internal admin panel
- `http://10.0.0.1/secrets` → internal network
- `http://169.254.169.254/` → cloud metadata

Blocking private IP ranges prevents these attacks.

| Method | What It Verifies |
|--------|------------------|
| `testPrivateIPv4ClassA/B/C` | RFC 1918 ranges blocked |
| `testPrivateIPv4Loopback` | 127.x.x.x blocked |
| `testPublicIPv4Address` | Public IPs allowed |
| `testSSRFProtectionEnabledByDefault` | On by default |

---

### ATProtoHandleValidatorTests
**File:** `Tests/Identity/ATProtoHandleValidatorTests.m`

**Purpose:** Handle validation rules per ATProto specification.

#### How It Works

```objc
ATProtoHandleValidator *validator = [[ATProtoHandleValidator alloc] init];

// Valid handles
XCTAssertTrue([validator isValidHandle:@"user.bsky.social"]);
XCTAssertTrue([validator isValidHandle:@"sub.domain.example.com"]);

// Invalid handles
XCTAssertFalse([validator isValidHandle:@"user"]);           // No dot
XCTAssertFalse([validator isValidHandle:@"user@example"]);  // @ symbol
XCTAssertFalse([validator isValidHandle:@"user_underscore"]); // Underscore
```

#### Why It Matters

| Rule | Purpose |
|------|---------|
| Must have dot | Prevents TLD collision |
| Max 253 chars | DNS limit |
| Labels max 63 chars | DNS limit |
| No underscores | DNS compatibility |
| No all-numeric TLD | Prevents IP confusion |

| Method | What It Verifies |
|--------|------------------|
| `testValidHandles` | Correct formats accepted |
| `testHandleTooLong` | > 253 chars rejected |
| `testInvalidCharacters` | Underscores, emoji rejected |

---

### DIDResolverTests
**File:** `Tests/Identity/DIDResolverTests.m`

**Purpose:** DID document resolution with caching and TTL support.

#### How It Works

**Cache population for testing:**

```objc
DIDResolver *resolver = [[DIDResolver alloc] init];
NSDictionary *documentJSON = @{
    @"id": @"did:plc:test",
    @"verificationMethod": @[@{
        @"id": @"did:plc:test#atproto",
        @"publicKeyMultibase": @"zQ3sh..."
    }]
};
DIDDocument *document = [DIDDocument documentWithJSON:documentJSON error:nil];
[resolver.cache setObject:document forKey:@"did:plc:test"];
```

**TTL-based caching:**

```objc
// Fresh within staleTTL
resolver.cacheTimestamps[@"did:plc:test"] = @([[NSDate date] timeIntervalSince1970]);

// Expired beyond maxTTL
resolver.cacheTimestamps[@"did:plc:test"] = @([[NSDate date] timeIntervalSince1970] - 86400 - 60);
```

#### Why It Matters

| Feature | Purpose |
|---------|---------|
| Caching | Reduces network latency |
| TTL enforcement | Ensures freshness |
| Batch resolution | Efficiency for multiple DIDs |

| Method | What It Verifies |
|--------|------------------|
| `testResolveAtprotoDataDecodesSigningKey` | Key extraction |
| `testDIDResolutionCaching` | Cache used |
| `testExpiredCacheEviction` | Old entries removed |

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/HandleResolverTests
./build/tests/AllTests -only-testing:AllTests/HandleResolverSSRFTests
./build/tests/AllTests -only-testing:AllTests/ATProtoHandleValidatorTests
./build/tests/AllTests -only-testing:AllTests/DIDResolverTests
```

## Security Considerations

1. **SSRF Protection**: All private IP ranges blocked by default
2. **Handle Validation**: Strict format rules prevent injection
3. **Cache TTL**: Prevents stale data from being served indefinitely

## Related Documentation

- [Folder README](README) - Identity & authentication tests overview
- [Test Index](../README) - Main test documentation index
- [SSRF Protection](../../security/SSRF_PROTECTION) - SSRF protection implementation
- [OAuth2 Security](../../oauth2/security) - OAuth2 security considerations
- [Security Tests](../05-security/README) - Security test documentation
- [Network Tests](../02-network/README) - Network layer tests
