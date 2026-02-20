# Security Validation Strategy for Objective-C PDS Implementation

## Executive Summary

Security validation strategy for the ATProto PDS Objective-C implementation using multiple analysis components: static analysis, fuzzing, and runtime sanitizers. External dependencies limited to Apple APIs.

## Security Analysis Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security Orchestrator                          │
├─────────────────┬─────────────────┬─────────────────────────────┤
│  Static Agent   │  Fuzzing Agent  │  Runtime Agent              │
│  (clang-tidy)   │  (libFuzzer)    │  (Sanitizers + Instruments) │
├─────────────────┼─────────────────┼─────────────────────────────┤
│ • Clang SA      │ • Input Fuzz    │ • AddressSanitizer          │
│ • Clang-Tidy    │ • Protocol Fuzz │ • UndefinedBehavior San.    │
│ • CodeQL        │ • Mutation      │ • ThreadSanitizer           │
│ • Security      │ • Corpus Mgmt   │ • Memory Debugger           │
└─────────────────┴─────────────────┴─────────────────────────────┘
```

---

## Static Analysis Component

### Tools
- **Clang Static Analyzer** (`scan-build`) - Built into Xcode/CommandLineTools
- **clang-tidy** - Part of LLVM toolchain
- **swiftlint static checks** - Not applicable (pure Obj-C)

### Check Categories

#### 1.1 Memory Safety Checks
```bash
# Run clang static analyzer
scan-build --use-cc=clang --use-c++=clang++ \
  xcodebuild -project ATProtoPDS.xcodeproj \
  -scheme ATProtoPDS -configuration Debug build
```

**Critical checks:**
- `bugprone-undefined-memory-manipulation` - memset/memcpy on non-trivial types
- `bugprone-dangling-handle` - Use-after-free patterns
- `bugprone-string-constructor` - Unsafe NSString creation
- `bugprone-misplaced-pointer-arithmetic-in-alloc` - Allocation errors
- `bugprone-suspicious-memset-usage` - Zero-initialization bugs

#### 1.2 C/Objective-C Security Checks
```bash
# Run targeted clang-tidy checks
clang-tidy ATProtoPDS/Sources/**/*.m \
  -checks='-*,bugprone-*,cert-*,clang-analyzer-*' \
  -header-filter='ATProtoPDS/.*' \
  -p build/
```

**Key checks:**
| Check | Description | Severity |
|-------|-------------|----------|
| `bugprone-unsafe-functions` | POSIX functions (gets, strcpy) | CRITICAL |
| `bugprone-reserved-identifier` | Double underscore prefixes | HIGH |
| `cert-err33-c` | Error handling for std functions | HIGH |
| `bugprone-signed-char-misuse` | Signed char overflow | HIGH |
| `bugprone-sizeof-expression` | sizeof on pointers | MEDIUM |

#### 1.3 Objective-C Specific Checks
```bash
clang-tidy ATProtoPDS/Sources/**/*.m \
  -checks='-*,objc-*' \
  -header-filter='ATProtoPDS/.*'
```

**Obj-C checks:**
| Check | Description |
|-------|-------------|
| `objc-avoid-nserror-init` | NSError initialization patterns |
| `objc-dealloc-in-category` | Dealloc in category (wrong) |
| `objc-missing-hash` | Missing hash implementation |
| `objc-nsdate-formatter` | DateFormatter thread safety |
| `objc-super-self` | super vs self in dealloc |

#### 1.4 Security/Cryptography Checks
```bash
clang-tidy ATProtoPDS/Sources/**/*.m \
  -checks='-*,security-*,crypto-*' \
  -header-filter='ATProtoPDS/.*'
```

**Cryptography validation:**
- Verify no `RAND_pseudo_bytes` (use `RAND_bytes`)
- Check constant-time comparisons (timing attacks)
- Validate IV generation patterns
- Check key storage (never in code)

### Configuration File: `.clang-tidy`
```yaml
Checks: >
  bugprone-*,
  cert-*,
  clang-analyzer-*,
  objc-*,
  -bugprone-reserved-identifier,
  -bugprone-move-forwarding-reference

