# Security Audit Guide

This guide explains how to use September PDS's security audit skills to identify and remediate common vulnerabilities in Objective-C code. The repository includes specialized audit tools in `.opencode/skills/` that automate vulnerability detection.

## Overview

September PDS includes 12 security-focused audit skills that scan for specific vulnerability classes:

1. **Cryptographic Security** — Weak algorithms, hardcoded keys, timing attacks
2. **SQL Injection** — Dynamic SQL construction, unsafe query building
3. **Parser Hardening** — Bounds checks, integer overflow, malformed input
4. **Log Redaction** — Sensitive data exposure in logs
5. **OAuth/DPoP Conformance** — Authentication protocol compliance
6. **Rate Limiting & DoS** — Request throttling, resource exhaustion
7. **Concurrency Bugs** — Race conditions, data races
8. **Locking & Queues** — Deadlocks, queue safety
9. **Reentrancy** — Callback reentrancy issues
10. **Secrets Detection** — Hardcoded credentials, API keys
11. **Service Boundaries** — Input validation at service layer
12. **XRPC Contract** — Protocol compliance, schema validation

## Quick Start

Each audit skill follows a consistent workflow:

```bash
# 1. Run the audit script
./skills/<skill-name>/scripts/scan_*.sh . /tmp/<skill-name>

# 2. Review the summary report
cat /tmp/<skill-name>/summary.md

# 3. Validate findings with the checklist
cat .opencode/skills/<skill-name>/references/*-checklist.md
```

## Audit Skills Reference

### 1. Cryptographic Security Audit

**Purpose:** Detect weak cryptographic algorithms, hardcoded keys, improper IV usage, timing attacks, and insecure random number generation.

**When to use:** Reviewing authentication, encryption, signing, or any security-sensitive crypto code.

**Quick start:**
```bash
./.opencode/skills/objc-cryptographic-security-audit/scripts/scan_crypto.sh . /tmp/crypto-audit
cat /tmp/crypto-audit/summary.md
```

**What it finds:**
- Weak hash algorithms (MD5, SHA1)
- Weak encryption (DES, RC4, ECB mode)
- Hardcoded encryption keys or IVs
- Non-constant-time secret comparison
- Non-cryptographic random for security contexts

**Triage priorities:**
- **P0:** Weak crypto for authentication, secrets, or signing
- **P1:** Hardcoded encryption keys or IVs
- **P1:** Timing-vulnerable secret comparison
- **P2:** Non-crypto random for security purposes
- **P3:** SHA1/MD5 for non-security uses (check context)

**Fix patterns:**
```objc
// Bad: Weak hash algorithm
CC_MD5(data.bytes, data.length, hash);

// Good: Strong hash algorithm
CC_SHA256(data.bytes, data.length, hash);

// Bad: Hardcoded key
NSData *key = [@"my-secret-key" dataUsingEncoding:NSUTF8StringEncoding];

// Good: Generated key
NSMutableData *key = [NSMutableData dataWithLength:32];
SecRandomCopyBytes(kSecRandomDefault, 32, key.mutableBytes);

// Bad: Timing-vulnerable comparison
if ([token isEqualToString:expectedToken]) { /* ... */ }

// Good: Constant-time comparison
if (CCHmacTimingSafeCompare(token, expectedToken)) { /* ... */ }

// Bad: Non-crypto random
int nonce = rand();

// Good: Crypto-secure random
uint32_t nonce;
SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce), &nonce);
```

**Reference:** `.opencode/skills/objc-cryptographic-security-audit/references/crypto-security-checklist.md`

### 2. SQL Injection Deep Audit

**Purpose:** Find SQL injection vulnerabilities beyond basic pattern matching, including dynamic SQL construction and raw query execution.

**When to use:** Reviewing database query construction, dynamic SQL, or any code that builds SQL strings from user input.

**Quick start:**
```bash
./.opencode/skills/objc-sql-injection-deep-audit/scripts/scan_sql_injection.sh . /tmp/sql-audit
cat /tmp/sql-audit/summary.md
```

**What it finds:**
- User input directly concatenated into SQL
- String formatting in SQL context
- Dynamic table/column names without validation
- Missing parameterization
- Unsafe `PRAGMA` usage

**Triage priorities:**
- **P0:** User input directly concatenated into SQL
- **P1:** Dynamic SQL construction with string formatting
- **P2:** Missing input validation before SQL operations
- **P3:** Indirect injection via configuration or file paths

