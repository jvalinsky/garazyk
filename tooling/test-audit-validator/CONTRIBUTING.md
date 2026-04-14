# Contributing

## Adding a New Validation Rule

1. Create a new file `internal/validation/your_rule.go`:

```go
package validation

import "github.com/september-pds/test-audit-validator/internal/models"

type YourRule struct{}

func (r *YourRule) Name() string        { return "YourRule" }
func (r *YourRule) Description() string { return "Describes what this rule checks" }

func (r *YourRule) Validate(ctx ValidationContext) []Finding {
    if ctx.TestMethod == nil {
        return nil
    }
    // Your validation logic here
    return nil
}
```

2. Register it in `internal/validation/rules.go`:
```go
func DefaultRules() []ValidationRule {
    return []ValidationRule{
        // ... existing rules ...
        &YourRule{},
    }
}
```

3. Write tests in `internal/validation/your_rule_test.go`

4. Run tests: `go test ./internal/validation/ -run YourRule -v`

## Running Tests

```bash
# All non-clang tests
go test ./internal/cache/ ./internal/config/ ./internal/report/ ./internal/runner/ ./internal/validation/ ./internal/models/ ./tests/integration/

# With verbose output
go test ./internal/validation/ -v

# Specific rule
go test ./internal/validation/ -run TestAsyncTestRule -v

# With coverage
go test ./internal/validation/ -coverprofile=coverage.out
go tool cover -html=coverage.out
```

## Code Style

- Follow standard Go conventions
- Use `strings.Contains` for pattern matching (not regex) for performance
- All rules should handle `ctx.TestMethod == nil` (class/file-level validation)
- Use `lowercased` source code for case-insensitive matching
- Return `nil` (not empty slice) when no findings

## Testing Conventions

- Each rule has its own test file
- Test names follow `TestRuleName_Scenario` pattern
- Use `models.TestMethod` directly in test contexts (no mocking)
- Integration tests go in `tests/integration/`
