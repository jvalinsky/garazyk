# Requirements Document

## Introduction

This document specifies requirements for a comprehensive audit system that validates whether test code in the September PDS codebase actually tests what it claims to test. The system will analyze 1017 tests across 155+ test classes to identify mismatches between test names/descriptions and their actual assertions, detect tests that don't validate their claimed functionality, and ensure property-based tests properly validate correctness properties.

The audit targets all test code in `Garazyk/Tests/` including Core (CBOR, CAR, CID, MST), Auth (OAuth, DPoP, JWT), Network (XRPC), Database (SQLite), Repository, Sync/Firehose, Identity (DID/handle resolution), and other subsystems.

## Glossary

- **Test_Audit_System**: The automated analysis tool that validates test correctness
- **Test_Case**: An individual test method discovered via ObjC runtime reflection
- **Test_Assertion**: XCTest assertion calls (XCTAssertEqual, XCTAssertTrue, etc.)
- **Test_Name**: The method name of a test (e.g., testOAuthTokenValidation)
- **Property_Based_Test**: Tests that validate general correctness properties across many inputs
- **Characterization_Test**: Tests that capture current behavior for regression detection
- **Test_Coverage_Gap**: Functionality claimed by test name but not validated by assertions
- **False_Positive_Test**: Test that passes but doesn't actually validate the claimed behavior
- **Assertion_Mismatch**: When test assertions don't align with test name/description
- **Test_Fixture**: Test data or setup code used across multiple tests
- **Interop_Test**: Tests validating compatibility with AT Protocol reference implementations

## Requirements

### Requirement 1: Test Name Analysis

**User Story:** As a developer, I want to analyze test method names, so that I can identify what each test claims to validate

#### Acceptance Criteria

1. WHEN a test file is provided, THE Test_Audit_System SHALL extract all test method names using ObjC runtime reflection patterns
2. THE Test_Audit_System SHALL parse test names to identify the claimed functionality (e.g., "testOAuthTokenValidation" claims to test OAuth token validation)
3. THE Test_Audit_System SHALL categorize tests by domain (Auth, Network, Database, Repository, Sync, Identity, Core, Security)
4. THE Test_Audit_System SHALL identify test naming patterns (test*, testThat*, testShould*, testWhen*)
5. THE Test_Audit_System SHALL extract semantic meaning from camelCase test names

### Requirement 2: Assertion Extraction

**User Story:** As a developer, I want to extract all assertions from test code, so that I can understand what each test actually validates

#### Acceptance Criteria

1. WHEN a test method is analyzed, THE Test_Audit_System SHALL identify all XCTest assertion calls (XCTAssertEqual, XCTAssertTrue, XCTAssertNil, XCTAssertNotNil, XCTAssertThrows, etc.)
2. THE Test_Audit_System SHALL extract the arguments passed to each assertion
3. THE Test_Audit_System SHALL identify the variables and expressions being asserted
4. THE Test_Audit_System SHALL detect conditional assertions within if/else blocks
5. THE Test_Audit_System SHALL track assertion count per test method
6. IF a test method contains zero assertions, THEN THE Test_Audit_System SHALL flag it as potentially invalid

### Requirement 3: Name-Assertion Alignment Validation

**User Story:** As a developer, I want to validate that test assertions match test names, so that I can identify tests that don't test what they claim

#### Acceptance Criteria

1. WHEN a test name claims to validate OAuth token generation, THE Test_Audit_System SHALL verify assertions check token properties
2. WHEN a test name claims to validate error handling, THE Test_Audit_System SHALL verify assertions check for expected errors or exceptions
3. WHEN a test name claims to validate data persistence, THE Test_Audit_System SHALL verify assertions check retrieved data matches stored data
4. WHEN a test name claims to validate parsing, THE Test_Audit_System SHALL verify assertions check parsed output structure
5. IF test assertions don't relate to the claimed functionality, THEN THE Test_Audit_System SHALL report an Assertion_Mismatch
6. THE Test_Audit_System SHALL calculate a confidence score (0-100) for name-assertion alignment

