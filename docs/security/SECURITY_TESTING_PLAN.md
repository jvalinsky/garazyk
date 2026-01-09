# ATProto PDS Security Testing Plan

**Generated:** 2026-01-07
**Purpose:** Comprehensive security testing for parsing exploits, SQL injection, and blob upload vulnerabilities

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Attack Surface Analysis](#attack-surface-analysis)
3. [Parsing Exploit Testing](#parsing-exploit-testing)
4. [SQL Injection Testing](#sql-injection-testing)
5. [Blob Upload Security Testing](#blob-upload-security-testing)
6. [Fuzzing Strategies](#fuzzing-strategies)
7. [Manual Testing Checklist](#manual-testing-checklist)
8. [Remediation Guidelines](#remediation-guidelines)

---

## Executive Summary

This document provides a comprehensive security testing plan for the Objective-C ATProto PDS implementation. The testing focuses on three critical areas:

| Category | Risk Level | Primary Concerns |
|----------|------------|------------------|
| Parsing Exploits | HIGH | CBOR/CAR buffer overflows, JSON injection, XRPC path traversal |
| SQL Injection | CRITICAL | SQLite query construction, parameter binding gaps |
| Blob Upload | HIGH | File type bypass, path traversal, content spoofing |

---

## Attack Surface Analysis

### Entry Points

```
                    ┌─────────────────────────┐
                    │     Network Layer       │
                    │  HTTP/WebSocket Server  │
                    └───────────┬─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  XRPC Handler │    │  Blob Storage   │    │  Admin API      │
│  (endpoints)  │    │  (uploadBlob)   │    │  (admin/*)      │
└───────┬───────┘    └────────┬────────┘    └────────┬────────┘
        │                     │                       │
        ▼                     ▼                       ▼
┌───────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ JSON Parser   │    │ MIME Validation │    │ SQL Queries     │
│ CBOR Parser   │    │ CID Generation  │    │ Auth Tokens     │
│ CAR Parser    │    │ Size Limits     │    │ DIDs/Handles    │
└───────────────┘    └─────────────────┘    └─────────────────┘
```

### Critical Files

| File | Purpose | Risk Score |
|------|---------|------------|
| `CBOR.m` | Binary format parsing | 9/10 |
| `CAR.m` | Repository serialization | 8/10 |
| `HttpRequest.m` | HTTP parsing | 8/10 |
| `PDSDatabase.m` | SQLite operations | 9/10 |
| `BlobStorage.m` | Blob handling | 8/10 |
| `XrpcHandler.m` | XRPC dispatch | 7/10 |
| `DID.m` | DID resolution | 6/10 |
| `MST.m` | Merkle Search Tree | 7/10 |

---

## Parsing Exploit Testing

### 1. CBOR Parsing Vulnerabilities

**Test Vectors:**

```python
# CBOR fuzzing categories
test_cases = {
    "integer_overflow": [
        "\x00",                    # 0
        "\x1b\xff\xff\xff\xff",   # Max uint64
        "\x20",                    # -1
        "\x3b\xff\xff\xff\xff",   # Min -2^64
    ],
    "array_bounds": [
        "\x82",                    # Array of 2, no items
        "\x99\xff\xff",            # Huge array count
        "\x5f",                    # Indefinite array start
    ],
    "map_attacks": [
        "\xa1",                    # Map of 1, no pairs
        "\xbf",                    # Indefinite map start
        "\xa1\x00\x00",            # Truncated map
    ],
    "string_attacks": [
        "\x60",                    # Empty string
        "\x78\xff" + "x"*65535,    # Huge string length
        "\x7f",                    # Indefinite string
        "\x61\xff",                # Overlong byte
    ],
    "special_types": [
        "\xf6",                    # null
        "\xf4",                    # false
        "\xf5",                    # true
        "\xf0",                    # undefined
        "\xff",                    # break
        "\xc0",                    # Tag 0 (date)
        "\xc1",                    # Tag 1 (epoch time)
    ],
    "nested_depth": [
        "\x81\x81\x81\x81\x81",    # Deep nesting
    ],
    "fraction_attacks": [
        "\xfb\x7f\xf0\x00\x00\x00\x00\x00\x00",  # +Infinity
        "\xfb\xff\xf0\x00\x00\x00\x00\x00\x00",  # -Infinity
        "\xfb\x7f\x7f\xff\xff\xff\xff\xff\xff",  # NaN
    ]
}
```

**Exploit Scenarios:**

1. **Integer Overflow**: `encodeCount` with large values causing buffer overflow
2. **Array Out-of-Bounds**: Iterating beyond allocated array size
3. **String Length Mismatch**: Allocating insufficient buffer for declared length
4. **Recursive Parsing**: Deep nesting causing stack overflow
5. **Float Conversion**: Malformed float encoding causing crash

**Fuzzing Corpus Addition:**

```c
// Add to fuzzing/corpus_cbor/
cbor_overflow_1.bin    // Integer overflow case
cbor_overflow_2.bin    // Array bounds
cbor_depth_10.bin      // Deep nesting
cbor_malformed_map.bin // Truncated map
cbor_huge_string.bin   // 64KB string
cbor_nested_array.bin  // Array of arrays
cbor_infinite_loop.bin // Indefinite length
```

### 2. CAR (Content Addressable Records) Attacks

**Test Vectors:**

```python
# CAR file attacks
car_attacks = {
    "header_corruption": [
        b"\x00\x00" + b"\x00" * 100,    # Wrong magic
        b"\xaa\x01" + b"\x00" * 10,     # Bad version
    ],
    "CID_malformed": [
        bytes([0x01, 0x71]) + b"\x00",  # Truncated CID
        bytes([0x01, 0x71]) * 100,      # Oversized CID
    ],
    "index_poisoning": [
        b"\x00" * 8 + b"\xff" * 8,      # Invalid block offset
        b"\x00" * 16,                   # Zero-length block
    ],
    "multi_root": [
        # Multiple roots with same CID
    ],
    "header_size_mismatch": [
        bytes([0x00, 0x00, 0x00, 0x10]) + b"\x00" * 8,  # Size mismatch
    ]
}
```

**Exploit Scenarios:**

1. **Off-by-One in Block Reading**: Reading one byte past buffer
2. **CID Hash Collision**: Malformed multihash causing DoS
3. **Archive Truncation**: Partial CAR file causing infinite loop
4. **Duplicate Block IDs**: Hash table collision attacks

### 3. HTTP Request Parsing Attacks

**Test Vectors:**

```python
# HTTP request fuzzing
http_attacks = {
    "header_injection": [
        "GET / HTTP/1.1\r\nHost: test\r\n\r\n",
        "GET /xrpc/test HTTP/1.1\r\nHost: test\r\nContent-Length: -1\r\n\r\n{}",
    ],
    "method_parsing": [
        "GET / HTTP/1.1\r\n\r\n",
        "PROPFIND / HTTP/1.1\r\n\r\n",
        "X-RPC-TEST / HTTP/1.1\r\n\r\n",
        "GET\x00 / HTTP/1.1\r\n\r\n",
    ],
    "path_traversal": [
        "GET /xrpc/../../../etc/passwd HTTP/1.1\r\n\r\n",
        "GET /xrpc/com.atproto.repo./../createRecord HTTP/1.1\r\n\r\n",
        "GET //xrpc/test HTTP/1.1\r\n\r\n",
        "GET /xrpc/test\x00 HTTP/1.1\r\n\r\n",
    ],
    "query_injection": [
        "GET /xrpc/test?repo=admin' OR '1'='1 HTTP/1.1\r\n\r\n",
        "GET /xrpc/test?limit=999999999 HTTP/1.1\r\n\r\n",
    ],
    "body_attacks": [
        "POST /xrpc/com.atproto.repo.createRecord HTTP/1.1\r\nContent-Length: 999999999\r\n\r\n",
        "POST /xrpc/test HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
    ],
    "encoding_attacks": [
        "GET /xrpc/test HTTP/1.1\r\nHost: test\r\n\r\n\x00\x00\x00",
        "GET /xrpc/test HTTP/1.1\r\nHost: test\r\n\r\n{invalid json",
    ]
}
```

**Exploit Scenarios:**

1. **Header Injection**: Injecting CRLF to add malicious headers
2. **Content-Length Attack**: Negative or huge content length
3. **Transfer-Encoding Abuse**: Chunked encoding edge cases
4. **Null Byte Injection**: Path with embedded null bytes
5. **HTTP Method Confusion**: Non-standard methods

### 4. JSON Parsing Attacks

**Test Vectors:**

```python
# JSON fuzzing
json_attacks = {
    "recursion": [
        '{"a": {"a": {"a": {"a": {"a": {"a": {"a": {"a": {"a": {"a": {"a":',
        '[[[[[[[[[[[[[[[[[[[[',
    ],
    "unicode_attacks": [
        '{"a": "\u0000"}',
        '{"a": "\xff\xfe"}',
        '{"a": "\uD800\uDFFF"}',  # Surrogate pair
    ],
    "number_overflow": [
        '{"a": 1e999999}',
        '{"a": -1e999999}',
        '{"a": 1.7976931348623157e+308}',
    ],
    "string_attacks": [
        '{"a": "' + 'x' * 100000 + '"}',
        '{"a": "\n\n\n\n\n\n\n\n\n\n"}',
        '{"a": "\x00\x01\x02\x03"}',
    ],
    "type_confusion": [
        '{"a": true}',
        '{"a": false}',
        '{"a": null}',
        '{"a": []}',
        '{"a": {}}',
    ],
    "encoding_attacks": [
        '{"a": "\u0041\u0042\u0043"}',  # Overlong UTF-8
        '{"a": "\xc0\x80"}',  # Overlong NUL
        '{"a": "\xed\xa0\x80"}',  # Surrogate
    ]
}
```

**Exploit Scenarios:**

1. **Stack Overflow**: Deep JSON nesting
2. **Integer Overflow**: Number parsing edge cases
3. **Memory Exhaustion**: Huge strings, deep arrays
4. **Encoding Attacks**: Overlong UTF-8, BOM injection

### 5. XRPC Endpoint Attacks

**Test Vectors:**

```python
# XRPC specific attacks
xrpc_attacks = {
    "nsid_injection": [
        "GET /xrpc/com.atproto.repo../createRecord HTTP/1.1\r\n\r\n",
        "GET /xrpc/../../../admin/getAccountInfo HTTP/1.1\r\n\r\n",
        "GET /xrpc/com.atproto.server\x00createSession HTTP/1.1\r\n\r\n",
    ],
    "method_confusion": [
        "GET /xrpc/com.atproto.server.createSession HTTP/1.1\r\n\r\n",  # Should be POST
        "POST /xrpc/com.atproto.server.getSession HTTP/1.1\r\n\r\n",    # Should be GET
    ],
    "param_overflow": [
        "GET /xrpc/com.atproto.repo.listRecords?limit=999999999 HTTP/1.1\r\n\r\n",
        "GET /xrpc/com.atproto.repo.listRecords?cursor=" + "x" * 10000 + " HTTP/1.1\r\n\r\n",
    ],
    "auth_bypass": [
        "GET /xrpc/com.atproto.admin.getAccountInfo HTTP/1.1\r\nAuthorization: Bearer invalid\r\n\r\n",
        "GET /xrpc/com.atproto.admin.getAccountInfo HTTP/1.1\r\nAuthorization: Basic YWRtaW46\r\n\r\n",
    ]
}
```

---

## SQL Injection Testing

### 1. Database Attack Surface

**Query Patterns in Codebase:**

```objective-c
// PDSDatabase.m - Potential injection points
- (NSArray *)queryWithSQL:(NSString *)sql parameters:(NSArray *)params;
- (BOOL)executeSQL:(NSString *)sql;
- (NSArray *)findRecordsWithCollection:(NSString *)collection 
                                  repo:(NSString *)repo
                                 limit:(NSInteger)limit
                                cursor:(NSString *)cursor;
```

**SQL Injection Test Cases:**

```python
# SQL injection test vectors
sql_injection_tests = {
    "union_based": [
        "' UNION SELECT * FROM users--",
        "' UNION SELECT username,password,email FROM users--",
        "' UNION SELECT 1,2,3,4,5--",
    ],
    "error_based": [
        "' OR 1=1--",
        "' OR 'x'='x'--",
        "'; DROP TABLE users--",
        "' OR 1=1;--",
    ],
    "boolean_based": [
        "' OR 1=1--",
        "' AND 1=1--",
        "' AND 1=2--",
    ],
    "time_based": [
        "' OR (SELECT CASE WHEN (1=1) THEN sleep(5) ELSE 0 END)--",
        "'; WAITFOR DELAY '0:0:5'--",
    ],
    "stacked_queries": [
        "'; SELECT * FROM users; DROP TABLE users;--",
        "'; INSERT INTO logs VALUES ('injection');--",
    ],
    "type_confusion": [
        "' OR 'test'::int = 'test'--",
        "' OR 1::text = '1'--",
    ],
    "xpath_injection": [
        "' OR 1=1--",
        "'; DECLARE @q VARCHAR(8000); EXEC(@q);--",
    ],
    "sqlite_specific": [
        "'; ATTACH DATABASE '/tmp/evil.db' AS evil;--",
        "'; SELECT load_extension('/tmp/malicious.so');--",
        "'; PRAGMA temp_store_directory='/tmp';--",
    ]
}
```

### 2. Column/Table Name Injection

**Test Cases:**

```python
# Column/table name injection
column_injection = {
    "order_by": [
        "repo",
        "collection",
        "createdAt",
        "1; DROP TABLE users;--",
        "' OR 1=1--",
        "null) UNION SELECT 1,2,3--",
    ],
    "select_columns": [
        "*",
        "repo, collection",
        "repo, (SELECT 1)--",
    ],
    "where_clause": [
        "repo='did:plc:test'",
        "repo='did:plc:test' OR 1=1",
        "repo='did:plc:test' UNION SELECT * FROM users--",
    ]
}
```

### 3. Prepared Statement Verification

**Checklist:**

```markdown
- [ ] All SELECT queries use parameterized statements
- [ ] All INSERT/UPDATE/DELETE use parameterized statements  
- [ ] Dynamic table/column names are validated against allowlist
- [ ] ORDER BY clauses use validated column names only
- [ ] LIMIT/OFFSET values are validated as integers
- [ ] Cursors are validated as base64 or alphanumeric
- [ ] No string concatenation in SQL queries
- [ ] Database file permissions restrict access
- [ ] WAL mode configured for concurrent access safety
```

---

## Blob Upload Security Testing

### 1. MIME Type Validation Bypass

**Test Cases:**

```python
# MIME type bypass tests
mime_bypass_tests = {
    "double_extension": [
        ("shell.php.jpg", "image/jpeg"),
        ("shell.jsp.png", "image/png"),
        ("shell.asp.gif", "image/gif"),
    ],
    "magic_bytes": [
        # GIF89a header for PHP file
        ("php_shell.gif", b"\x47\x49\x46\x38\x39\x61" + b"<?php system($_GET['cmd']); ?>"),
        # PNG header for malicious file
        ("malware.png", b"\x89PNG\r\n\x1a\n" + b"<?php"),
    ],
    "content_type_header": [
        ("test.php", "image/png"),
        ("test.jpg", "application/octet-stream"),
        ("test.txt", "text/html"),
    ],
    "polymorphic": [
        ("shell.php", b"<?php /*<?xml?><?x?>*/ eval(base64_decode('...'));"),
        ("shell.jpg", b"GIF89a<?php system($_GET['cmd']); ?>"),
    ]
}
```

### 2. File Size/Resource Attacks

**Test Cases:**

```python
# Resource exhaustion tests
resource_attacks = {
    "size_limits": [
        0,                          # Zero byte file
        1,                          # Single byte
        1024 * 1024 * 5,            # 5MB (within limit)
        1024 * 1024 * 50,           # 50MB (over limit)
        1024 * 1024 * 500,          # 500MB (way over)
    ],
    "compression_bomb": [
        # PNG that expands massively when parsed
        b"\x89PNG\r\n\x1a\n" + 
        b"\x00\x00\x00\rIHDR" +
        b"\x00\x00\xff\xff" +  # 65535 wide
        b"\x00\x00\xff\xff" +  # 65535 tall
        b"\x08\x02\x00\x00\x00" + b"\xf6\xd8\x90\x6b",
    ],
    "zip_bomb": [
        # Tiny ZIP that contains GB of data
        b"PK\x03\x04" + b"\x00" * 50,
    ],
    "memory_exhaustion": [
        b"x" * (1024 * 1024 * 100),  # 100MB string
        b"\x00" * (1024 * 1024 * 100),  # 100MB nulls
    ]
}
```

### 3. Path Traversal in Filenames

**Test Cases:**

```python
# Path traversal tests
path_traversal = {
    "absolute_paths": [
        "/etc/passwd",
        "/var/www/html/shell.php",
        "C:\\Windows\\System32\\config\\sam",
    ],
    "relative_paths": [
        "../../../etc/passwd",
        "..\\..\\..\\Windows\\System32\\config\\sam",
        "....//....//etc/passwd",
        "..%2F..%2Fetc%2Fpasswd",
    ],
    "null_byte_injection": [
        "shell.php\x00.jpg",
        "shell.php%00.jpg",
    ],
    "unicode_traversal": [
        "..%c0%af..%c0%afetc%c0%afpasswd",
        "..%e5%80%83..%e5%80%83etc%e5%80%83passwd",
    ]
}
```

### 4. Image-Specific Attacks

**Test Cases:**

```python
# Image parsing exploits
image_attacks = {
    "exif_metadata": [
        # Malicious EXIF with crafted field
        b"\xff\xd8\xff\xe0\x00\x10JFIF\x00" + b"\x00" * 1000,
        # EXIF with huge comment
        b"\xff\xd8\xff\xe1\x00\x1fEXIF\x00\x00" + b"x" * 100000,
    ],
    "png_chunks": [
        # PNG with recursive IDAT
        b"\x89PNG\r\n\x1a\n" + 
        b"\x00\x00\x00\rIHDR" + b"A" * 16 +
        b"\x00\x00\x00\x01IDAT" + b"x" * 100000,
        # PNG with malicious tEXt chunk
        b"\x89PNG\r\n\x1a\n" +
        b"\x00\x00\x00\rIHDR" + b"A" * 16 +
        b"\x00\x00\x00\x0atEXt" + b"\x00" + b"<?php",
    ],
    "imagebomb": [
        # Tiny image that renders huge
        b"GIF89a" + b"\x00" * 10,
        b"\x89PNG\r\n\x1a\n" + b"\x00" * 100,
    ],
    "libpng_cves": [
        # Known vulnerable PNG patterns
    ]
}
```

### 5. Archive-Based Attacks

**Test Cases:**

```python
# Archive parsing exploits
archive_attacks = {
    "zip_symlink": [
        # ZIP with symlink pointing to /etc/passwd
        b"PK\x03\x04\x14\x00\x00\x00\x08\x00" +
        b"\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
        b"\x00\x00\x00\x05\x00\x00\x00\x00" +
        b"../../../etc/passwd",
    ],
    "zip_absolute": [
        # ZIP with absolute path
        b"PK\x03\x04\x14\x00\x00\x00\x08\x00" +
        b"\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
        b"\x00\x00\x00\x1c\x00\x00\x00\x00" +
        b"/etc/passwd",
    ],
    "zip_bomb_zip": [
        # ZIP containing ZIP containing ZIP...
    ],
    "rar_password_bomb": [
        # Many RAR files with passwords
    ]
}
```

---

## Fuzzing Strategies

### 1. Enhanced Fuzzing Corpus

**Directory Structure:**

```
fuzzing/
├── corpus_cbor/
│   ├── basic/
│   ├── edge_cases/
│   ├── malformed/
│   └── crafted/
├── corpus_http/
│   ├── requests/
│   ├── responses/
│   └── edge_cases/
├── corpus_xrpc/
│   ├── valid_requests/
│   ├── malformed_requests/
│   └── edge_cases/
├── corpus_blob/
│   ├── images/
│   ├── archives/
│   └── malicious/
└── corpus_sql/
    ├── valid_queries/
    └── injection_attempts/
```

### 2. Fuzzing Recipes

**CBOR Fuzzer Enhancement:**

```c
// Add to fuzz_cbor.mm
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // ... existing CBOR tests ...
    
    // NEW: Test edge cases
    if (size > 0 && size < 100) {
        // Deep nesting
        NSMutableData *nested = [NSMutableData data];
        for (int i = 0; i < size; i++) {
            [nested appendBytes:"\x81" length:1];  // Array of 1
        }
        [nested appendBytes:data length:1];
        [CBORDecoder decode:nested];
    }
    
    // NEW: Test integer overflow
    if (size >= 8) {
        uint64_t val = *(uint64_t *)data;
        CBORValue *encoded = [CBORValue unsignedInteger:val];
        (void)encoded;
    }
    
    return 0;
}
```

**SQL Injection Fuzzer:**

```c
// NEW: fuzz_sqlite.mm
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 10000) return 0;
    
    @autoreleasepool {
        NSString *input = [[NSString alloc] initWithData:[NSData dataWithBytes:data length:size] 
                                               encoding:NSUTF8StringEncoding];
        if (!input) return 0;
        
        // Test injection vectors
        NSArray *tests = @[
            [NSString stringWithFormat:@"SELECT * FROM records WHERE repo='%@'", input],
            [NSString stringWithFormat:@"SELECT * FROM records WHERE collection='%@'", input],
            [NSString stringWithFormat:@"SELECT * FROM records ORDER BY %@", input],
        ];
        
        for (NSString *sql in tests) {
            // Validate - should fail if contains injection patterns
            BOOL hasInjection = [sql containsString:@"' OR"] || 
                               [sql containsString:@"UNION SELECT"] ||
                               [sql containsString:@"DROP TABLE"] ||
                               [sql containsString:@"--"];
            (void)hasInjection;
        }
    }
    return 0;
}
```

### 3. Fuzzing Commands

```bash
# Extended CBOR fuzzing
./fuzzing/fuzz_cbor fuzzing/corpus_cbor/ \
    -max_len=65536 \
    -jobs=8 \
    -timeout=60 \
    -detect_leaks=1 \
    -use_value_profile=1

# HTTP fuzzing with corpus expansion
./fuzzing/fuzz_http fuzzing/corpus_http/ \
    -max_len=65536 \
    -jobs=8 \
    -timeout=60

# XRPC fuzzing with auth vectors
./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ \
    -max_len=65536 \
    -jobs=8 \
    -timeout=60

# SQL injection fuzzing (NEW)
./fuzzing/fuzz_sqlite fuzzing/corpus_sql/ \
    -max_len=10000 \
    -jobs=4 \
    -timeout=30

# Blob fuzzing (NEW)
./fuzzing/fuzz_blob fuzzing/corpus_blob/ \
    -max_len=50000000 \
    -jobs=4 \
    -timeout=60
```

---

## Manual Testing Checklist

### 1. Authentication Testing

- [ ] Login with `' OR '1'='1` as password
- [ ] Login with `admin'--` as username
- [ ] JWT token manipulation (algorithm confusion)
- [ ] JWT token replay (expired token)
- [ ] DPoP token reuse
- [ ] Session fixation
- [ ] Account enumeration via login
- [ ] Brute force protection

### 2. Authorization Testing

- [ ] Access admin endpoints without admin token
- [ ] Access other user's data
- [ ] Privilege escalation
- [ ] IDOR on record access
- [ ] Broken access control on blob download

### 3. Input Validation Testing

- [ ] XSS via JSON fields
- [ ] CRLF injection in headers
- [ ] Unicode spoofing in handles/DIDs
- [ ] Null byte injection
- [ ] Path traversal in XRPC paths
- [ ] ReDoS via regex in parsing

### 4. Rate Limiting Testing

- [ ] Rate limit bypass via header manipulation
- [ ] Rate limit reset abuse
- [ ] Concurrent connection exhaustion

### 5. Repository Testing

- [ ] Malicious CAR file upload
- [ ] Repository commit injection
- [ ] MST manipulation
- [ ] CID hash collision

---

## Remediation Guidelines

### 1. Input Validation

```objective-c
// Sanitize all user input
- (NSString *)sanitizeSQLInput:(NSString *)input {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
    return [[input componentsSeparatedByCharactersInSet:[allowed invertedSet]] componentsJoinedByString:@""];
}

// Validate NSID format
- (BOOL)isValidNSID:(NSString *)nsid {
    NSRegularExpression *regex = [NSRegularExpression 
        regularExpressionWithPattern:@"^[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+$"
        options:0 error:nil];
    return [regex numberOfMatchesInString:nsid options:0 range:NSMakeRange(0, nsid.length)] == 1;
}
```

### 2. Parameterized Queries

```objective-c
// WRONG - vulnerable
- (NSArray *)queryRecords:(NSString *)collection {
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM records WHERE collection='%@'", collection];
    return [self executeSQL:sql];
}

// CORRECT - parameterized
- (NSArray *)queryRecords:(NSString *)collection {
    NSString *sql = @"SELECT * FROM records WHERE collection=?";
    return [self executeSQL:sql parameters:@[collection]];
}
```

### 3. Blob Upload Security

```objective-c
- (BOOL)validateBlobUpload:(NSData *)data mimeType:(NSString *)mimeType error:(NSError **)error {
    // Check size
    if (data.length > MAX_BLOB_SIZE) {
        return NO;
    }
    
    // Validate MIME type against magic bytes
    NSString *detectedType = [self detectMimeType:data];
    if (![self isAllowedMimeType:detectedType]) {
        return NO;
    }
    
    // Scan for malicious content
    if ([self containsMaliciousPattern:data]) {
        return NO;
    }
    
    return YES;
}
```

### 4. Safe Parsing

```objective-c
- (id)safeParseJSON:(NSData *)data error:(NSError **)error {
    // Limit depth to prevent stack overflow
    NSJSONReadingOptions options = NSJSONReadingAllowFragments;
    options |= NSJSONReadingMutableContainers;
    
    // Check size first
    if (data.length > MAX_JSON_SIZE) {
        if (error) *error = [NSError errorWithDomain:@"PDS" code:413 userInfo:nil];
        return nil;
    }
    
    return [NSJSONSerialization JSONObjectWithData:data options:options error:error];
}
```

---

## References

1. [OWASP File Upload Security](https://owasp.org/www-community/vulnerabilities/Unrestricted_File_Upload)
2. [SQL Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
3. [CBOR Security Considerations](https://datatracker.ietf.org/doc/html/rfc8949#section-10)
4. [ATProto Specifications](https://atproto.com/specs/xrpc)
5. [CVE-2024-7254 Protobuf](https://asec.ahnlab.com/en/84033/)
6. [SQLite Fuzzing](https://sqlite.org/afl/doc/trunk/README.md)
7. [PortSwigger File Upload Testing](https://portswigger.net/web-security/file-upload)

---

*This document should be updated as new vulnerabilities are discovered and as the codebase evolves.*
