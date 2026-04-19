---
title: Input Validation
---

# Input Validation

Input validation is a critical security layer that prevents malicious data from entering the system. Garazyk PDS implements comprehensive validation strategies at multiple levels to protect against injection attacks, data corruption, and protocol violations.

## Overview

Input validation occurs at three distinct layers:

1. **Protocol Layer** — Validates AT Protocol identifiers (DIDs, handles, CIDs, NSIDs, TIDs)
2. **Network Layer** — Validates HTTP requests, XRPC parameters, and content types
3. **Application Layer** — Validates business logic constraints and data integrity

## Validation Strategies

### 1. Protocol Identifier Validation

The `ATProtoValidator` class provides static methods for validating AT Protocol identifiers according to specification requirements.

#### DID Validation

```objc
// From Garazyk/Sources/Core/ATProtoValidator.m

+ (BOOL)validateDID:(NSString *)did error:(NSError **)error {
    if (!did) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:1 
                                             userInfo:@{NSLocalizedDescriptionKey: @"DID cannot be nil"}];
        return NO;
    }

    // Supported methods: did:plc and did:web
    if ([did hasPrefix:@"did:plc:"]) {
        // did:plc:<24 chars base32>
        // Regex: ^did:plc:[a-z2-7]{24}$
        NSRegularExpression *regex = [NSRegularExpression 
            regularExpressionWithPattern:@"^did:plc:[a-z2-7]{24}$" 
            options:0 
            error:nil];
        if ([regex numberOfMatchesInString:did 
                                   options:0 
                                     range:NSMakeRange(0, did.length)] == 0) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                     code:2 
                                                 userInfo:@{NSLocalizedDescriptionKey: 
                                                     @"Invalid did:plc format. Must be lowercase base32 (24 chars)."}];
            return NO;
        }
        return YES;
    } else if ([did hasPrefix:@"did:web:"]) {
        // did:web:<hostname> or did:web:<hostname>:<path>
        NSString *identifier = [did substringFromIndex:8];
        if (identifier.length == 0 || [identifier containsString:@"/"]) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                     code:3 
                                                 userInfo:@{NSLocalizedDescriptionKey: 
                                                     @"Invalid did:web format."}];
            return NO;
        }

        NSArray<NSString *> *components = [identifier componentsSeparatedByString:@":"];
        for (NSString *component in components) {
            if (component.length == 0) {
                if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                         code:3 
                                                     userInfo:@{NSLocalizedDescriptionKey: 
                                                         @"Invalid did:web format."}];
                return NO;
            }
        }
        return YES;
    }

    if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                             code:4 
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             @"Unsupported DID method"}];
    return NO;
}
```

**Validation Rules:**
- `did:plc:` — Must be exactly 24 lowercase base32 characters (a-z, 2-7)
- `did:web:` — Must contain valid hostname, no slashes, colon-separated path components
- Rejects unsupported DID methods
- Returns detailed error messages for debugging

#### Handle Validation

```objc
// From Garazyk/Sources/Core/ATProtoValidator.m

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error {
    if (!handle) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:1 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"Handle cannot be nil"}];
        return NO;
    }

    // Maximum DNS hostname length
    if (handle.length > 253) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:5 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"Handle too long"}];
        return NO;
    }

    // Regex pattern for handle validation:
    // ^([a-zA-Z0-9](#)?\.)+[a-zA-Z](#)?$
    NSRegularExpression *regex = [NSRegularExpression 
        regularExpressionWithPattern:@"^([a-zA-Z0-9](#)?\\.)+[a-zA-Z](#)?$" 
        options:0 
        error:nil];
    
    if ([regex numberOfMatchesInString:handle 
                               options:0 
                                 range:NSMakeRange(0, handle.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:6 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"Invalid handle syntax"}];
        return NO;
    }

    return YES;
}
```

**Validation Rules:**
- Maximum length: 253 characters (DNS limit)
- Must be valid DNS hostname format
- Alphanumeric with hyphens, dot-separated labels
- Each label: 1-63 characters, cannot start/end with hyphen
- TLD must be alphabetic

#### CID Validation

