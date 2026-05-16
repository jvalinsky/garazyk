---
title: Security Best Practices
---

# Security Best Practices

This document outlines security best practices for Garazyk PDS, focusing on defense in depth, least privilege, and secure development patterns. These principles should guide all security-related decisions and implementations.

## Core Security Principles

### 1. Defense in Depth

Defense in depth means implementing multiple layers of security controls so that if one layer fails, others continue to provide protection.

**Garazyk PDS implements defense in depth through:**

#### Layer 1: Network Perimeter
- TLS/HTTPS for all external communication
- Rate limiting at HTTP server level
- Request size limits
- IP-based filtering (optional)

```objc
// From Garazyk/Sources/Network/HttpServer.m
- (void)configureSecurityMiddleware {
    // TLS configuration
    [self requireTLS:YES];
    
    // Rate limiting
    [self enableRateLimiting:self.config.rateLimitConfig];
    
    // Request size limits
    [self setMaxRequestSize:10 * 1024 * 1024];  // 10 MB
    
    // Timeout configuration
    [self setRequestTimeout:30.0];  // 30 seconds
}
```

#### Layer 2: Authentication & Authorization
- OAuth 2.0 with DPoP for token binding
- JWT signature verification
- Token expiration enforcement
- Scope-based authorization

```objc
// From Garazyk/Sources/Network/XrpcAuthHelper.m
- (BOOL)verifyRequest:(XrpcRequest *)request error:(NSError **)error {
    // Layer 2a: Verify JWT signature
    if (![self verifyJWTSignature:request.token error:error]) {
        return NO;
    }
    
    // Layer 2b: Verify DPoP proof
    if (![self verifyDPoPProof:request.dpopProof 
                     forMethod:request.method 
                           uri:request.uri 
                         error:error]) {
        return NO;
    }
    
    // Layer 2c: Check token expiration
    if ([self isTokenExpired:request.token]) {
        if (error) {
            *error = [NSError errorWithDomain:@"Auth" 
                                         code:401 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Token expired"}];
        }
        return NO;
    }
    
    // Layer 2d: Verify scopes
    if (![self hasRequiredScopes:request.token 
                      forEndpoint:request.nsid]) {
        if (error) {
            *error = [NSError errorWithDomain:@"Auth" 
                                         code:403 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Insufficient permissions"}];
        }
        return NO;
    }
    
    return YES;
}
```

#### Layer 3: Input Validation
- Protocol identifier validation (DID, CID, NSID)
- MIME type validation
- Size limits by content type
- Magic number verification

```objc
// From Garazyk/Sources/Blob/BlobService.m
- (BOOL)validateBlobUpload:(NSData *)data 
                  mimeType:(NSString *)mimeType 
                       cid:(NSString *)cid 
                     error:(NSError **)error {
    // Layer 3a: Validate CID format
    if (![ATProtoValidator validateCID:cid error:error]) {
        return NO;
    }
    
    // Layer 3b: Validate MIME type
    if (![self.mimeValidator validateMimeType:mimeType error:error]) {
        return NO;
    }
    
    // Layer 3c: Validate size for type
    if (![self.mimeValidator validateSize:data.length 
                              forMimeType:mimeType 
                                    error:error]) {
        return NO;
    }
    
    // Layer 3d: Verify magic numbers
    if (![self.mimeValidator validateMagicNumbers:data 
                                      forMimeType:mimeType 
                                            error:error]) {
        return NO;
    }
    
    // Layer 3e: Verify CID matches content
    NSString *computedCID = [self computeCIDForData:data];
    if (![computedCID isEqualToString:cid]) {
        if (error) {
            *error = [NSError errorWithDomain:@"BlobService" 
                                         code:400 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"CID mismatch"}];
        }
        return NO;
    }
    
    return YES;
}
```

#### Layer 4: Business Logic
- Service-level authorization checks
- Resource ownership verification
- State validation
- Transaction integrity

```objc
// From Garazyk/Sources/Services/PDSRecordService.m
- (BOOL)deleteRecord:(NSString *)did 
          collection:(NSString *)collection 
              rkey:(NSString *)rkey 
         requestDID:(NSString *)requestDID 
             error:(NSError **)error {
    // Layer 4a: Verify ownership
    if (![did isEqualToString:requestDID]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RecordService" 
                                         code:403 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Cannot delete another user's record"}];
        }
        return NO;
    }
    
    // Layer 4b: Verify record exists
    NSDictionary *record = [self getRecord:did 
                                collection:collection 
                                      rkey:rkey 
                                     error:error];
    if (!record) {
        return NO;
    }
    
    // Layer 4c: Check for dependencies
    if ([self hasReferences:did collection:collection rkey:rkey]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RecordService" 
                                         code:409 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Record has references"}];
        }
        return NO;
    }
    
    // Proceed with deletion
    return [self performDelete:did collection:collection rkey:rkey error:error];
}
```

