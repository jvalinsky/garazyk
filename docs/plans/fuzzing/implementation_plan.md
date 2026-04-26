# Fuzzer Implementation Plan

## Overview

This document details the implementation of 8 Objective-C/libFuzzer harness files for critical components in the ATProto PDS. Each harness targets a core parsing or validation layer with a history of security-critical bugs.

## Directory Structure

```
fuzzing/
├── harness/
│   ├── FuzzXrpcDispatcher.m
│   ├── FuzzCBORDecoder.m
│   ├── FuzzHttp1Parser.m
│   ├── FuzzJWT.m
│   ├── FuzzDPoP.m
│   ├── FuzzMimeTypeValidator.m
│   ├── FuzzPDSDatabase.m
│   ├── FuzzATProtoLexiconValidator.m
│   └── FuzzMST.m
└── corpus/
    ├── xrpc/
    ├── cbor/
    ├── http/
    ├── auth/
    ├── blob/
    ├── sql/
    ├── lexicon/
    └── mst/
```

---

## 1. XRPC Dispatcher Fuzzer

### File: `FuzzXrpcDispatcher.m`

### Target Function
```objc
[XrpcDispatcher handleRequest:request response:response]
```

### Input Type
- Raw HTTP/1.1 request bytes (method, path, headers, body)
- CBOR-encoded XRPC procedure call

### Approach
1. Feed raw HTTP request bytes to `HttpRequest`
2. Construct XRPC body from CBOR bytes
3. Call `handleRequest:response:`

### Dependencies / Setup
- `XrpcDispatcher` singleton via `[XrpcDispatcher sharedDispatcher]`
- Pre-register method handlers via `registerMethod:handler:`
- Mock `PDSController` for auth (if needed)

### Build
```
clang -fsanitize=fuzzer \
    -FuzzXrpcDispatcher.m \
    -IGarazyk/Sources \
    -framework Foundation \
    -framework Security \
    -o fuzzing/fuzz_xrpc
```

### Run
```
./fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/ -jobs=8 -runs=50000
```

### Priority: **P0** - High network attack surface

---

## 2. CBOR Decoder Fuzzer

### File: `FuzzCBORDecoder.m`

### Target Function
```objc
[CBORDecoder decode:data]
```

### Input Type
- Raw CBOR-encoded bytes (any valid or malformed)

### Approach
1. Feed arbitrary byte sequences
2. Check for:
   - Buffer over-reads
   - Infinite loops
   - Stack overflow from deeply nested structures
   - Integer overflow in length calculations
   - Memory exhaustion via massive arrays/byte strings

### Dependencies / Setup
- None (pure function)

### Build
```
clang -fsanitize=fuzzer,address,undefined \
    -FuzzCBORDecoder.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -o fuzzing/fuzz_cbor
```

### Run
```
./fuzzing/fuzz_cbor fuzzing/corpus_cbor/ -jobs=8 -runs=100000
```

### Priority: **P0** - Fundamental data format, exploited in past CVEs

---

## 3. HTTP/1.1 Parser Fuzzer

### File: `FuzzHttp1Parser.m`

### Target Function
```objc
[Http1Parser parseRequestFromData:error:]
// or via HttpRequest
[HttpRequest requestWithData:data]
```

### Input Type
- Raw HTTP/1.1 request bytes (partial, malformed, chunked)

### Approach
1. Feed malformed HTTP request bytes
2. Test:
   - Header injection
   - Response splitting
   - Oversized header values
   - Invalid UTF-8 in headers
   - Malformed chunked encoding
   - Connection: close vs Content-Length conflicts

### Dependencies / Setup
- Optional: `Http1Parser` instance for incremental parsing

### Build
```
clang -fsanitize=fuzzer \
    -FuzzHttp1Parser.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -framework Security \
    -o fuzzing/fuzz_http
```

### Run
```
./fuzzing/fuzz_http fuzzing/corpus_http/ -jobs=8 -runs=50000
```

### Priority: **P0** - Network entry point

---

## 4. JWT Fuzzer

### File: `FuzzJWT.m`

### Target Function
```objc
// Parsing
[JWT jwtWithData:data error:]
// Header parsing
[JWTHeader headerFromDictionary:error:]
// Verification
[JWTVerifier verifyJWT:secret:]
```

