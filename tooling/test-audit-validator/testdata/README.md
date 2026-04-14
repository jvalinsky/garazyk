# Test Data

This directory contains test fixtures and sample data for testing the Test Audit Validator.

## Structure

```
testdata/
  fixtures/
    good_tests/       - Well-written tests that should pass validation
    bad_tests/        - Tests with known issues for validation testing
    interop/          - Sample interop test fixtures
    security/         - Sample security test fixtures
  output/             - Generated test outputs (gitignored)
  cache/              - Test cache databases (gitignored)
```

## Usage

Test fixtures are used by the test suite to verify that the validator correctly identifies issues in test code.

Each fixture should include:
- The test file (`.m`)
- Expected findings (`.json`)
- Description of what the fixture tests (`.md`)