#### Layer 5: Data Protection
- Encryption at rest (Keychain for secrets)
- Secure key storage
- Database encryption (optional)
- Secure deletion

```objc
// From Garazyk/Sources/Auth/KeychainManager.m
- (BOOL)storePrivateKey:(NSData *)keyData 
             identifier:(NSString *)identifier 
                  error:(NSError **)error {
    // Store in Keychain with hardware-backed protection
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: [identifier dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecValueData: keyData,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave  // Hardware-backed
    };
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain 
                                         code:status 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Failed to store key in Keychain"}];
        }
        return NO;
    }
    
    return YES;
}
```

### 2. Least Privilege

The principle of least privilege means granting only the minimum permissions necessary to perform a task.

**Implementation strategies:**

#### Token Scopes

Limit token capabilities to specific operations:

```objc
// Token with limited scopes
NSDictionary *tokenClaims = @{
    @"sub": did,
    @"iss": @"https://pds.garazyk.xyz",
    @"aud": @"https://pds.garazyk.xyz",
    @"exp": @(expirationTime),
    @"scope": @"com.atproto.repo.createRecord com.atproto.repo.getRecord"  // Limited scopes
};

// Verify scope before operation
- (BOOL)hasRequiredScopes:(NSString *)token forEndpoint:(NSString *)nsid {
    NSArray *tokenScopes = [self extractScopes:token];
    NSArray *requiredScopes = [self requiredScopesForEndpoint:nsid];
    
    for (NSString *required in requiredScopes) {
        if (![tokenScopes containsObject:required]) {
            return NO;
        }
    }
    
    return YES;
}
```

#### Database Permissions

Use separate database connections with minimal privileges:

```objc
// Read-only connection for queries
- (PDSDatabase *)readOnlyConnection {
    PDSDatabase *db = [[PDSDatabase alloc] initWithPath:self.dbPath];
    [db executeUpdate:@"PRAGMA query_only = ON" error:nil];
    return db;
}

// Write connection only when needed
- (BOOL)updateRecord:(NSDictionary *)record error:(NSError **)error {
    PDSDatabase *writeDB = [self writeConnection];
    BOOL success = [writeDB executeUpdate:@"UPDATE records SET value = ? WHERE id = ?" 
                                   params:@[record[@"value"], record[@"id"]] 
                                    error:error];
    [writeDB close];
    return success;
}
```

#### File System Permissions

Restrict file access to necessary directories:

```objc
- (BOOL)validateBlobPath:(NSString *)path error:(NSError **)error {
    // Ensure path is within blob directory
    NSString *resolvedPath = [path stringByStandardizingPath];
    NSString *blobDir = [self.blobDirectory stringByStandardizingPath];
    
    if (![resolvedPath hasPrefix:blobDir]) {
        if (error) {
            *error = [NSError errorWithDomain:@"BlobStorage" 
                                         code:403 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Path outside blob directory"}];
        }
        return NO;
    }
    
    return YES;
}
```

### 3. Fail Securely

When errors occur, fail in a way that maintains security rather than bypassing controls.

**Secure failure patterns:**

```objc
// Good: Fail securely on validation error
- (BOOL)processRequest:(XrpcRequest *)request error:(NSError **)error {
    // If validation fails, reject request
    if (![self validateRequest:request error:error]) {
        return NO;  // Secure failure
    }
    
    // Process validated request
    return [self handleRequest:request error:error];
}

// Bad: Continue on validation error
// if (![self validateRequest:request error:error]) {
//     PDS_LOG_WARN(@"Validation failed, continuing anyway");  // INSECURE!
// }
// return [self handleRequest:request error:error];

// Good: Deny by default
- (BOOL)isAuthorized:(NSString *)did forAction:(NSString *)action {
    // Explicit authorization required
    return [self.authorizationRules allowsDID:did action:action];
}

// Bad: Allow by default
// - (BOOL)isDenied:(NSString *)did forAction:(NSString *)action {
//     return [self.denyList containsDID:did];  // Allows unknown DIDs!
// }
```

