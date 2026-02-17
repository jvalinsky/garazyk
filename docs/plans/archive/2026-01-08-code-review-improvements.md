# Code Review Improvement Plan

**Created:** 2026-01-08
**Author:** Code Review
**Scope:** Repository-wide improvement recommendations for new contributors

## Executive Summary

This plan addresses barriers for new contributors to the ATProtoPDS Objective-C project. The codebase has solid architecture and security practices, but needs structural fixes and documentation improvements to reduce onboarding friction.

## Priority Matrix

| Category | Impact | Effort | Priority |
|----------|--------|--------|----------|
| Fix test directory location | High | Low | P0 |
| Add test coverage reporting | High | Medium | P0 |
| Create CONTRIBUTING.md | High | Low | P0 |
| Add code style (.clang-format) | Medium | Low | P1 |
| Enable documentation warnings | Medium | Low | P1 |
| Fix clang-tidy violations | Medium | Medium | P1 |
| Add security headers | Medium | Low | P1 |
| Create documentation index | Medium | Low | P1 |
| Add issue/PR templates | Low | Low | P2 |
| Add build caching to CI | Low | Medium | P2 |
| Create Brewfile | Low | Low | P2 |
| Simplify AGENTS.md | Low | Low | P2 |

## P0 Tasks

### 1. Fix Test Directory Location

**Issue:** Tests exist at `tests/` but project.yml and Makefile reference `ATProtoPDS/Tests/`.

**Files affected:**
- `tests/` directory
- `project.yml` lines 81-112
- `Makefile` line 12
- `AGENTS.md` lines 208-210

**Action:**
```bash
# Move tests to correct location
mv tests ATProtoPDS/Tests
```

**Update references in:**
- `project.yml`: Change `- path: tests/` to `- path: ATProtoPDS/Tests/`
- `Makefile`: Change `TEST_SOURCES = $(wildcard ATProtoPDS/Tests/**/*.m)`
- `AGENTS.md`: Update test bundle path reference

### 2. Add Test Coverage Reporting

**Issue:** No code coverage metrics configured for CI or local development.

**Files affected:**
- `.github/workflows/ci.yml`
- `project.yml`

**Action:** Update CI workflow to generate coverage reports:

```yaml
# In build-and-test job, add after build:
- name: Generate Coverage Report
  env:
    SCHEME: $(cat default_scheme)
  run: |
    xcodebuild test \
      -scheme "$SCHEME" \
      -project ATProtoPDS.xcodeproj \
      -configuration Debug \
      -destination 'platform=macOS' \
      CODE_SIGNING_ALLOWED=NO \
      GCC_GENERATE_TEST_COVERAGE_FILES=YES \
      GCC_INSTRUMENT_PROGRAM_AREA_FILES=YES

    # Generate HTML report
    xcrun llvm-cov show \
      $(find ~/Library/Developer/Xcode/DerivedData -name "AllTests" -type f | head -1) \
      --instr-profile=Build/Profile.profdata \
      --format=html > coverage.html
```

### 3. Create CONTRIBUTING.md

**Issue:** No standardized contribution guide at project root.

**Files to create:** `CONTRIBUTING.md`

**Content:**
```markdown
# Contributing to ATProtoPDS

## Quick Start

```bash
# Clone and build
git clone https://github.com/jvalinsky/NSPds.git
cd NSPds

# Setup dependencies
brew install xcodegen llvm@18
cd secp256k1 && ./autogen.sh && ./configure && make && cd ..

# Generate project and build
xcodegen generate
make build

# Run tests
make test-unit
```

## Development Workflow

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/your-feature`
3. **Make** your changes with tests
4. **Run** tests: `make test-unit`
5. **Run** linter: `make clang-tidy`
6. **Commit** with clear messages (see below)
7. **Push** and create pull request

## Code Style

- Follow Apple's [Coding Guidelines for Cocoa](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CodingGuidelines/CodingGuidelines.html)
- Use `.clang-format` for formatting (run `make format` before committing)
- Enable documentation warnings in Xcode

## Commit Messages

Use conventional commits:

```
feat: add new API endpoint for search
fix: resolve memory leak in CBOR decoder
docs: update API documentation
test: add coverage for HTTP routing
refactor: simplify blob storage initialization
```

## Testing

```bash
# Run all unit tests
make test-unit

# Run specific test
./build/did_resolver_tests

# Run with coverage
xcodebuild test -scheme AllTests -configuration Debug GCC_GENERATE_TEST_COVERAGE_FILES=YES
```

## Submitting Changes

1. Ensure all tests pass
2. Run static analysis: `make clang-tidy`
3. Update documentation as needed
4. Create a descriptive PR description

## Getting Help

- Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- Review [DEVELOPER_GUIDE.md](docs/guides/DEVELOPER_GUIDE.md)
- Open an issue for questions
```

## P1 Tasks

### 4. Add Code Style (.clang-format)

**Issue:** No enforced code formatting standard.

**Files to create:** `.clang-format`

**Content:**
```yaml
BasedOnStyle: LLVM
ObjCBlockIndentationWidth: 4
ColumnLimit: 100
IndentWidth: 4
TabWidth: 4
UseTab: Never
AllowShortIfStatementsOnASingleLine: false
AllowShortLoopsOnASingleLine: false
BreakBeforeBraces: Allman
IndentCaseLabels: true
SpacesInParentheses: false
SpacesInSquareBrackets: false
SpaceAfterCStyleCast: false
```

**Add to Makefile:**
```makefile
format:
	clang-format -i -style=file ATProtoPDS/Sources/**/*.m