```objc
// From Garazyk/Sources/Core/ATProtoValidator.m

+ (BOOL)validateCID:(NSString *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:1 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"CID cannot be nil"}];
        return NO;
    }

    // Must be CIDv1 base32 lowercase (starts with 'b')
    if (![cid hasPrefix:@"b"]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:8 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"CID must be base32 lowercase (start with 'b')"}];
        return NO;
    }
    
    // Check minimum length (CIDv1 with SHA-256 is typically 59 chars)
    if (cid.length < 10) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:14 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"CID too short"}];
        return NO;
    }

    // Check valid base32 chars (a-z, 2-7)
    NSRegularExpression *regex = [NSRegularExpression 
        regularExpressionWithPattern:@"^[a-z2-7]+$" 
        options:0 
        error:nil];
    NSString *content = [cid substringFromIndex:1];
    if ([regex numberOfMatchesInString:content 
                               options:0 
                                 range:NSMakeRange(0, content.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                                 code:10 
                                             userInfo:@{NSLocalizedDescriptionKey: 
                                                 @"Invalid base32 characters in CID"}];
        return NO;
    }

    return YES;
}
```

**Validation Rules:**
- Must start with 'b' (CIDv1 base32 indicator)
- Minimum length: 10 characters
- Only lowercase base32 characters (a-z, 2-7)
- Typical CIDv1 with SHA-256: 59 characters

### 2. MIME Type and Blob Validation

The `MimeTypeValidator` class enforces strict content type validation and size limits for blob uploads.

#### MIME Type Validation

```objc
// From Garazyk/Sources/Blob/MimeTypeValidator.m

- (BOOL)validateMimeType:(NSString *)mimeType error:(NSError **)error {
    if (!mimeType || mimeType.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorMalformed
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"MIME type cannot be empty"}];
        }
        return NO;
    }

    // Check if type is in any supported category
    if ([self.supportedImageTypes containsObject:mimeType] ||
        [self.supportedVideoTypes containsObject:mimeType] ||
        [self.supportedAudioTypes containsObject:mimeType] ||
        [self.supportedFontTypes containsObject:mimeType] ||
        [self.supportedModelTypes containsObject:mimeType] ||
        [self.supportedDocumentTypes containsObject:mimeType]) {
        return YES;
    }

    if (error) {
        *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                     code:MimeTypeErrorUnsupported
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                     [NSString stringWithFormat:@"Unsupported MIME type: %@", mimeType]}];
    }
    return NO;
}
```

#### Size Validation

```objc
// From Garazyk/Sources/Blob/MimeTypeValidator.m

- (BOOL)validateSize:(NSUInteger)fileSize 
         forMimeType:(NSString *)mimeType 
               error:(NSError **)error {
    NSUInteger maxSize = [self maxSizeForMimeType:mimeType];
    
    if (fileSize > maxSize) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorTooLarge
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: 
                                             [NSString stringWithFormat:
                                                 @"File size %lu exceeds limit %lu for type %@",
                                                 (unsigned long)fileSize,
                                                 (unsigned long)maxSize,
                                                 mimeType]
                                     }];
        }
        return NO;
    }
    
    return YES;
}
```

**Size Limits by Category:**
- Images: 5 MB (PNG, JPEG, GIF, WebP, AVIF, HEIC)
- Videos: 50 MB (MP4, WebM, QuickTime, MPEG)
- Audio: 10 MB (MP3, WAV, OGG, FLAC, AAC)
- Fonts: 10 MB (WOFF, WOFF2, TTF, OTF)
- 3D Models: 100 MB (GLTF, GLB, USDZ)
- Documents: 10 MB (PDF, JSON, XML)
- Applications: 5 MB (generic application types)

#### Magic Number Validation

Magic number validation prevents MIME type spoofing by verifying file headers match the claimed content type:

```objc
// From Garazyk/Sources/Blob/MimeTypeValidator.m

- (BOOL)validateMagicNumbers:(NSData *)data 
            forMimeType:(NSString *)claimedMimeType 
                  error:(NSError **)error {
    if (!data || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorMalformed
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Empty data cannot be validated"}];
        }
        return NO;
    }

    // Get expected magic numbers for claimed type
    NSArray<NSData *> *expectedMagicNumbers = [self magicNumbersForMimeType:claimedMimeType];
    
    if (expectedMagicNumbers.count == 0) {
        // No magic numbers defined for this type, skip validation
        return YES;
    }

    // Check if data starts with any expected magic number
    for (NSData *magicNumber in expectedMagicNumbers) {
        if (data.length >= magicNumber.length) {
            NSData *prefix = [data subdataWithRange:NSMakeRange(0, magicNumber.length)];
            if ([prefix isEqualToData:magicNumber]) {
                return YES;
            }
        }
    }

    if (error) {
        *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                     code:MimeTypeErrorMagicNumberMismatch
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                     [NSString stringWithFormat:
                                         @"File header does not match claimed MIME type %@",
                                         claimedMimeType]}];
    }
    return NO;
}
```

**Common Magic Numbers:**
- PNG: `89 50 4E 47 0D 0A 1A 0A`
- JPEG: `FF D8 FF`
- GIF: `47 49 46 38` (GIF8)
- PDF: `25 50 44 46` (%PDF)
- MP4: `66 74 79 70` (ftyp box)