### 4. Secure Defaults

Configure systems with secure settings by default, requiring explicit action to weaken security.

**Secure configuration defaults:**

```objc
// From Garazyk/Sources/App/ATProtoServiceConfiguration.m
- (instancetype)initWithDefaults {
    self = [super init];
    if (self) {
        // Secure defaults
        _requireInviteCode = YES;  // Require invite codes
        _rateLimitEnabled = YES;   // Enable rate limiting
        _debugMode = NO;           // Disable debug mode
        _logLevel = PDSLogLevelInfo;  // Info level (not debug)
        _maxRequestSize = 10 * 1024 * 1024;  // 10 MB limit
        _sessionTimeout = 3600;    // 1 hour
        _requireTLS = YES;         // Require HTTPS
        _plcURL = @"https://plc.directory";  // Production PLC
    }
    return self;
}
```

**Configuration validation:**

```objc
- (BOOL)validateConfiguration:(NSError **)error {
    // Warn about insecure settings
    if (!self.requireInviteCode) {
        PDS_LOG_WARN(@"Invite codes disabled - server is open to public registration");
    }
    
    if (self.debugMode) {
        PDS_LOG_WARN(@"Debug mode enabled - verbose logging may expose sensitive data");
    }
    
    if ([self.plcURL isEqualToString:@"mock"]) {
        PDS_LOG_ERROR(@"Mock PLC URL in production - DID resolution will fail");
        if (error) {
            *error = [NSError errorWithDomain:@"Configuration" 
                                         code:1 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Mock PLC URL not allowed in production"}];
        }
        return NO;
    }
    
    return YES;
}
```

### 5. Minimize Attack Surface

Reduce the number of potential entry points for attackers.

**Attack surface reduction strategies:**

#### Disable Unnecessary Features

```objc
// Conditional compilation for debug features
#if DEBUG
- (void)registerDebugEndpoints {
    [self.httpServer registerRoute:@"/debug/state" 
                           handler:^(HttpRequest *req, HttpResponse *res) {
        [res sendJSON:[self dumpInternalState]];
    }];
}
#endif

// Never expose debug endpoints in production
- (void)configureServer {
    [self registerProductionEndpoints];
    
#if DEBUG
    if (self.config.debugMode) {
        [self registerDebugEndpoints];
    }
#endif
}
```

#### Limit Exposed Endpoints

```objc
// Only expose necessary XRPC methods
- (void)registerXRPCMethods {
    // Core methods (always enabled)
    [self registerMethod:@"com.atproto.server.createSession"];
    [self registerMethod:@"com.atproto.repo.createRecord"];
    [self registerMethod:@"com.atproto.repo.getRecord"];
    
    // Admin methods (only if admin enabled)
    if (self.config.adminEnabled) {
        [self registerMethod:@"com.atproto.admin.disableInviteCodes"];
        [self registerMethod:@"com.atproto.admin.emitModerationEvent"];
    }
    
    // Experimental methods (only in development)
    if (self.config.experimentalFeaturesEnabled) {
        [self registerMethod:@"com.atproto.temp.experimental"];
    }
}
```

#### Remove Sensitive Information from Responses

```objc
- (NSDictionary *)sanitizeErrorResponse:(NSError *)error {
    // Never expose internal details to clients
    NSMutableDictionary *response = [NSMutableDictionary dictionary];
    
    response[@"error"] = @"InvalidRequest";
    response[@"message"] = @"The request could not be processed";
    
    // Only include details in development
#if DEBUG
    if (self.config.debugMode) {
        response[@"debug"] = @{
            @"domain": error.domain,
            @"code": @(error.code),
            @"description": error.localizedDescription
        };
    }
#endif
    
    return response;
}
```

## Secure Development Practices

### 1. Code Review Checklist

Before merging security-sensitive code, verify:

- [ ] Input validation at all entry points
- [ ] Authentication checks on protected endpoints
- [ ] Authorization checks for resource access
- [ ] Parameterized queries (no string concatenation in SQL)
- [ ] Sensitive data redacted from logs
- [ ] Error messages don't leak internal details
- [ ] Cryptographic operations use approved algorithms
- [ ] Secrets not hardcoded in source
- [ ] Rate limiting on resource-intensive operations
- [ ] Tests cover security requirements

### 2. Security Testing

**Unit Tests:**