HeaderFilterRegex: 'ATProtoPDS/.*'

WarningsAsErrors: >
  bugprone-undefined-memory-manipulation,
  bugprone-unsafe-functions,
  cert-err33-c,
  bugprone-signed-char-misuse

AnalyzeTemporaryDtors: false
```

---

## Fuzzing Component

### Tools
- **libFuzzer** - Built into LLVM/Clang
- **AddressSanitizer (ASAN)** - Built into Clang
- **UndefinedBehaviorSanitizer (UBSAN)** - Built into Clang

### Fuzzing Targets

#### 2.1 Network Input Fuzzing
```bash
# Fuzz XRPC handler
clang -fsanitize=fuzzer,address,undefined \
  -IATProtoPDS/Sources \
  ATProtoPDS/Sources/Network/XrpcHandler.m \
  fuzz_xrpc.m -o fuzz_xrpc

./fuzz_xrpc corpus_xrpc/ -max_len=65536 -jobs=8
```

**Fuzz harness template:**
```c
// fuzz_xrpc.m
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 10) return 0;
    
    NSData *input = [NSData dataWithBytes:data length:size];
    NSString *method = [NSString stringWithUTF8String:(const char *)data];
    NSData *body = [NSData dataWithBytes:data + method.length + 1 
                                   length:size - method.length - 1];
    
    // Call XRPC handler
    [XrpcHandler handleMethod:method body:body];
    
    return 0;
}
```

#### 2.2 CBOR/CAR Parsing Fuzzing
```c
// fuzz_cbor.m - Fuzz CBOR decoding
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0) return 0;
    
    NSData *cborData = [NSData dataWithBytes:data length:size];
    NSError *error = nil;
    
    // Fuzz CAR/CBOR parsing
    CARArchive *archive = [CARArchive archiveWithData:cborData error:&error];
    
    return 0;
}
```

#### 2.3 HTTP Request Fuzzing
```c
// fuzz_http.m - Fuzz HTTP parsing
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    NSString *raw = [[NSString alloc] initWithBytes:data 
                                              length:size 
                                            encoding:NSUTF8StringEncoding];
    if (!raw) return 0;
    
    HttpRequest *request = [HttpRequest parseRawRequest:raw];
    
    return 0;
}
```

### Sanitizer Configuration

#### Makefile Integration
```makefile
# Fuzzing build
FUZZ_CFLAGS = -fsanitize=fuzzer,address,undefined
FUZZ_CFLAGS += -g -O1
FUZZ_CFLAGS += -fno-omit-frame-pointer

fuzz: $(FUZZ_TARGETS)
	./fuzz_xrpc corpus/ -max_len=65536 -jobs=8
	./fuzz_cbor corpus_cbor/ -max_len=65536 -jobs=8
	./fuzz_http corpus_http/ -max_len=65536 -jobs=8

# Run with timeout
timeout 24h ./fuzz_xrpc corpus/ -max_len=65536 -jobs=8 || echo "Fuzzing complete or timeout"
```

### Corpus Management
```
fuzzing/
├── corpus_xrpc/       # XRPC method inputs
├── corpus_cbor/       # CAR/CBOR blobs  
├── corpus_http/       # HTTP requests
└── crashers/          # Crash inputs (analyze immediately)
```

---

## Runtime Security Component

### Sanitizers

#### 3.1 AddressSanitizer (ASAN)
Detects memory errors including buffer overflow, use-after-free, and double-free conditions.

```bash
# Build with ASAN
clang -fsanitize=address -g -O1 \
  -IATProtoPDS/Sources \
  ATProtoPDS/Sources/**/*.m \
  -o atprotopds_asan

# Run tests
ASAN_OPTIONS=detect_leaks=1:halt_on_error=0 \
  ./atprotopds_asan
```

#### 3.2 UndefinedBehaviorSanitizer (UBSAN)
Detects undefined behavior including integer overflow and null pointer dereference.

```bash
# Build with UBSAN
clang -fsanitize=undefined -g -O1 \
  -IATProtoPDS/Sources \
  ATProtoPDS/Sources/**/*.m \
  -o atprotopds_ubsan