### 3. Request Parameter Validation

XRPC handlers validate request parameters before processing:

```objc
// Pattern from Garazyk/Sources/Services/PDSAdminService.m

- (BOOL)disableInviteCodes:(NSArray<NSString *> *)codes
                  accounts:(nullable NSArray<NSString *> *)accounts
                     error:(NSError **)error {
    // Deduplicate and filter empty strings
    NSArray<NSString *> *validatedCodes = deduplicatedNonEmptyStringArray(codes);
    NSArray<NSString *> *accountIdentifiers = deduplicatedNonEmptyStringArray(accounts);
    
    // Require at least one parameter
    if (validatedCodes.count == 0 && accountIdentifiers.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.admin"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Must provide at least one code or account"}];
        }
        return NO;
    }

    // Validate DID format for account identifiers
    for (NSString *identifier in accountIdentifiers) {
        NSError *didValidationError = nil;
        if (![ATProtoValidator validateDID:identifier error:&didValidationError]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.admin"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: 
                                             [NSString stringWithFormat:
                                                 @"Invalid DID format: %@", identifier]}];
            }
            return NO;
        }
    }

    // Proceed with validated parameters
    // ...
}
```

### 4. Data Sanitization

Sanitization removes sensitive or internal-only data before external transmission:

```objc
// From Garazyk/Sources/Sync/EventFormatter.m

- (NSDictionary *)formatCommitEvent:(CommitEvent *)event {
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    
    payload[@"seq"] = @(event.seq);
    payload[@"did"] = event.did;
    payload[@"time"] = event.time;
    payload[@"blocks"] = event.blocks ?: [NSData data];
    
    // Sanitize ops to remove recordCBOR which is internal-only and huge
    // Per ATProto spec, the record data is in the blocks (CAR), not in the ops metadata
    NSMutableArray *sanitizedOps = [NSMutableArray arrayWithCapacity:event.ops.count];
    for (NSDictionary *op in event.ops) {
        if (op[@"recordCBOR"]) {
            NSMutableDictionary *cleanOp = [op mutableCopy];
            [cleanOp removeObjectForKey:@"recordCBOR"];
            [sanitizedOps addObject:cleanOp];
        } else {
            [sanitizedOps addObject:op];
        }
    }
    payload[@"ops"] = sanitizedOps;
    
    payload[@"blobs"] = event.blobs ?: @[];
    
    return payload;
}
```

## Attack Prevention

### SQL Injection Prevention

Garazyk PDS uses parameterized queries exclusively to prevent SQL injection:

```objc
// Safe: Parameterized query
NSString *sql = @"SELECT * FROM accounts WHERE did = ?";
NSArray *params = @[did];
NSArray *results = [database executeQuery:sql params:params error:&error];

// NEVER do this (vulnerable to SQL injection):
// NSString *sql = [NSString stringWithFormat:@"SELECT * FROM accounts WHERE did = '%@'", did];
```

### Path Traversal Prevention

Validate file paths to prevent directory traversal attacks:

```objc
- (NSString *)safePathForBlobCID:(NSString *)cid error:(NSError **)error {
    // Validate CID format first
    if (![ATProtoValidator validateCID:cid error:error]) {
        return nil;
    }
    
    // Use CID as filename (already validated, no path separators)
    NSString *blobPath = [self.blobDirectory stringByAppendingPathComponent:cid];
    
    // Verify resolved path is still within blob directory
    NSString *resolvedPath = [blobPath stringByStandardizingPath];
    NSString *resolvedBlobDir = [self.blobDirectory stringByStandardizingPath];
    
    if (![resolvedPath hasPrefix:resolvedBlobDir]) {
        if (error) {
            *error = [NSError errorWithDomain:@"BlobStorage"
                                         code:403
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Path traversal attempt detected"}];
        }
        return nil;
    }
    
    return resolvedPath;
}
```

### Command Injection Prevention

Never pass user input directly to shell commands. Use Foundation APIs instead:

```objc
// Safe: Use NSFileManager
NSError *error = nil;
[[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];

// NEVER do this (vulnerable to command injection):
// system([[NSString stringWithFormat:@"rm %@", filePath] UTF8String]);
```

### Cross-Site Scripting (XSS) Prevention

Escape HTML output when rendering user content:

