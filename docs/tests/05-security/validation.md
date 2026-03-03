# Input Validation Tests

Tests for identifier, path, SQL, and JSON input validation.

## Test Classes

### PDSInputValidatorTests
**File:** `Tests/Security/PDSInputValidatorTests.m`

**Purpose:** Comprehensive input sanitization for all external inputs.

#### How It Works

**Identifier validation:**

```objc
PDSInputValidator *validator = [PDSInputValidator sharedValidator];

// NSID validation
XCTAssertTrue([validator isValidNSID:@"app.bsky.feed.post"]);
XCTAssertFalse([validator isValidNSID:@"App.Bsky.Feed.Post"]);  // Uppercase

// DID validation
XCTAssertTrue([validator isValidDID:@"did:plc:z72i7hdynmk6r22z27h6tvurm"]);
XCTAssertFalse([validator isValidDID:@"did:plc:tooShort"]);

// AT-URI validation
XCTAssertTrue([validator isValidATURI:@"at://did:plc:abc/app.bsky.feed.post/123"]);
```

**SQL injection prevention:**

```objc
NSError *error;
NSString *sanitized = [validator sanitizeSQLInput:@"1; DROP TABLE users" error:&error];

XCTAssertNil(sanitized);  // Rejected
XCTAssertNotNil(error);

// Valid input passes
sanitized = [validator sanitizeSQLInput:@"valid_username" error:&error];
XCTAssertNotNil(sanitized);
```

**Path traversal prevention:**

```objc
sanitized = [validator sanitizePathInput:@"../etc/passwd" error:&error];
XCTAssertNil(sanitized);  // Rejected

sanitized = [validator sanitizePathInput:@"data/file.txt" error:&error];
XCTAssertNotNil(sanitized);  // Accepted
```

**XSS prevention in JSON:**

```objc
NSString *escaped = [validator sanitizeJSONField:@"<script>alert('xss')</script>"];
XCTAssertFalse([escaped containsString:@"<script>"]);
// Escaped to: &lt;script&gt;alert('xss')&lt;/script&gt;
```

**Null byte detection:**

```objc
NSString *malicious = @"admin\x00evil";
BOOL hasNull = [validator stringContainsNullBytes:malicious];
XCTAssertTrue(hasNull);
```

---

### HandleResolverSecurityTests
**File:** `Tests/Identity/HandleResolverSecurityTests.m`

**Purpose:** Handle resolver security testing.

---

## Validation Rules

### NSID (Namespaced ID)
```
Format: nsid.authority.name
Rules: lowercase, alphanumeric + dot, max 317 chars
```

### DID
```
did:plc: 24-char base32lower
did:web: domain[:port][/path]
```

### AT-URI
```
Format: at://did/collection/rkey
Rules: valid DID, valid NSID, valid rkey
```

### SQL Input
```
Blocked: ; -- ' " /* */
Escaped: Single quotes doubled
```

### Path Input
```
Blocked: ../, ..\, null bytes
Allowed: Alphanumeric, -, _, ., /
```

### JSON Field
```
Escaped: <, >, &, ", '
Removed: <script>, javascript:, on*=
```

---

## Running These Tests

```bash
./build/tests/AllTests -only-testing:AllTests/PDSInputValidatorTests
```

## Related Documentation

- [Folder README](README) - Security tests overview
- [Test Index](../README) - Main test documentation index
- [Hardening Tests](hardening) - Production security hardening
- [Auth Security Tests](auth-security) - Authorization tests
- [Primitives Tests](../01-repository/primitives) - Core validation
- [Identity Resolution Tests](../00-identity-auth/identity-resolution) - Handle/DID validation
- [XRPC Tests](../02-network/xrpc) - XRPC input validation
- [Security Analysis Report](../../security/SECURITY_ANALYSIS_REPORT) - Detailed review