```objc
- (void)testAuthenticationRequired {
    // Verify endpoint rejects unauthenticated requests
    XrpcRequest *request = [[XrpcRequest alloc] init];
    request.nsid = @"com.atproto.repo.createRecord";
    // No token provided
    
    XrpcResponse *response = [self.dispatcher handleRequest:request];
    
    XCTAssertEqual(response.statusCode, 401);
    XCTAssertEqualObjects(response.error, @"AuthenticationRequired");
}

- (void)testAuthorizationEnforced {
    // Verify user cannot access another user's data
    NSString *aliceDID = @"did:plc:alice";
    NSString *bobDID = @"did:plc:bob";
    
    NSString *aliceToken = [self createTokenForDID:aliceDID];
    
    XrpcRequest *request = [[XrpcRequest alloc] init];
    request.nsid = @"com.atproto.repo.deleteRecord";
    request.token = aliceToken;
    request.params = @{@"repo": bobDID, @"collection": @"app.bsky.feed.post", @"rkey": @"123"};
    
    XrpcResponse *response = [self.dispatcher handleRequest:request];
    
    XCTAssertEqual(response.statusCode, 403);
    XCTAssertEqualObjects(response.error, @"Forbidden");
}
```

**Integration Tests:**

```objc
- (void)testSQLInjectionPrevention {
    // Attempt SQL injection
    NSString *maliciousDID = @"did:plc:test' OR '1'='1";
    
    NSError *error = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:maliciousDID error:&error];
    
    // Should return nil (not found), not execute injection
    XCTAssertNil(account);
    XCTAssertNil(error);  // No error, just not found
}

- (void)testRateLimitingEnforced {
    NSString *did = @"did:plc:test";
    
    // Make requests up to limit
    for (int i = 0; i < 100; i++) {
        XrpcResponse *response = [self makeRequest:did];
        XCTAssertEqual(response.statusCode, 200);
    }
    
    // Next request should be rate limited
    XrpcResponse *response = [self makeRequest:did];
    XCTAssertEqual(response.statusCode, 429);
}
```

### 3. Dependency Management

**Verify dependencies:**

```bash
# Check for known vulnerabilities
osv-scanner --lockfile=package-lock.json

# Audit npm dependencies
npm audit

# Update dependencies regularly
npm update
```

**Pin dependency versions:**

```json
{
  "dependencies": {
    "sqlite3": "5.1.6",  // Pinned version
    "express": "4.18.2"
  }
}
```

## 4. Secrets Management

**Never commit secrets:**

```bash
# Add to .gitignore
config.json
*.key
*.pem
.env
secrets/
```

**Use environment variables:**

```objc
- (NSString *)getJWTSecret {
    // Read from environment, not config file
    NSString *secret = [[[NSProcessInfo processInfo] environment] objectForKey:@"JWT_SECRET"];
    
    if (!secret) {
        PDS_LOG_ERROR(@"JWT_SECRET environment variable not set");
        exit(1);
    }
    
    return secret;
}
```

**Rotate secrets regularly:**

```objc
- (void)rotateJWTSigningKey {
    // Generate new key
    NSData *newKey = [self generateSigningKey];
    
    // Store with version identifier
    [self.keychain storeKey:newKey identifier:@"jwt-signing-v2" error:nil];
    
    // Keep old key for verification during transition
    [self.keychain storeKey:self.currentKey identifier:@"jwt-signing-v1" error:nil];
    
    // Update current key reference
    self.currentKey = newKey;
    self.currentKeyVersion = 2;
}
```

## Incident Response

### 1. Security Monitoring

**Log security events:**

```objc
- (void)logSecurityEvent:(NSString *)event details:(NSDictionary *)details {
    NSMutableDictionary *logEntry = [NSMutableDictionary dictionary];
    logEntry[@"timestamp"] = [NSDate date];
    logEntry[@"event"] = event;
    logEntry[@"details"] = details;
    logEntry[@"severity"] = @"SECURITY";
    
    PDS_LOG_SECURITY(@"%@", logEntry);
    
    // Send to SIEM if configured
    if (self.siemEnabled) {
        [self.siemClient sendEvent:logEntry];
    }
}

// Usage
[self logSecurityEvent:@"AuthenticationFailure" 
               details:@{
                   @"did": did,
                   @"ip": request.remoteIP,
                   @"reason": @"Invalid token signature"
               }];
```

### 2. Alerting

**Configure alerts for suspicious activity:**