### Input Type
- JWT token strings (JWS format)
- JSON header/payload dictionaries

### Approach
1. Feed malformed JWT strings
2. Test:
   - Algorithm confusion (none vs HS256)
   - Key confusion attacks
   - Expired tokens
   - Invalid Base64URL
   - Malformed JSON in claims
   - Key ID spoofing

### Dependencies / Setup
- `JWTMinter` via `[JWTMinter minterForService:]`
- Test keys for verification

### Build
```
clang -fsanitize=fuzzer \
    -FuzzJWT.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -framework Security \
    -o fuzzing/fuzz_jwt
```

### Run
```
./fuzzing/fuzz_jwt fuzzing/corpus_auth/ -jobs=8 -runs=50000
```

### Priority: **P1** - Auth critical, but limited parser attack surface

---

## 5. DPoP Fuzzer

### File: `FuzzDPoP.m`

### Target Function
```objc
// Proof generation and verification
[OAuth2DPoPProof verifyProof:forURL:method:accessToken:nonce:]
[AuthCryptoDPoP createProofForURL:method:key:error:]
```

### Input Type
- DPoP proof JWT strings
- URLs and HTTP methods

### Approach
1. Feed malformed DPoP proofs
2. Test:
   - Invalid JWT structure
   - HTU/HTM mismatch
   - Invalid keythumbprint
   - Algorithm confusion
   - Nonce reuse

### Dependencies / Setup
- Test EC keys for proof generation
- `OAuth2DPoPProof` singleton

### Build
```
clang -fsanitize=fuzzer \
    -FuzzDPoP.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -framework Security \
    -o fuzzing/fuzz_dpop
```

### Run
```
./fuzzing/fuzz_dpop fuzzing/corpus_auth/ -jobs=8 -runs=50000
```

### Priority: **P1** - Auth critical for token binding

---

## 6. MIME Type Validator Fuzzer

### File: `FuzzMimeTypeValidator.m`

### Target Function
```objc
[MimeTypeValidator validateMimeType:error:]
// or via singleton
[[MimeTypeValidator sharedValidator] validateMimeType:error:]
```

### Input Type
- MIME type strings from user input (file upload, Content-Type header)

### Approach
1. Feed arbitrary MIME type strings
2. Test:
   - Buffer overflow from long strings
   - NULL byte injection
   - Invalid charset specifications
   - MIME type spoofing (filter bypass)
   - Parameter injection

### Dependencies / Setup
- `[MimeTypeValidator sharedValidator]` singleton
- Load magic bytes database if applicable

### Build
```
clang -fsanitize=fuzzer \
    -FuzzMimeTypeValidator.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -o fuzzing/fuzz_mime
```

### Run
```
./fuzzing/fuzz_mime fuzzing/corpus_blob/ -jobs=8 -runs=10000
```

### Priority: **P1** - File upload validation

---

## 7. SQLite Database Query Fuzzer

### File: `FuzzPDSDatabase.m`

### Target Function
```objc
// Query execution
[PDSDatabase executeQuery:error:]
[PDSDatabase executeUpdate:error:]
// Prepared statements
[PDSDatabase prepareStatement:error:]
```

### Input Type
- SQL query strings
- Parameter bindings

### Approach
1. Feed SQL strings directly
2. Test via PDS-specific table structures
3. Target:
   - SQL injection (though parameterized)
   - Query planner DoS
   - Large result sets
   - Lock contention
   - WAL checkpoint issues

### Dependencies / Setup
- `PDSDatabase` at temporary path
- Create test schema (users, records, repo_mst, etc.)
- Connection pool size of 1 to isolate

### Build
```
clang -fsanitize=fuzzer \
    -FuzzPDSDatabase.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -lsqlite3 \
    -o fuzzing/fuzz_sqlite
```

### Run
```
./fuzzing/fuzz_sqlite fuzzing/corpus_sql/ -jobs=8 -runs=10000
```

### Priority: **P1** - DoS and data integrity

---

## 8. ATProto Lexicon Validator Fuzzer

### File: `FuzzATProtoLexiconValidator.m`

### Target Function
```objc
// Validation
[ATProtoLexiconValidator validateRecord:schema:error:]
[ATProtoLexiconValidator validateObject:error:]
// Schema parsing
[ATProtoLexiconValidator parseSchemaFromJSON:]
```