```objc
- (NSString *)escapeHTML:(NSString *)input {
    NSMutableString *escaped = [input mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" 
                             withString:@"&amp;" 
                                options:NSLiteralSearch 
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" 
                             withString:@"&lt;" 
                                options:NSLiteralSearch 
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" 
                             withString:@"&gt;" 
                                options:NSLiteralSearch 
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" 
                             withString:@"&quot;" 
                                options:NSLiteralSearch 
                                  range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" 
                             withString:@"&#x27;" 
                                options:NSLiteralSearch 
                                  range:NSMakeRange(0, escaped.length)];
    return escaped;
}
```

## Validation Best Practices

### 1. Fail Securely

Always reject invalid input rather than attempting to "fix" it:

```objc
// Good: Reject invalid input
if (![ATProtoValidator validateDID:did error:&error]) {
    return nil;  // Fail securely
}

// Bad: Try to "fix" invalid input
// did = [self attemptToFixDID:did];  // Don't do this!
```

### 2. Validate Early

Validate input at the earliest possible point (network layer before application layer):

```objc
- (void)handleCreateRecord:(XrpcRequest *)request 
                  response:(XrpcResponse *)response {
    // Validate immediately
    NSString *did = request.params[@"repo"];
    if (![ATProtoValidator validateDID:did error:nil]) {
        [response sendError:400 message:@"Invalid DID format"];
        return;
    }
    
    // Now safe to proceed
    [self.recordService createRecord:did /* ... */];
}
```

### 3. Use Allowlists Over Denylists

Define what is allowed rather than what is forbidden:

```objc
// Good: Allowlist of supported types
NSSet *allowedTypes = [NSSet setWithArray:@[
    @"image/jpeg",
    @"image/png",
    @"image/gif"
]];
if (![allowedTypes containsObject:mimeType]) {
    return NO;
}

// Bad: Denylist of forbidden types
// NSSet *forbiddenTypes = [NSSet setWithArray:@[@"application/x-msdownload"]];
// if ([forbiddenTypes containsObject:mimeType]) return NO;
```

### 4. Provide Clear Error Messages

Error messages should be informative for developers but not leak sensitive information:

```objc
// Good: Specific but safe error
if (![ATProtoValidator validateDID:did error:&error]) {
    *error = [NSError errorWithDomain:@"ATProtoValidator"
                                 code:2
                             userInfo:@{NSLocalizedDescriptionKey: 
                                 @"Invalid did:plc format. Must be lowercase base32 (24 chars)."}];
    return NO;
}

// Bad: Leaks internal details
// *error = [NSError ... @"Database query failed: SELECT * FROM users WHERE did = '%@'", did];
```

### 5. Validate Length Limits

Always enforce maximum lengths to prevent buffer overflows and DoS attacks:

```objc
- (BOOL)validateRecordValue:(NSDictionary *)value error:(NSError **)error {
    // Enforce maximum record size (1 MB)
    NSData *serialized = [NSJSONSerialization dataWithJSONObject:value 
                                                         options:0 
                                                           error:nil];
    if (serialized.length > 1024 * 1024) {
        if (error) {
            *error = [NSError errorWithDomain:@"RecordService"
                                         code:413
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                         @"Record exceeds maximum size of 1 MB"}];
        }
        return NO;
    }
    
    return YES;
}
```

## Testing Validation Logic

Validation logic should be thoroughly tested with both valid and invalid inputs:

```objc
- (void)testDIDValidation {
    NSError *error = nil;
    
    // Valid DIDs
    XCTAssertTrue([ATProtoValidator validateDID:@"did:plc:z72i7hdynmk6r22z27h6tvur" error:&error]);
    XCTAssertTrue([ATProtoValidator validateDID:@"did:web:example.com" error:&error]);
    
    // Invalid DIDs
    XCTAssertFalse([ATProtoValidator validateDID:@"did:plc:UPPERCASE" error:&error]);
    XCTAssertFalse([ATProtoValidator validateDID:@"did:plc:tooshort" error:&error]);
    XCTAssertFalse([ATProtoValidator validateDID:@"did:unknown:test" error:&error]);
    XCTAssertFalse([ATProtoValidator validateDID:nil error:&error]);
}
```

## Related Documentation

- [Error Handling](error-handling) — Standardized error responses
- [Rate Limiting](rate-limiting) — Request throttling and DoS protection
- [Security Best Practices](../06-authentication/security-best-practices) — Defense in depth
- [Security Audit Guide](../11-reference/security-audit-guide) — Using audit skills

## References

- AT Protocol Specification: https://atproto.com/specs/atp
- OWASP Input Validation Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html
- CWE-20: Improper Input Validation: https://cwe.mitre.org/data/definitions/20.html\n\n## Related\n\n- [Documentation Map](../11-reference/documentation-map.md)\n- [Contributor Guide](../index.md)\n- [Repository Documentation Index](../repo-index/index.md)\n\n