### Requirement 4: Property-Based Test Validation

**User Story:** As a developer, I want to validate property-based tests, so that I can ensure they test meaningful correctness properties

#### Acceptance Criteria

1. WHEN a test uses property-based testing patterns, THE Test_Audit_System SHALL identify the correctness property being tested
2. THE Test_Audit_System SHALL verify round-trip properties test bidirectional operations (encode/decode, serialize/deserialize, parse/print)
3. THE Test_Audit_System SHALL verify invariant properties test conditions that must always hold
4. THE Test_Audit_System SHALL verify idempotence properties test operations where f(x) = f(f(x))
5. THE Test_Audit_System SHALL verify metamorphic properties test relationships between inputs and outputs
6. THE Test_Audit_System SHALL verify model-based properties compare optimized vs reference implementations
7. IF a property-based test doesn't validate a recognized correctness property, THEN THE Test_Audit_System SHALL flag it for review

### Requirement 5: Parser and Serializer Test Validation

**User Story:** As a developer, I want to validate parser/serializer tests, so that I can ensure critical round-trip properties are tested

#### Acceptance Criteria

1. WHEN analyzing CBOR serialization tests, THE Test_Audit_System SHALL verify round-trip properties are tested (encode → decode → encode)
2. WHEN analyzing CAR format tests, THE Test_Audit_System SHALL verify parsing and writing are both tested
3. WHEN analyzing MST tests, THE Test_Audit_System SHALL verify tree structure invariants are validated
4. WHEN analyzing JSON/CBOR interop tests, THE Test_Audit_System SHALL verify bidirectional conversion is tested
5. IF a parser test exists without a corresponding round-trip test, THEN THE Test_Audit_System SHALL report a Test_Coverage_Gap
6. IF a serializer test exists without a pretty-printer test, THEN THE Test_Audit_System SHALL report a Test_Coverage_Gap

### Requirement 6: Security Test Validation

**User Story:** As a developer, I want to validate security tests, so that I can ensure they actually test security properties

#### Acceptance Criteria

1. WHEN analyzing OAuth/DPoP tests, THE Test_Audit_System SHALL verify cryptographic signature validation is tested
2. WHEN analyzing JWT tests, THE Test_Audit_System SHALL verify token expiration and signature checks are tested
3. WHEN analyzing SSRF protection tests, THE Test_Audit_System SHALL verify malicious URLs are rejected
4. WHEN analyzing input validation tests, THE Test_Audit_System SHALL verify malformed inputs are rejected
5. WHEN analyzing rate limiting tests, THE Test_Audit_System SHALL verify requests are throttled after limits
6. IF a security test name claims protection but assertions don't verify rejection, THEN THE Test_Audit_System SHALL report a False_Positive_Test

### Requirement 7: Interop Test Validation

**User Story:** As a developer, I want to validate interop tests, so that I can ensure AT Protocol compliance is actually tested

#### Acceptance Criteria

1. WHEN analyzing MST interop tests, THE Test_Audit_System SHALL verify test fixtures from atproto-interop-tests are used
2. WHEN analyzing CAR interop tests, THE Test_Audit_System SHALL verify compatibility with reference implementations is tested
3. WHEN analyzing CBOR interop tests, THE Test_Audit_System SHALL verify canonical encoding matches reference outputs
4. THE Test_Audit_System SHALL verify interop tests load fixture data from `Garazyk/Tests/fixtures/`
5. IF an interop test doesn't compare against reference implementation outputs, THEN THE Test_Audit_System SHALL report an Assertion_Mismatch

### Requirement 8: Characterization Test Validation

**User Story:** As a developer, I want to validate characterization tests, so that I can ensure they capture meaningful behavior

#### Acceptance Criteria

1. WHEN analyzing characterization tests, THE Test_Audit_System SHALL identify what behavior is being captured
2. THE Test_Audit_System SHALL verify characterization tests assert specific output values or states
3. THE Test_Audit_System SHALL verify characterization tests document why the behavior is being captured
4. IF a characterization test only checks for non-null results without validating specific values, THEN THE Test_Audit_System SHALL flag it as weak
5. THE Test_Audit_System SHALL distinguish characterization tests from regression tests

