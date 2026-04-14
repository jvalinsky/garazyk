# Findings Guide

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **Critical** | Test provides false confidence — passes without validating correctness | Fix immediately |
| **High** | Test likely doesn't test what it claims — significant gaps | Review and fix |
| **Medium** | Potential gaps — incomplete coverage or structural issues | Consider improving |
| **Low** | Minor quality issues — documentation, organization | Improve when convenient |

## Finding Types

### FalsePositiveDetectionRule (Critical)

**What it detects**: Tests that always pass regardless of whether the code under test is correct.

**Patterns**:
- Only `XCTAssertNotNil` checks (existence without value validation)
- Only `XCTAssertNoThrow` checks (no-crash without behavior validation)
- Trivial assertions like `XCTAssertTrue(YES)`
- Setup code without any assertions
- Assertions inside unreachable code blocks

**Fix**: Add assertions that validate actual values and behavior, not just existence.

---

### NameAssertionAlignmentRule (High)

**What it detects**: Tests whose assertions don't match what the test name claims to verify.

**Example**: `testJWTSignatureValidation` that only checks `XCTAssertNotNil(token)` — the name claims signature validation but assertions only check existence.

**Fix**: Either rename the test to match what it actually tests, or add assertions that validate the claimed behavior.

---

### SecurityTestRule (Critical)

**What it detects**: Security tests (OAuth, DPoP, JWT, SSRF, input validation, rate limiting) that don't actually validate security properties.

**Patterns detected**:
- OAuth/DPoP tests without signature rejection checks
- JWT tests without expiration/signature validation
- SSRF tests without URL rejection validation
- Input validation tests without malformed input rejection

**Fix**: Security tests must verify that invalid/malicious inputs are **rejected**, not just that valid inputs are accepted.

---

### AsyncTestRule (High)

**What it detects**: Async tests that may be flaky due to improper expectation handling.

**Patterns**:
- Expectations created but never fulfilled
- Expectations created but `waitForExpectations` never called
- Timeouts < 1s (too short) or > 30s (too long)
- `dispatch_async` without `XCTestExpectation`

**Fix**: Always create expectations, fulfill them in callbacks, and wait with reasonable timeouts (1-30s).

---

### CoverageGapRule (Medium-High)

**What it detects**: Tests that claim to test something but miss important aspects.

**Gap types**:
- Multiple claims (contains "And") with single assertion
- Error handling claims without exception assertions
- State transition claims without before/after checks
- Concurrency claims without race testing
- Performance claims without timing assertions

**Fix**: Add the missing validation aspect. E.g., for error handling, add `XCTAssertThrows`.

---

### AssertionQualityRule (Medium)

**What it detects**: Tests with too few or too many assertions, or predominately existence-only assertions.

**Thresholds**:
- < 2 assertions: may indicate incomplete testing
- \> 20 assertions: may indicate the test does too much
- Low quality score: too many `XCTAssertNotNil` vs value assertions like `XCTAssertEqual`

**Fix**: Aim for 2-15 focused assertions per test. Prefer value assertions over existence checks.

---

### TestDependencyRule (High)

**What it detects**: Tests that depend on external services, execution order, or shared state.

**Patterns**:
- Network calls to external URLs
- File system dependencies
- Database connections without cleanup
- Reading pre-existing state without setup
- Shared mutable state between tests

**Fix**: Mock external dependencies, use in-memory databases, ensure each test sets up its own state.

---

### MockStubRule (Medium)

**What it detects**: Poor mock/stub usage patterns.

**Patterns**:
- Over-mocking (>3 mocks in one test)
- Under-mocking (external deps like HTTP/DB not mocked)
- Unverified mock interactions (mock created but `verify` never called)

**Fix**: Mock only external boundaries. Verify important mock interactions. Keep mock count reasonable.

---

### TestDocumentationRule (Low)

**What it detects**: Complex tests without explanatory comments.

**Triggers**: Tests with >20 lines or >5 assertions with no comments.

**Fix**: Add comments explaining the test's purpose, setup rationale, and expected outcomes.

---

### IntegrationTestRule (Medium)

**What it detects**: Problems in integration tests.

**Patterns**:
- Single component (misclassified as integration)
- Missing resource cleanup
- Assertions only on intermediate states
- Unrealistic test environment

**Fix**: Integration tests should exercise multiple components, clean up resources, and assert on final outcomes.

---

### Other Rules

| Rule | What it checks |
|------|---------------|
| PropertyBasedTestRule | Recognized property patterns (round-trip, invariant, idempotence) |
| InteropTestRule | Fixture loading and reference comparison in interop tests |
| ParserSerializerRule | Round-trip companions for parser tests |
| CharacterizationTestRule | Specific value assertions in characterization tests |
| TestFixtureRule | Fixture file existence and usage in assertions |
| TestOrganizationRule | Directory structure and base class usage |

## Troubleshooting

### Too Many False Positives

Use severity filtering to focus on the most important findings:
```bash
./bin/test-audit-validator analyze --severity critical,high
```

### Specific Rule Producing Bad Results

File an issue with the test code that was incorrectly flagged. Rules can be tuned via confidence thresholds.