```

### 5. Enable Documentation Warnings

**Issue:** `CLANG_WARN_DOCUMENTATION_COMMENTS: NO` disables documentation enforcement.

**Files affected:** `project.yml`

**Action:** Change to `YES`:
```yaml
CLANG_WARN_DOCUMENTATION_COMMENTS: YES
```

### 6. Fix Clang-Tidy Violations

**Issue:** Static analysis warnings need resolution.

**Files affected:**
- `ATProtoPDS/Sources/Repository/CBOR.m`
- `ATProtoPDS/Sources/Database/PDSDatabase.m`

**Actions:**
1. CBOR.m: Extract hash case logic into helper method to eliminate branch cloning
2. PDSDatabase.m: Rename `_iso8601Formatter` to `iso8601Formatter` or use static storage

### 7. Add Security Headers

**Issue:** HTTP responses lack security headers.

**Files affected:** `ATProtoPDS/Sources/Network/HttpResponse.h/m`

**Action:** Add header constants and apply in responses:

```objc
// In HttpResponse.h
@interface HttpResponse : NSObject

+ (void)applySecurityHeaders:(NSMutableDictionary *)headers;

// Properties for security headers
@property (class, nonatomic, copy, readonly) NSString *xContentTypeOptions;
@property (class, nonatomic, copy, readonly) NSString *xFrameOptions;
@property (class, nonatomic, copy, readonly) NSString *contentSecurityPolicy;

@end

// In HttpResponse.m
+ (NSString *)xContentTypeOptions { return @"nosniff"; }
+ (NSString *)xFrameOptions { return @"DENY"; }
+ (NSString *)contentSecurityPolicy { return @"default-src 'self';"; }

+ (void)applySecurityHeaders:(NSMutableDictionary *)headers {
    headers[@"X-Content-Type-Options"] = self.xContentTypeOptions;
    headers[@"X-Frame-Options"] = self.xFrameOptions;
    headers[@"Content-Security-Policy"] = self.contentSecurityPolicy;
}
```

### 8. Create Documentation Index

**Issue:** Documentation is scattered without clear navigation.

**Files affected:** `docs/README.md`

**Action:** Replace with  index:

```markdown
# ATProtoPDS Documentation Index

## Getting Started
- [README.md](../README.md) - Project overview
- [QUICKSTART.md](guides/QUICKSTART.md) - 5-minute setup guide
- [CONTRIBUTING.md](../CONTRIBUTING.md) - How to contribute

## Development
- [DEVELOPER_GUIDE.md](guides/DEVELOPER_GUIDE.md) - Adding endpoints, code patterns
- [ARCHITECTURE.md](architecture/OVERVIEW.md) - System design overview
- [API Reference](http://localhost:2583/explore/api/docs) - Interactive API docs

## Testing
- [TEST_IMPLEMENTATION_PLAN.md](TEST_IMPLEMENTATION_PLAN.md) - Testing strategy
- [Security Testing](security/SECURITY_TESTING_IMPROVEMENT_PLAN.md) - Security test guidelines

## Troubleshooting
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [Debug Session](debug_session_2026-01-08.md) - Recent debugging notes

## Reference
- [Implementation Plans](plans/) - Historical implementation decisions
- [Research](research/) - Technical research and exploration
- [Security Reports](security/) - Security analysis and audits

## Architecture Diagrams
- [AT Protocol Models](architecture/atproto_data_models.md)
- [System Architecture](architecture/ARCHITECTURE_DIAGRAMS.md)
```

## P2 Tasks

### 9. Add Issue/PR Templates

**Files to create:**
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`
- `.github/PULL_REQUEST_TEMPLATE.md`

### 10. Add Build Caching to CI

**Files affected:** `.github/workflows/ci.yml`

### 11. Create Brewfile

**Files to create:** `Brewfile`

### 12. Simplify AGENTS.md

**Files affected:** `AGENTS.md`

**Action:** Create `AGENTS_QUICKREF.md` with essential commands only.

## Testing Checklist

After implementing changes, verify:

- [ ] `make build` succeeds
- [ ] `make test-unit` runs all tests
- [ ] `xcodebuild test` generates coverage data
- [ ] `make clang-tidy` shows no new warnings
- [ ] Xcode can discover and run tests
- [ ] CONTRIBUTING.md is accessible from project root

## Estimated Effort

| Task | Hours |
|------|-------|
| P0 tasks | 4-6 |
| P1 tasks | 8-12 |
| P2 tasks | 6-8 |
| **Total** | **18-26** |

## References

- Original code review: 2026-01-08
- Project README: [README.md](../README.md)
- Developer Guide: [DEVELOPER_GUIDE.md](guides/DEVELOPER_GUIDE.md)
- Troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
