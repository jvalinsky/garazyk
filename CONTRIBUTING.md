# Contributing to ATProtoPDS

## Quick Start

```bash
# Clone and build
git clone https://github.com/jvalinsky/NSPds.git
cd NSPds

# Setup dependencies
brew install xcodegen cmake

# Generate project and build
xcodegen generate
xcodebuild -scheme ATProtoPDS-CLI build

# Run tests
./build/tests/AllTests
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
xcodebuild -scheme AllTests build
./build/tests/AllTests

# Run specific test
./build/tests/AllTests --test-class MyTests
```

## Submitting Changes

1. Ensure all tests pass: `./build/tests/AllTests`
2. Run static analysis (if applicable)
3. Update documentation as needed
4. Create a descriptive PR description

## Getting Help

- Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- Review [DEVELOPER_GUIDE.md](docs/guides/DEVELOPER_GUIDE.md)
- Open an issue for questions