# Run
UBSAN_OPTIONS=print_summary=1:halt_on_error=0 \
  ./atprotopds_ubsan
```

#### 3.3 ThreadSanitizer (TSAN)
Detects data races in concurrent code paths critical for PDS operations.

```bash
# Build with TSAN
clang -fsanitize=thread -g -O2 \
  -IATProtoPDS/Sources \
  ATProtoPDS/Sources/**/*.m \
  -o atprotopds_tsan
```

#### 3.4 Combined Sanitizers
```bash
# Combined sanitizer build for maximum coverage
clang -fsanitize=address,undefined,thread \
  -fsanitize-recover=address,undefined \
  -g -O1 \
  -IATProtoPDS/Sources \
  ATProtoPDS/Sources/**/*.m \
  -o atprotopds_full
```

### Runtime Configuration

```bash
# Sanitizer environment configuration
export ASAN_OPTIONS=\
  detect_leaks=1:\
  detect_stack_use_after_return=1:\
  detect_container_overflow=1:\
  detect_odr_violation=2:\
  halt_on_error=0:\
  symbolize=1:\
  print_summary=1

export UBSAN_OPTIONS=\
  print_summary=1:\
  halt_on_error=0:\
  (null Dereference=1,\
   IntegerOverflow=1,\
   ShiftBase=1)

export TSAN_OPTIONS=\
  halt_on_error=0:\
  report_at_exit_races=1:\
  detect_deadlocks=1
```

---

## C/Objective-C Vulnerabilities and Mitigations

### Memory Safety

| Vulnerability | Pattern | Mitigation |
|---------------|---------|------------|
| Buffer Overflow | `strcpy(buf, user_input)` | Use `strlcpy`, `NSString` APIs |
| Integer Overflow | `malloc(n * m)` | Check `n > SIZE_MAX / m` before multiply |
| Use-After-Free | `free(p); use(p)` | Use ARC, avoid manual `free` |
| Double-Free | `free(p); free(p)` | Set pointer to NULL after free |
| Format String | `printf(user_input)` | Use `NSLog`, never `printf` |

### Objective-C Specific

| Issue | Pattern | Safe Alternative |
|-------|---------|------------------|
| Retain Cycle | Strong delegate cycle | Use `weak` delegates |
| Dealloc Side Effects | `self.property` in dealloc | Direct ivar access |
| Thread Safety | UIKit from background | `dispatch_async` to main |
| NSZombie | Over-released object | Enable NSZombie for debug |

### Cryptography

| Issue | Anti-Pattern | Safe Alternative |
|-------|--------------|------------------|
| Constant Time | `memcmp(a, b, len)` | Use `openssl_memcmp` or custom |
| IV Reuse | Same IV for encryptions | Generate random IV each time |
| Weak RNG | `rand()` for keys | `arc4random_buf()`, `SecRandomCopyBytes` |
| Hardcoded Keys | `static NSString *key = @"..."` | Use Keychain, generate at runtime |

### Network Security

| Issue | Anti-Pattern | Safe Alternative |
|-------|--------------|------------------|
| Certificate Validation | Bypass `NSURLSession` validation | Always validate certificates |
| Plaintext HTTP | `http://` URLs | Use `https://` only |
| Hostname Bypass | `validatesDomainName=NO` | Never disable |

---

## Automated CI/CD Pipeline

### GitHub Actions Workflow Configuration

```yaml
name: Security Checks

on: [push, pull_request]

jobs:
  static-analysis:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install Xcode
        run: xcodebuild -version
      - name: Clang Static Analyzer
        run: |
          scan-build --use-cc=clang xcodebuild \
            -project ATProtoPDS.xcodeproj \
            -scheme ATProtoPDS \
            -configuration Debug build
      - name: Clang-Tidy
        run: |
          clang-tidy ATProtoPDS/Sources/**/*.m \
            -checks='bugprone-*,cert-*,clang-analyzer-*' \
            -header-filter='ATProtoPDS/.*' \
            -p build/ > clang_tidy_report.txt
          cat clang_tidy_report.txt

  fuzzing:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build Fuzzers
        run: |
          clang -fsanitize=fuzzer,address,undefined \
            fuzz_xrpc.m -o fuzz_xrpc
          clang -fsanitize=fuzzer,address \
            fuzz_cbor.m -o fuzz_cbor
      - name: Fuzz (24h timeout)
        run: |
          timeout 24h ./fuzz_xrpc corpus_xrpc/ -jobs=8 || true
          timeout 24h ./fuzz_cbor corpus_cbor/ -jobs=8 || true
      - name: Upload Crashes
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: fuzzing-crashes
          path: crashers/

  sanitizers:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build with ASAN
        run: |
          clang -fsanitize=address,undefined -g \
            ATProtoPDS/Sources/**/*.m \
            -o atprotopds_asan
      - name: Run Tests
        run: |
          ASAN_OPTIONS=halt_on_error=0 ./atprotopds_asan
```