### Requirement 9: Test Fixture Validation

**User Story:** As a developer, I want to validate test fixtures, so that I can ensure they provide meaningful test data

#### Acceptance Criteria

1. WHEN analyzing tests using fixtures, THE Test_Audit_System SHALL identify which fixture files are loaded
2. THE Test_Audit_System SHALL verify fixture data is actually used in assertions
3. THE Test_Audit_System SHALL detect unused fixture data
4. THE Test_Audit_System SHALL verify fixture paths exist in `Garazyk/Tests/fixtures/`
5. IF a test loads fixtures but doesn't assert against fixture data, THEN THE Test_Audit_System SHALL report a Test_Coverage_Gap

### Requirement 10: False Positive Detection

**User Story:** As a developer, I want to detect false positive tests, so that I can identify tests that pass without validating behavior

#### Acceptance Criteria

1. THE Test_Audit_System SHALL detect tests that only assert non-null results without checking values
2. THE Test_Audit_System SHALL detect tests that only assert method calls don't throw exceptions
3. THE Test_Audit_System SHALL detect tests that assert trivial conditions (e.g., XCTAssertTrue(YES))
4. THE Test_Audit_System SHALL detect tests that set up state but don't verify state changes
5. THE Test_Audit_System SHALL detect tests with assertions in unreachable code paths
6. WHEN a False_Positive_Test is detected, THE Test_Audit_System SHALL report the test name and reason

### Requirement 11: Coverage Gap Identification

**User Story:** As a developer, I want to identify coverage gaps, so that I can find functionality that needs better testing

#### Acceptance Criteria

1. THE Test_Audit_System SHALL identify test names that claim to test multiple behaviors but only assert one
2. THE Test_Audit_System SHALL identify error handling claims without exception assertions
3. THE Test_Audit_System SHALL identify state transition claims without before/after state assertions
4. THE Test_Audit_System SHALL identify concurrency claims without race condition testing
5. THE Test_Audit_System SHALL identify performance claims without timing assertions
6. WHEN a Test_Coverage_Gap is identified, THE Test_Audit_System SHALL report the gap type and location

### Requirement 12: Test Organization Validation

**User Story:** As a developer, I want to validate test organization, so that I can ensure tests are properly structured

#### Acceptance Criteria

1. THE Test_Audit_System SHALL verify test classes are registered in the testClasses array in test_main.m
2. THE Test_Audit_System SHALL detect test classes that exist but aren't registered
3. THE Test_Audit_System SHALL verify test files are in appropriate subdirectories (Auth/, Network/, Core/, etc.)
4. THE Test_Audit_System SHALL detect test helper classes vs actual test classes
5. THE Test_Audit_System SHALL verify test base classes (e.g., CharacterizationTestBase) are properly used

### Requirement 13: Assertion Quality Analysis

**User Story:** As a developer, I want to analyze assertion quality, so that I can identify weak or ineffective assertions

#### Acceptance Criteria

1. THE Test_Audit_System SHALL calculate assertion density (assertions per test method)
2. THE Test_Audit_System SHALL identify tests with only one assertion as potentially incomplete
3. THE Test_Audit_System SHALL identify tests with excessive assertions (>20) as potentially testing too much
4. THE Test_Audit_System SHALL distinguish between value assertions (XCTAssertEqual) and existence assertions (XCTAssertNotNil)
5. THE Test_Audit_System SHALL prefer specific assertions over generic ones
6. THE Test_Audit_System SHALL calculate an assertion quality score per test

### Requirement 14: Integration Test Validation

**User Story:** As a developer, I want to validate integration tests, so that I can ensure they test end-to-end workflows

#### Acceptance Criteria

1. WHEN analyzing integration tests, THE Test_Audit_System SHALL verify multiple components are exercised
2. THE Test_Audit_System SHALL verify integration tests set up realistic test environments
3. THE Test_Audit_System SHALL verify integration tests clean up resources (databases, files, network connections)
4. THE Test_Audit_System SHALL verify integration tests assert on final outcomes, not intermediate states
5. IF an integration test only tests a single component, THEN THE Test_Audit_System SHALL suggest moving it to unit tests