**Fix patterns:**
```objc
// Bad: String concatenation
NSString *sql = [NSString stringWithFormat:@"SELECT * FROM users WHERE did = '%@'", did];
[database executeQuery:sql];

// Good: Parameterized query
NSString *sql = @"SELECT * FROM users WHERE did = ?";
[database executeQuery:sql params:@[did] error:&error];

// Bad: Dynamic table name
NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", tableName];

// Good: Whitelist validation
NSSet *allowedTables = [NSSet setWithArray:@[@"users", @"posts", @"follows"]];
if (![allowedTables containsObject:tableName]) {
    return nil;  // Reject invalid table name
}
NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@", tableName];
```

**Reference:** `.opencode/skills/objc-sql-injection-deep-audit/references/sql-injection-checklist.md`

### 3. Parser Hardening Audit

**Purpose:** Audit parsing and decoding code for bounds checks, integer overflow risks, malformed input handling, and unsafe memory operations.

**When to use:** Reviewing parser security, fuzzing gaps, or crash-prone decoding paths.

**Quick start:**
```bash
./.opencode/skills/objc-parser-hardening-audit/scripts/scan_parser_hardening.sh . /tmp/parser-audit
cat /tmp/parser-audit/summary.md
```

**What it finds:**
- Unchecked length/offset before memory access
- Integer conversion or arithmetic overflow risk
- Malformed input paths with partial state mutation
- Missing bounds checks in parsers

**Triage priorities:**
- **P0:** Unchecked length/offset before memory access
- **P1:** Integer conversion or arithmetic overflow risk
- **P2:** Malformed input path with partial state mutation
- **P3:** Low-confidence parser smell

**Fix patterns:**
```objc
// Bad: No bounds check
uint8_t *data = buffer.bytes;
uint32_t length = *(uint32_t *)(data + offset);  // Could read past end

// Good: Bounds check
if (offset + sizeof(uint32_t) > buffer.length) {
    return nil;  // Fail safely
}
uint8_t *data = buffer.bytes;
uint32_t length = *(uint32_t *)(data + offset);

// Bad: Integer overflow
NSUInteger totalSize = count * itemSize;  // Could overflow
NSMutableData *result = [NSMutableData dataWithLength:totalSize];

// Good: Overflow check
if (count > 0 && itemSize > NSUIntegerMax / count) {
    return nil;  // Overflow would occur
}
NSUInteger totalSize = count * itemSize;
NSMutableData *result = [NSMutableData dataWithLength:totalSize];
```

**Reference:** `.opencode/skills/objc-parser-hardening-audit/references/parser-hardening-checklist.md`

### 4. Log Redaction Audit

**Purpose:** Detect logging paths that may leak credentials, tokens, authorization headers, or personally identifiable information.

**When to use:** Reviewing security hardening, incident response, or logging policy compliance.

**Quick start:**
```bash
./.opencode/skills/objc-log-redaction-audit/scripts/scan_log_redaction.sh . /tmp/log-audit
cat /tmp/log-audit/summary.md
```

**What it finds:**
- Direct logging of tokens, secrets, or authorization headers
- Logs that can reconstruct credentials/session context
- Inconsistent masking across code paths
- PII exposure in logs

**Triage priorities:**
- **P0:** Direct logging of tokens, secrets, or authorization headers
- **P1:** Logs that can reconstruct credentials/session context
- **P2:** Inconsistent masking across code paths
- **P3:** Uncertain sensitive-field logging

**Fix patterns:**
```objc
// Bad: Logging sensitive data
PDS_LOG_INFO(@"Request headers: %@", request.allHTTPHeaderFields);
PDS_LOG_DEBUG(@"JWT token: %@", token);

// Good: Redacted logging
PDS_LOG_INFO(@"Request headers: %@", [self redactedHeaders:request.allHTTPHeaderFields]);
PDS_LOG_DEBUG(@"JWT token: %@", [self maskToken:token]);

// Redaction helper
- (NSString *)maskToken:(NSString *)token {
    if (token.length <= 8) {
        return @"[REDACTED]";
    }
    NSString *prefix = [token substringToIndex:4];
    NSString *suffix = [token substringFromIndex:token.length - 4];
    return [NSString stringWithFormat:@"%@...%@", prefix, suffix];
}

// Header redaction
- (NSDictionary *)redactedHeaders:(NSDictionary *)headers {
    NSMutableDictionary *redacted = [headers mutableCopy];
    NSArray *sensitiveKeys = @[@"Authorization", @"Cookie", @"X-API-Key"];
    for (NSString *key in sensitiveKeys) {
        if (redacted[key]) {
            redacted[key] = @"[REDACTED]";
        }
    }
    return redacted;
}
```

**Reference:** `.opencode/skills/objc-log-redaction-audit/references/log-redaction-checklist.md`

### 5. OAuth/DPoP Conformance Audit

**Purpose:** Verify OAuth 2.0 and DPoP implementation conforms to RFC specifications.

**When to use:** Reviewing authentication flows, token handling, or OAuth/DPoP implementation changes.