### Input Type
- JSON objects matching ATProto lexicons
- Lexicon definitions

### Approach
1. Feed malformed JSON matching ATProto schemas
2. Test:
   - Recursive object validation (infinite nesting)
   - Large array expansion
   - Invalid CID formats
   - Wrong record types for schema
   - Missing vs null handling

### Dependencies / Setup
- `ATProtoLexiconValidator` with registry
- Load test lexicons from `Lexicons/` bundle
- Mock lex resolve via `XrpcLexiconResolver`

### Build
```
clang -fsanitize=fuzzer \
    -FuzzATProtoLexiconValidator.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -o fuzzing/fuzz_lexicon
```

### Run
```
./fuzzing/fuzz_lexicon fuzzing/corpus_lexicon/ -jobs=8 -runs=10000
```

### Priority: **P1** - Record validation layer

---

## 9. MST (Merkle Search Tree) Fuzzer

### File: `FuzzMST.m`

### Target Function
```objc
// MST parsing and operations
[MST nodeWithData:error:]
[MSTNode entryAtKey:error:]
[MST walkFromKey:toKey:withBlock:]
// CAR file reading
[CARReader readFromData:error:]
```

### Input Type
- Binary MST node data
- CAR (Content Addressable Repository) files

### Approach
1. Feed CAR/MST binary data
2. Test:
   - Buffer over-reads in CID parsing
   - Infinite recursion in tree walk
   - Massive tree depth
   - HashTree corruption detection
   - Key sorting violations

### Dependencies / Setup
- `CARReader` for CAR parsing
- `MSTPersistence` for MST operations
- Optional: mock block store

### Build
```
clang -fsanitize=fuzzer,address \
    -FuzzMST.m \
    -I/Users/jack/Software/garazyk/Garazyk/Sources \
    -framework Foundation \
    -o fuzzing/fuzz_mst
```

### Run
```
./fuzzing/fuzz_mst fuzzing/corpus_mst/ -jobs=8 -runs=10000
```

### Priority: **P1** - Repository data structure integrity

---

## Priority Ordering

| Priority | Component | Reason |
|----------|-----------|--------|
| P0 | CBOR Decoder | Past CVEs, fundamental to all data |
| P0 | XRPC Dispatcher | Network attack surface |
| P0 | HTTP/1.1 Parser | Network entry point |
| P1 | JWT | Authentication |
| P1 | DPoP | Token binding |
| P1 | MIME Type Validator | File upload validation |
| P1 | SQLite | DoS / data integrity |
| P1 | Lexicon Validator | Record validation |
| P1 | MST | Repository integrity |

---

## Implementation Notes

1. **Corpus Generation**: Start with valid samples, mutate with radamsa or similar
2. **LibFuzzer Integration**: Use `-fsanitize=fuzzer` for LLVM Fuzzer
3. **macOS Limitation**: DPoP/AuthCrypto require security framework (macOS only)
4. **SQLite Isolation**: Use in-memory or temporary files, single connection
5. **Timeout Handling**: Set `-runs=...` timeout to catch infinite loops

---

## Build System Integration

Add to `project.yml`:

```yaml
targets:
  fuzz_xrpc:
    type: tool
    sources: [fuzzing/harness/FuzzXrpcDispatcher.m]
    dependencies: [Library/PDSFoundation]
  
  fuzz_cbor:
    type: tool
    sources: [fuzzing/harness/FuzzCBORDecoder.m]
    dependencies: [Library/PDSFoundation]
  
  # ... repeat for each
```

---

## References

- `Garazyk/Sources/Network/XrpcHandler.m` - XrpcDispatcher
- `Garazyk/Sources/Repository/CBOR.m` - CBORDecoder
- `Garazyk/Sources/Network/Http1Parser.m` - HTTP parser
- `Garazyk/Sources/Auth/JWT.m` - JWT parsing
- `Garazyk/Sources/Auth/OAuth2Handler.m` - DPoP validation
- `Garazyk/Sources/Blob/MimeTypeValidator.m` - MIME validation
- `Garazyk/Sources/Database/PDSDatabase.*` - Query execution
- `Garazyk/Sources/Lexicon/ATProtoLexiconValidator.*` - Schema validation
- `Garazyk/Sources/Repository/MST.*` - MST operations
- `Garazyk/Sources/Repository/CAR.*` - CARReader