### Requirement 15: Audit Report Generation

**User Story:** As a developer, I want a comprehensive audit report, so that I can prioritize test improvements

#### Acceptance Criteria

1. THE Test_Audit_System SHALL generate a report listing all Assertion_Mismatch findings
2. THE Test_Audit_System SHALL generate a report listing all False_Positive_Test findings
3. THE Test_Audit_System SHALL generate a report listing all Test_Coverage_Gap findings
4. THE Test_Audit_System SHALL rank findings by severity (critical, high, medium, low)
5. THE Test_Audit_System SHALL provide actionable recommendations for each finding
6. THE Test_Audit_System SHALL generate summary statistics (total tests analyzed, issues found, pass rate)
7. THE Test_Audit_System SHALL output reports in both human-readable and machine-readable formats

### Requirement 16: Incremental Analysis Support

**User Story:** As a developer, I want to analyze tests incrementally, so that I can audit large test suites efficiently

#### Acceptance Criteria

1. THE Test_Audit_System SHALL support analyzing individual test files
2. THE Test_Audit_System SHALL support analyzing test directories (e.g., Garazyk/Tests/Auth/)
3. THE Test_Audit_System SHALL support analyzing specific test classes
4. THE Test_Audit_System SHALL cache analysis results to avoid re-analyzing unchanged tests
5. THE Test_Audit_System SHALL support filtering by test domain (Auth, Network, Core, etc.)
6. THE Test_Audit_System SHALL support filtering by issue severity

### Requirement 17: Test Dependency Analysis

**User Story:** As a developer, I want to analyze test dependencies, so that I can identify brittle tests

#### Acceptance Criteria

1. THE Test_Audit_System SHALL identify tests that depend on external services (network, filesystem, databases)
2. THE Test_Audit_System SHALL identify tests that depend on test execution order
3. THE Test_Audit_System SHALL identify tests that share mutable state
4. THE Test_Audit_System SHALL verify tests properly isolate their environments
5. IF a test depends on another test's side effects, THEN THE Test_Audit_System SHALL flag it as brittle

### Requirement 18: Mock and Stub Validation

**User Story:** As a developer, I want to validate mock usage, so that I can ensure mocks don't hide real bugs

#### Acceptance Criteria

1. WHEN a test uses mocks or stubs, THE Test_Audit_System SHALL identify what is being mocked
2. THE Test_Audit_System SHALL verify mock behavior matches real implementation contracts
3. THE Test_Audit_System SHALL detect over-mocking (mocking too many dependencies)
4. THE Test_Audit_System SHALL detect under-mocking (not mocking external dependencies)
5. THE Test_Audit_System SHALL verify mock assertions are checked (verify method calls occurred)

### Requirement 19: Async Test Validation

**User Story:** As a developer, I want to validate async tests, so that I can ensure they properly handle asynchronous operations

#### Acceptance Criteria

1. WHEN analyzing async tests, THE Test_Audit_System SHALL identify XCTestExpectation usage
2. THE Test_Audit_System SHALL verify expectations are fulfilled in async callbacks
3. THE Test_Audit_System SHALL verify timeout values are reasonable (not too short or too long)
4. THE Test_Audit_System SHALL detect race conditions in async test setup
5. IF an async test doesn't wait for expectations, THEN THE Test_Audit_System SHALL flag it as potentially flaky

### Requirement 20: Test Documentation Validation

**User Story:** As a developer, I want to validate test documentation, so that I can ensure tests are understandable

#### Acceptance Criteria

1. THE Test_Audit_System SHALL extract comments and documentation from test methods
2. THE Test_Audit_System SHALL verify complex tests have explanatory comments
3. THE Test_Audit_System SHALL verify test setup code is documented when non-obvious
4. THE Test_Audit_System SHALL identify tests with misleading comments (comments don't match code)
5. THE Test_Audit_System SHALL calculate a documentation completeness score per test file