**Quick start:**
```bash
./.opencode/skills/objc-oauth-dpop-conformance-audit/scripts/scan_oauth_dpop.sh . /tmp/oauth-audit
cat /tmp/oauth-audit/summary.md
```

**What it finds:**
- Missing DPoP proof validation
- Incorrect token binding
- Missing nonce/timestamp checks
- Non-compliant error responses
- Insecure token storage

**Key compliance checks:**
- DPoP proof signature verification
- Token binding to DPoP key
- Replay protection (nonce/timestamp)
- PKCE for public clients
- Secure token storage

**Reference:** `.opencode/skills/objc-oauth-dpop-conformance-audit/references/oauth-dpop-checklist.md`

### 6. Rate Limiting & DoS Audit

**Purpose:** Identify missing rate limits, resource exhaustion vectors, and DoS vulnerabilities.

**When to use:** Reviewing endpoint handlers, resource-intensive operations, or DoS protection.

**Quick start:**
```bash
./.opencode/skills/objc-rate-limiting-dos-audit/scripts/scan_rate_limiting.sh . /tmp/rate-limit-audit
cat /tmp/rate-limit-audit/summary.md
```

**What it finds:**
- Endpoints without rate limiting
- Unbounded resource allocation
- Missing request size limits
- CPU-intensive operations without throttling
- Memory exhaustion vectors

**Fix patterns:**
```objc
// Add rate limiting to endpoints
- (void)handleRequest:(XrpcRequest *)request response:(XrpcResponse *)response {
    // Check rate limit
    if (![self.rateLimiter allowRequest:request.did]) {
        [response sendError:429 message:@"Too many requests"];
        return;
    }
    
    // Enforce request size limit
    if (request.body.length > 1024 * 1024) {  // 1 MB
        [response sendError:413 message:@"Request too large"];
        return;
    }
    
    // Process request
    // ...
}
```

**Reference:** `.opencode/skills/objc-rate-limiting-dos-audit/references/rate-limiting-checklist.md`

### 7. Concurrency Bug Audit

**Purpose:** Detect race conditions, data races, and thread-safety violations.

**When to use:** Reviewing multi-threaded code, shared state access, or concurrency-related bugs.

**Quick start:**
```bash
./.opencode/skills/objc-concurrency-bug-audit/scripts/scan_concurrency.sh . /tmp/concurrency-audit
cat /tmp/concurrency-audit/summary.md
```

**What it finds:**
- Unsynchronized shared state access
- Race conditions in check-then-act patterns
- Missing atomic operations
- Thread-unsafe collection mutations

**Reference:** `.opencode/skills/objc-concurrency-bug-audit/references/concurrency-checklist.md`

### 8. Locking & Queue Audit

**Purpose:** Identify deadlock risks, lock ordering violations, and queue safety issues.

**When to use:** Reviewing locking patterns, dispatch queue usage, or deadlock investigations.

**Quick start:**
```bash
./.opencode/skills/objc-locking-queue-audit/scripts/scan_locking.sh . /tmp/locking-audit
cat /tmp/locking-audit/summary.md
```

**What it finds:**
- Potential deadlocks (lock ordering violations)
- Recursive lock usage
- Dispatch queue misuse
- Lock held across async operations

**Reference:** `.opencode/skills/objc-locking-queue-audit/references/locking-checklist.md`

### 9. Reentrancy Audit

**Purpose:** Detect reentrancy issues where callbacks can cause unexpected state mutations.

**When to use:** Reviewing callback-heavy code, delegate patterns, or state machine implementations.

**Quick start:**
```bash
./.opencode/skills/objc-reentrancy-audit/scripts/scan_reentrancy.sh . /tmp/reentrancy-audit
cat /tmp/reentrancy-audit/summary.md
```

**What it finds:**
- Callbacks that can trigger reentrancy
- State mutations during iteration
- Delegate calls with mutable state
- Completion handlers that modify caller state

**Reference:** `.opencode/skills/objc-reentrancy-audit/references/reentrancy-checklist.md`

### 10. Secrets Detection Audit

**Purpose:** Find hardcoded credentials, API keys, tokens, and other secrets in source code.

**When to use:** Pre-commit checks, security reviews, or compliance audits.

**Quick start:**
```bash
./.opencode/skills/objc-secrets-detection-audit/scripts/scan_secrets.sh . /tmp/secrets-audit
cat /tmp/secrets-audit/summary.md
```

**What it finds:**
- Hardcoded passwords and API keys
- Embedded tokens and credentials
- Private keys in source
- Database connection strings with credentials

**Reference:** `.opencode/skills/objc-secrets-detection-audit/references/secrets-checklist.md`

## Common Vulnerability Patterns

### 1. Input Validation Failures

**Symptoms:**
- Crashes on malformed input
- Unexpected behavior with edge cases
- Buffer overflows or out-of-bounds access

