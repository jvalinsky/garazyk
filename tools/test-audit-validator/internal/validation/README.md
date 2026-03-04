# Validation Package

This package provides the validation rule framework for the Test Audit Validation System.

## Overview

The validation framework orchestrates the execution of validation rules against test code to identify issues such as:
- Tests that don't test what they claim
- False positive tests that pass without validating behavior
- Coverage gaps where claimed functionality isn't validated
- Security tests that don't verify security properties
- And more...

## Core Components

### Severity

Defines the severity levels for validation findings:
- **CRITICAL**: Test provides false confidence - fix immediately
- **HIGH**: Test likely doesn't test what it claims - review and fix
- **MEDIUM**: Test has potential gaps - consider improving
- **LOW**: Minor quality issues - improve when convenient

```go
severity := validation.CRITICAL
fmt.Println(severity.String()) // "critical"

sev, ok := validation.ParseSeverity("high")
if ok {
    fmt.Println(sev) // HIGH
}
```

### Finding

Represents a validation issue discovered in test code:

```go
finding := validation.Finding{
    RuleName:       "NameAssertionAlignmentRule",
    Severity:       validation.HIGH,
    TestMethod:     "testOAuthTokenValidation",
    TestClass:      "OAuthTests",
    FilePath:       "/path/to/OAuthTests.m",
    LineNumber:     42,
    Message:        "Test name claims to validate OAuth tokens but only checks non-null",
    Recommendation: "Add assertions to verify token properties (type, expiration, signature)",
    Confidence:     0.85,
}
```

### ValidationRule Interface

All validation rules must implement this interface:

```go
type ValidationRule interface {
    // Validate applies the rule to the given context and returns findings
    Validate(ctx ValidationContext) []Finding

    // Severity returns the severity level for findings from this rule
    Severity() Severity

    // Description returns a human-readable description of what this rule validates
    Description() string

    // Name returns the unique name of this rule
    Name() string
}
```

### ValidationContext

Provides context for validation rules:

```go
type ValidationContext struct {
    TestMethod *models.TestMethod // Current test method (nil for class/file-level validation)
    TestClass  *models.TestClass  // Current test class (nil for file-level validation)
    TestFile   *models.TestFile   // Current test file
}
```

### Engine

Orchestrates the execution of validation rules:

```go
// Create engine with rules
engine := validation.NewEngine([]validation.ValidationRule{
    &NameAssertionAlignmentRule{},
    &FalsePositiveDetectionRule{},
    &AssertionQualityRule{},
})

// Add more rules dynamically
engine.AddRule(&SecurityTestRule{})

// Validate at different levels
methodFindings := engine.ValidateTestMethod(method, class, file)
classFindings := engine.ValidateTestClass(class, file)
fileFindings := engine.ValidateTestFile(file)
```

## Creating a Custom Validation Rule

Here's an example of implementing a custom validation rule:

```go
package validation

import "github.com/september-pds/test-audit-validator/internal/models"

type ZeroAssertionRule struct{}

func (r *ZeroAssertionRule) Name() string {
    return "ZeroAssertionRule"
}

func (r *ZeroAssertionRule) Severity() Severity {
    return CRITICAL
}

func (r *ZeroAssertionRule) Description() string {
    return "Detects test methods with zero assertions"
}

func (r *ZeroAssertionRule) Validate(ctx ValidationContext) []Finding {
    // Only validate at method level
    if ctx.TestMethod == nil {
        return nil
    }

    // Check if method has zero assertions
    if len(ctx.TestMethod.Assertions) == 0 {
        return []Finding{{
            RuleName:       r.Name(),
            Severity:       r.Severity(),
            TestMethod:     ctx.TestMethod.Name,
            TestClass:      ctx.TestClass.Name,
            FilePath:       ctx.TestFile.Path,
            LineNumber:     ctx.TestMethod.LineNumber,
            Message:        "Test method has no assertions",
            Recommendation: "Add assertions to verify expected behavior",
            Confidence:     1.0,
        }}
    }

    return nil
}
```

## Validation Levels

The engine supports validation at three levels:

### Method-Level Validation

Validates individual test methods:

```go
findings := engine.ValidateTestMethod(method, class, file)
```

Rules receive a context with all three fields populated (TestMethod, TestClass, TestFile).

### Class-Level Validation

Validates test classes and all their methods:

```go
findings := engine.ValidateTestClass(class, file)
```

Rules are called:
1. Once per method (with TestMethod populated)
2. Once for the class (with TestMethod = nil)

### File-Level Validation

Validates entire test files:

```go
findings := engine.ValidateTestFile(file)
```

Rules are called:
1. Once per method in each class
2. Once per class
3. Once for the file (with TestMethod = nil, TestClass = nil)

## Testing Validation Rules

Use the provided MockRule for testing:

```go
func TestMyValidationLogic(t *testing.T) {
    rule := &MyCustomRule{}
    
    method := &models.TestMethod{
        Name:       "testExample",
        Assertions: []models.Assertion{},
    }
    
    class := &models.TestClass{Name: "ExampleTests"}
    file := &models.TestFile{Path: "/path/to/test.m"}
    
    ctx := validation.ValidationContext{
        TestMethod: method,
        TestClass:  class,
        TestFile:   file,
    }
    
    findings := rule.Validate(ctx)
    
    if len(findings) != 1 {
        t.Errorf("Expected 1 finding, got %d", len(findings))
    }
}
```

## Best Practices

1. **Confidence Scores**: Always set confidence between 0.0 and 1.0
   - 0.9-1.0: Very confident (clear pattern match)
   - 0.7-0.9: Confident (strong indicators)
   - 0.5-0.7: Moderate confidence (some ambiguity)
   - 0.3-0.5: Low confidence (uncertain)

2. **Actionable Recommendations**: Provide specific, actionable recommendations
   - ❌ "Fix this test"
   - ✅ "Add assertions to verify token.type equals 'Bearer' and token.expiresAt is in the future"

3. **Context Awareness**: Check which context fields are populated
   ```go
   if ctx.TestMethod == nil {
       // This is class or file-level validation
       return nil
   }
   ```

4. **Performance**: Avoid expensive operations in Validate()
   - Cache parsed data when possible
   - Use early returns for non-applicable contexts

5. **Severity Guidelines**:
   - CRITICAL: Test passes but provides false confidence
   - HIGH: Test likely doesn't validate what it claims
   - MEDIUM: Test has gaps but provides some value
   - LOW: Minor quality or style issues
