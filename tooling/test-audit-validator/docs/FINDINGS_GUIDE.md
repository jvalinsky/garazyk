# Findings Guide

## Severity Levels

| Level | Meaning | Action |
|-------|---------|--------|
| **Critical** | False confidence: test passes without validating correctness. | Fix immediately. |
| **High** | Significant gaps: test likely fails to verify the claimed behavior. | Review and fix. |
| **Medium** | Potential gaps: incomplete coverage or structural issues. | Review and improve. |
| **Low** | Quality issues: organization or documentation. | Improve when convenient. |

## Core Rules

### FalsePositiveDetectionRule (Critical)
Identifies tests that pass without validating actual behavior.
- **Patterns**: `XCTAssertNotNil` or `XCTAssertNoThrow` only, `XCTAssertTrue(YES)`, or setup code without assertions.
- **Remediation**: Add assertions that validate specific values and state transitions.

### NameAssertionAlignmentRule (High)
Identifies tests where the name claims to verify behavior that the assertions do not cover.
- **Example**: `testJWTSignatureValidation` that only asserts the token is not nil.
- **Remediation**: Add assertions for the claimed behavior or rename the test.

### SecurityTestRule (Critical)
Identifies security tests (OAuth, DPoP, JWT, SSRF) that fail to validate rejection paths.
- **Patterns**: Tests missing checks for signature rejection, expiration, or malformed input.
- **Remediation**: Verify that malicious or invalid inputs result in rejection.

### AsyncTestRule (High)
Identifies potentially flaky async tests.
- **Patterns**: Expectations that are never fulfilled or waited upon, or timeouts outside the 1-30s range.
- **Remediation**: Ensure every expectation is fulfilled and explicitly waited upon with a reasonable timeout.

### CoverageGapRule (Medium-High)
Identifies tests missing key validation aspects.
- **Patterns**: Single assertions for multiple claims, missing error handling assertions, or missing before/after state checks.
- **Remediation**: Add validation for all aspects mentioned in the test name or intent.

### AssertionQualityRule (Medium)
Identifies weak assertion mixes or suspicious counts.
- **Patterns**: Tests with fewer than 2 or more than 20 assertions, or excessive use of existence checks over value equality.
- **Remediation**: Aim for 2-15 focused value assertions per test.

### TestDependencyRule (High)
Identifies tests with external dependencies or order coupling.
- **Patterns**: External network calls, unmanaged file system access, or shared mutable state.
- **Remediation**: Mock external boundaries and use in-memory databases or temporary directories.

### MockStubRule (Medium)
Identifies poor mock usage.
- **Patterns**: Over-mocking (>3 mocks) or unverified interactions.
- **Remediation**: Mock only external boundaries and verify interactions that impact behavior.

### IntegrationTestRule (Medium)
Identifies issues in multi-component tests.
- **Patterns**: Single-component tests misclassified as integration, or missing resource cleanup.
- **Remediation**: Verify interactions between multiple real components and ensure environment cleanup.

## Rule Reference

| Rule | Description |
|------|-------------|
| PropertyBasedTestRule | Detects property-style patterns (round-trip, invariant). |
| InteropTestRule | Verifies fixture loading in interop tests. |
| ParserSerializerRule | Ensures round-trip companions exist for parser tests. |
| CharacterizationTestRule | Checks for specific-value assertions. |
| TestFixtureRule | Validates fixture file existence and usage. |
| TestOrganizationRule | Checks for base class usage and directory structure. |

## Troubleshooting

- **False Positives**: Filter by severity using `--severity critical,high` to focus on high-impact findings.
- **Rule Tuning**: Rules can be tuned via confidence thresholds in the rule definitions.