**Detection:**
- Run parser hardening audit
- Review input validation at service boundaries
- Check for missing bounds checks

**Remediation:**
- Validate all inputs at entry points
- Use allowlists over denylists
- Fail securely on invalid input
- Add fuzzing for parsers

### 2. Authentication Bypass

**Symptoms:**
- Missing authentication checks
- Incorrect token validation
- Session fixation vulnerabilities

**Detection:**
- Run OAuth/DPoP conformance audit
- Review authentication middleware
- Check token validation logic

**Remediation:**
- Validate tokens on every protected endpoint
- Implement proper DPoP proof verification
- Use constant-time comparison for secrets
- Enforce token expiration

### 3. Information Disclosure

**Symptoms:**
- Sensitive data in logs
- Detailed error messages to clients
- Unredacted debug output

**Detection:**
- Run log redaction audit
- Review error handling code
- Check debug logging paths

**Remediation:**
- Redact sensitive fields in logs
- Return generic error messages to clients
- Disable verbose logging in production
- Use structured logging with redaction

### 4. Injection Attacks

**Symptoms:**
- Dynamic SQL construction
- Unsanitized user input in queries
- Command injection vectors

**Detection:**
- Run SQL injection audit
- Review query construction code
- Check for string concatenation in SQL

**Remediation:**
- Use parameterized queries exclusively
- Validate and whitelist dynamic identifiers
- Never pass user input to shell commands
- Escape output for HTML/JavaScript contexts

### 5. Cryptographic Weaknesses

**Symptoms:**
- Weak hash algorithms (MD5, SHA1)
- Hardcoded encryption keys
- Predictable random numbers

**Detection:**
- Run cryptographic security audit
- Review key generation and storage
- Check random number usage

**Remediation:**
- Use SHA-256 or stronger for hashing
- Generate keys with `SecRandomCopyBytes`
- Store keys in Keychain (macOS) or secure storage
- Use crypto-secure random for security contexts

## Audit Workflow

### Pre-Release Security Review

1. **Run all audit skills:**
```bash
for skill in .opencode/skills/objc-*/; do
    skill_name=$(basename "$skill")
    echo "Running $skill_name..."
    "$skill/scripts/scan_"*.sh . "/tmp/$skill_name"
done
```

2. **Review summary reports:**
```bash
for report in /tmp/objc-*/summary.md; do
    echo "=== $(dirname "$report") ==="
    cat "$report"
    echo
done
```

3. **Triage findings by priority:**
   - P0: Critical security issues (fix immediately)
   - P1: High-risk vulnerabilities (fix before release)
   - P2: Medium-risk issues (fix in next sprint)
   - P3: Low-risk or false positives (review and document)

4. **Validate and fix:**
   - Review each finding with the corresponding checklist
   - Implement fixes following the documented patterns
   - Add tests to prevent regression
   - Re-run audit to verify fix

### Continuous Security Monitoring

Add audit skills to CI/CD pipeline:

```yaml
# .github/workflows/security.yml
name: Security Audit

on: [push, pull_request]

jobs:
  security-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run cryptographic audit
        run: |
          ./.opencode/skills/objc-cryptographic-security-audit/scripts/scan_crypto.sh . /tmp/crypto
          cat /tmp/crypto/summary.md
      
      - name: Run SQL injection audit
        run: |
          ./.opencode/skills/objc-sql-injection-deep-audit/scripts/scan_sql_injection.sh . /tmp/sql
          cat /tmp/sql/summary.md
      
      # Add more audits as needed
```

## Best Practices

### 1. Regular Audits

- Run security audits before each release
- Include audits in code review process
- Schedule quarterly comprehensive security reviews

### 2. Prioritize Findings

- Focus on P0/P1 issues first
- Consider attack surface and exploitability
- Document accepted risks for P3 findings

### 3. Fix Patterns

- Follow documented fix patterns
- Add tests for security fixes
- Document security decisions in code comments

### 4. False Positive Management

- Review findings with checklists
- Document false positives
- Improve audit scripts to reduce noise

### 5. Security Culture

- Train developers on common vulnerabilities
- Share audit findings in team meetings
- Celebrate security improvements

## Related Documentation

- [Input Validation](../04-network-layer/input-validation) — Validation strategies and patterns
- [Security Best Practices](../06-authentication/security-best-practices) — Defense in depth
- [Secrets Management](../06-authentication/secrets-management) — Key storage and rotation
- [Rate Limiting](../04-network-layer/rate-limiting) — DoS protection

## External Resources

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- CWE Top 25: https://cwe.mitre.org/top25/
- NIST Secure Software Development Framework: https://csrc.nist.gov/projects/ssdf
- AT Protocol Security Considerations: https://atproto.com/specs/security