---

## Secure Coding Checklist

### Pre-Review Requirements
- [ ] All `strcpy`/`sprintf` replaced with bounded alternatives
- [ ] All `malloc`/`free` pairs verified (or use ARC)
- [ ] Integer overflow checks on arithmetic operations
- [ ] No hardcoded secrets (keys, passwords, salts)
- [ ] NSError patterns used consistently

### Objective-C Specific
- [ ] Delegates declared as `weak`
- [ ] No `self.` in `dealloc`
- [ ] No UIKit/AppKit calls from background threads
- [ ] Proper `copy`/`mutableCopy` semantics
- [ ] `NSSecureCoding` for persisted data

### Cryptography
- [ ] `SecRandomCopyBytes` for RNG
- [ ] Constant-time comparisons for sensitive data
- [ ] No custom crypto implementations
- [ ] Proper IV/nonce generation
- [ ] Secure key storage (Keychain, not code)

### Network
- [ ] HTTPS only (no http://)
- [ ] Certificate validation enabled
- [ ] No hostname bypasses
- [ ] Rate limiting implemented

---

## Implementation Timeline

### Phase 1: Static Analysis
1. Run Clang Static Analyzer on entire codebase
2. Run clang-tidy with security checks
3. Fix all CRITICAL and HIGH severity issues
4. Add `.clang-tidy` configuration file

### Phase 2: Fuzzing Implementation
1. Create fuzzing harness for XRPC handler
2. Create fuzzing harness for CAR/CBOR parsing
3. Set up corpus with valid inputs
4. Run 24-hour fuzzing session
5. Analyze any crashes found

### Phase 3: Sanitizer Integration
1. Build with ASAN and run unit tests
2. Build with UBSAN and run unit tests
3. Build with TSAN and verify thread safety
4. Fix any sanitizer-detected issues

### Phase 4: Integration and Documentation
1. Add security checks to CI pipeline
2. Implement runtime exploit mitigations
3. Document security posture
4. Create security incident response plan

---

## Success Criteria

| Metric | Target | Current |
|--------|--------|---------|
| Static analysis violations (HIGH+) | 0 | TBD |
| Fuzzing crashes (24h) | 0 | TBD |
| ASAN errors | 0 | TBD |
| TSAN data races | 0 | TBD |
| Code coverage (fuzzed paths) | >80% | TBD |

---

## References and Resources

- [Clang Static Analyzer](https://clang-analyzer.llvm.org/)
- [Clang-Tidy Checks](https://clang.llvm.org/extra/clang-tidy/checks/)
- [libFuzzer Documentation](https://llvm.org/docs/LibFuzzer.html)
- [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)
- [CERT C Coding Standard](https://www.cert.org/secure-coding/)
- [Apple Security Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/)

---

## Related Documentation

- [Security Documentation Index](README.md) - Overview of all security docs
- [Security Testing Plan](SECURITY_TESTING_PLAN.md) - Detailed fuzzing strategies
- [Security Analysis Report](SECURITY_ANALYSIS_REPORT.md) - Current findings
- [Security Test Results](security_test_results.md) - Test execution results
- [SQL Injection Report](SQL_INJECTION_VULNERABILITY_REPORT.md) - SQL vulnerabilities
- [OAuth2 Security](../oauth2/security.md) - OAuth2 security implementation
- [Security Tests](../tests/05-security/README.md) - Security test documentation