```objc
- (void)checkForSuspiciousActivity:(NSString *)did {
    // Check for rapid authentication failures
    NSInteger failureCount = [self.authFailureTracker countForDID:did 
                                                       inLastMinutes:5];
    if (failureCount > 10) {
        [self sendAlert:@"Possible brute force attack" 
                details:@{@"did": did, @"failures": @(failureCount)}];
    }
    
    // Check for unusual access patterns
    if ([self detectAnomalousAccess:did]) {
        [self sendAlert:@"Anomalous access pattern detected" 
                details:@{@"did": did}];
    }
}
```

### 3. Breach Response

**If a security breach is detected:**

1. **Contain:** Disable affected accounts, revoke tokens
2. **Investigate:** Review logs, identify scope
3. **Remediate:** Fix vulnerability, deploy patch
4. **Notify:** Inform affected users
5. **Learn:** Post-mortem, improve defenses

```objc
- (void)handleSecurityBreach:(NSString *)breachType affectedDIDs:(NSArray *)dids {
    // 1. Contain
    for (NSString *did in dids) {
        [self.accountService disableAccount:did reason:@"Security breach" error:nil];
        [self.tokenService revokeAllTokensForDID:did];
    }
    
    // 2. Log incident
    [self logSecurityEvent:@"SecurityBreach" 
                   details:@{
                       @"type": breachType,
                       @"affectedCount": @(dids.count)
                   }];
    
    // 3. Alert administrators
    [self sendAlert:@"SECURITY BREACH" 
            details:@{@"type": breachType, @"affected": @(dids.count)}];
    
    // 4. Initiate investigation
    [self startIncidentInvestigation:breachType affectedDIDs:dids];
}
```

## Compliance

### 1. Data Protection

**GDPR/Privacy considerations:**

- Implement data export (user can download their data)
- Implement data deletion (right to be forgotten)
- Minimize data collection
- Encrypt sensitive data
- Log access to personal data

```objc
- (NSDictionary *)exportUserData:(NSString *)did error:(NSError **)error {
    // Export all user data for GDPR compliance
    NSMutableDictionary *export = [NSMutableDictionary dictionary];
    
    export[@"account"] = [self.accountService getAccount:did error:error];
    export[@"records"] = [self.recordService getAllRecords:did error:error];
    export[@"blobs"] = [self.blobService getBlobMetadata:did error:error];
    
    return export;
}

- (BOOL)deleteUserData:(NSString *)did error:(NSError **)error {
    // Permanently delete all user data
    BOOL success = YES;
    
    success &= [self.recordService deleteAllRecords:did error:error];
    success &= [self.blobService deleteAllBlobs:did error:error];
    success &= [self.accountService deleteAccount:did error:error];
    
    // Log deletion for audit trail
    [self logSecurityEvent:@"UserDataDeleted" details:@{@"did": did}];
    
    return success;
}
```

### 2. Audit Logging

**Maintain audit trail:**

```objc
- (void)auditLog:(NSString *)action 
             did:(NSString *)did 
        resource:(NSString *)resource 
          result:(NSString *)result {
    NSDictionary *auditEntry = @{
        @"timestamp": [NSDate date],
        @"action": action,
        @"did": did,
        @"resource": resource,
        @"result": result,
        @"ip": self.currentRequest.remoteIP
    };
    
    // Write to audit log (separate from application logs)
    [self.auditLogger writeEntry:auditEntry];
}

// Usage
[self auditLog:@"DeleteRecord" 
           did:did 
      resource:[NSString stringWithFormat:@"%@/%@", collection, rkey]
        result:success ? @"SUCCESS" : @"FAILURE"];
```

## Related Documentation

- [Input Validation](../04-network-layer/input-validation) — Validation strategies
- [Security Audit Guide](../11-reference/security-audit-guide) — Using audit skills
- [Secrets Management](secrets-management) — Key storage and rotation
- [OAuth 2.0 with DPoP](oauth2-dpop) — Authentication implementation
- [Rate Limiting](../04-network-layer/rate-limiting) — DoS protection

## External Resources

- OWASP Secure Coding Practices: https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/
- NIST Cybersecurity Framework: https://www.nist.gov/cyberframework
- CIS Controls: https://www.cisecurity.org/controls
- AT Protocol Security: https://atproto.com/specs/security

## Related

- [Documentation Map](../11-reference/documentation-map.md)
- [Contributor Guide](../index.md)
- [Repository Documentation Index](../repo-index/index.md)

