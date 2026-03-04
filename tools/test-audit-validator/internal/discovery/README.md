# Test Discovery Engine

The discovery package provides functionality for discovering test files, classes, and methods in the September PDS codebase.

## Overview

The `TestDiscoveryEngine` recursively scans directories to find Objective-C test files (`.m` extension) while intelligently excluding fixture directories and helper files.

## Usage

```go
import "github.com/september-pds/test-audit-validator/internal/discovery"

// Create a new discovery engine with default settings
engine := discovery.NewTestDiscoveryEngine()

// Discover all test files in a directory
testFiles, err := engine.DiscoverTestFiles("ATProtoPDS/Tests")
if err != nil {
    log.Fatal(err)
}

// Process discovered test files
for _, testFile := range testFiles {
    fmt.Printf("Found test file: %s\n", testFile.Path)
}
```

## Features

### Automatic Exclusions

The engine automatically excludes:

**Directories:**
- `fixtures/` - Test fixture data
- `plc_e2e/` - End-to-end test infrastructure
- `helpers/` - Test helper utilities

**Files:**
- Files containing "helper" in the name (e.g., `TestHelper.m`)
- Files containing "util" in the name (e.g., `TestUtil.m`)
- Files containing "base" in the name (e.g., `TestBase.m`)
- Files containing "common" in the name (e.g., `CommonTest.m`)
- `test_main.m` - Test runner entry point

### File Type Filtering

Only `.m` (Objective-C implementation) files are discovered. Header files (`.h`), C files (`.c`), and other file types are automatically excluded.

### Nested Directory Support

The engine recursively walks the entire directory tree, discovering test files at any depth.

## Customization

You can customize the exclude patterns:

```go
engine := discovery.NewTestDiscoveryEngine()

// Add custom exclude patterns
engine.ExcludePatterns = append(engine.ExcludePatterns, "custom_exclude")

// Or replace entirely
engine.ExcludePatterns = []string{"fixtures", "my_custom_exclude"}
```

## Implementation Details

### Directory Walking

The engine uses `filepath.Walk` to recursively traverse the directory tree. When an excluded directory is encountered, `filepath.SkipDir` is returned to skip the entire subtree.

### Case-Insensitive Matching

Directory and file name matching is case-insensitive, so `Fixtures`, `FIXTURES`, and `fixtures` are all excluded.

### Error Handling

The engine validates that:
- The root path exists
- The root path is a directory (not a file)
- All file system operations succeed

Errors are wrapped with context for better debugging.

## Testing

The discovery engine has comprehensive unit tests covering:
- Empty directories
- Nested directory structures
- Fixture exclusion
- Helper file exclusion
- File type filtering
- Error conditions (nonexistent paths, file instead of directory)

Run tests with:
```bash
go test ./internal/discovery/
```

## Future Enhancements

Task 2.2 will add:
- `DiscoverTestClasses()` - Extract test classes using clang AST parsing
- `DiscoverTestMethods()` - Find test methods within classes
- `CheckTestRegistration()` - Verify test classes are registered in `test_main.m`
