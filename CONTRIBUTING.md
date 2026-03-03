# Contributing to ATProto PDS (Objective-C)

Thank you for your interest in contributing to the ATProto Personal Data Server implementation in Objective-C!

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Review Process](#code-review-process)
- [Documentation Requirements](#documentation-requirements)
- [Testing Requirements](#testing-requirements)
- [Style Guidelines](#style-guidelines)

## Code of Conduct

This project follows a professional and respectful code of conduct. Be kind, constructive, and collaborative.

## Getting Started

### Prerequisites

- macOS with Xcode 14+ or Linux with GNUstep 2.2+
- CMake 3.20+
- Git

### Building the Project

```bash
# macOS
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)

# Linux
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

### Running Tests

```bash
./build/tests/AllTests
```

See `AGENTS.md` for detailed build and test instructions.

## Development Workflow

1. **Fork and clone** the repository
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following our style guidelines
4. **Write tests** for new functionality
5. **Update documentation** (see below)
6. **Run quality gates** before pushing:
   - Build succeeds: `xcodebuild -scheme AllTests build`
   - Tests pass: `./build/tests/AllTests`
   - No new warnings
7. **Push to your fork** and create a pull request

## Code Review Process

### For Contributors

When submitting a pull request:

1. **Fill out the PR template completely**
   - Describe your changes clearly
   - Check all applicable checklist items
   - Complete the documentation checklist if applicable

2. **Ensure CI passes**
   - All tests must pass
   - No new compiler warnings
   - Static analysis checks pass

3. **Respond to feedback promptly**
   - Address reviewer comments
   - Update documentation if requested
   - Re-request review after changes

### For Reviewers

When reviewing pull requests:

1. **Code Quality**
   - [ ] Code follows project style guidelines
   - [ ] No obvious bugs or security issues
   - [ ] Error handling is appropriate
   - [ ] Memory management is correct (ARC)
   - [ ] Thread safety is considered

2. **Testing**
   - [ ] Tests are included for new functionality
   - [ ] Tests cover edge cases
   - [ ] Existing tests still pass

3. **Documentation** (see detailed guidelines below)
   - [ ] Documentation changes are included if needed
   - [ ] Code examples are accurate
   - [ ] Diagrams reflect changes
   - [ ] Links work correctly

4. **Architecture**
   - [ ] Changes fit the existing architecture
   - [ ] Service boundaries are respected
   - [ ] Platform compatibility maintained

## Documentation Requirements

**Documentation must be updated when code changes.** This is not optional.

### When Documentation Updates Are Required

Documentation MUST be updated for:

- ✅ New or modified XRPC endpoints
- ✅ Service layer changes (new services, modified APIs)
- ✅ Database schema changes
- ✅ Authentication mechanism changes
- ✅ Configuration option changes
- ✅ CLI command changes
- ✅ Platform compatibility changes
- ✅ Build process changes
- ✅ API contract changes
- ✅ Architecture changes

Documentation SHOULD be updated for:

- ⚠️ Significant implementation pattern changes
- ⚠️ Error handling improvements
- ⚠️ Performance optimizations affecting usage
- ⚠️ Security best practice updates
- ⚠️ Common issues discovered and resolved

### Documentation Review Guidelines

#### For Code Authors

1. **Identify affected documentation** using this mapping:

   | Change Type | Affected Documentation |
   |------------|------------------------|
   | XRPC endpoint | `docs/04-network-layer/`, `docs/11-reference/api-reference.md` |
   | Service layer | `docs/03-application-layer/`, relevant tutorials |
   | Database | `docs/05-database-layer/`, `docs/12-diagrams/database-schema.svg` |
   | Authentication | `docs/06-authentication/`, `docs/10-tutorials/tutorial-4-auth.md` |
   | Repository/Protocol | `docs/07-repository-protocol/` |
   | Firehose/Sync | `docs/08-sync-firehose/` |
   | Platform compat | `docs/09-platform-compatibility/` |
   | Configuration | `docs/11-reference/config-reference.md` |
   | CLI | `docs/11-reference/cli-reference.md` |

2. **Update documentation files:**
   - Update prose descriptions
   - Update code examples (extract from actual source)
   - Update diagrams if architecture changed
   - Update cross-references and links

3. **Verify documentation accuracy:**
   ```bash
   # Check links
   python3 scripts/test-doc-links.py
   
   # Build documentation site
   ./scripts/build-docs.sh
   
   # Verify locally
   cd _site && python3 -m http.server 8000
   ```

4. **Complete the documentation checklist in your PR**

#### For Documentation Reviewers

When reviewing documentation changes:

1. **Technical Accuracy**
   - [ ] Descriptions match the actual implementation
   - [ ] Code examples compile and run
   - [ ] API signatures are correct
   - [ ] Configuration options are accurate
   - [ ] Error messages match actual output

2. **Code Examples**
   - [ ] Examples are extracted from real source code
   - [ ] Line references are accurate
   - [ ] Examples include necessary context
   - [ ] Examples follow best practices
   - [ ] Example output is current

3. **Diagrams**
   - [ ] Diagrams accurately reflect architecture
   - [ ] All components are labeled clearly
   - [ ] Relationships are correct
   - [ ] Diagrams are in SVG format
   - [ ] Text descriptions are included for accessibility

4. **Consistency**
   - [ ] Terminology matches glossary
   - [ ] Style is consistent with existing docs
   - [ ] Cross-references work correctly
   - [ ] Navigation is clear

5. **Completeness**
   - [ ] All affected sections are updated
   - [ ] No broken links
   - [ ] No TODO/FIXME markers left
   - [ ] Related documentation is updated

6. **Clarity**
   - [ ] Explanations are clear and concise
   - [ ] Technical concepts are well-explained
   - [ ] Examples progress from simple to complex
   - [ ] Common pitfalls are addressed

### Documentation Quality Checklist

Use this checklist when reviewing documentation:

```markdown
## Documentation Review

### Technical Accuracy
- [ ] Code examples compile without errors
- [ ] API signatures match implementation
- [ ] Configuration options are correct
- [ ] Command-line examples work as shown

### Completeness
- [ ] All new features are documented
- [ ] All changed APIs are updated
- [ ] Diagrams reflect current architecture
- [ ] Cross-references are updated

### Clarity
- [ ] Explanations are clear and concise
- [ ] Examples are easy to follow
- [ ] Terminology is consistent
- [ ] Common issues are addressed

### Quality
- [ ] No broken links (verified with link checker)
- [ ] Documentation builds successfully
- [ ] No spelling or grammar errors
- [ ] Formatting is consistent

### Notes
<!-- Add any specific feedback or concerns -->
```

### When to Request Documentation Changes

Request documentation updates if:

- Code changes are not reflected in documentation
- Code examples don't compile or are outdated
- Diagrams don't match current architecture
- Links are broken
- Terminology is inconsistent
- Explanations are unclear or incorrect
- Important details are missing

### Documentation Resources

- **Full checklist**: `docs/DOCUMENTATION_UPDATE_CHECKLIST.md`
- **Link checker**: `scripts/test-doc-links.py`
- **Build script**: `scripts/build-docs.sh`
- **Documentation source**: `docs/` directory
- **Style guide**: Follow existing documentation patterns

## Testing Requirements

### Unit Tests

- Write unit tests for all new functions and classes
- Test both happy paths and error cases
- Use descriptive test names
- Aim for high code coverage

### Integration Tests

- Test interactions between components
- Verify XRPC endpoints work end-to-end
- Test database operations
- Test authentication flows

### Running Tests

```bash
# Run all tests
./build/tests/AllTests

# Run specific test class
./build/tests/AllTests -XCTest MSTInteropTests

# Run multiple test classes
./build/tests/AllTests -XCTest MSTInteropTests,CARInteropTests
```

## Style Guidelines

### Objective-C Style

- Use ARC (Automatic Reference Counting)
- Follow Apple's Objective-C conventions
- Use descriptive variable and method names
- Add comments for complex logic
- Use `#pragma mark` to organize code

### Code Organization

- Keep files focused and cohesive
- Separate interface (.h) and implementation (.m)
- Group related functionality
- Use clear directory structure

### Error Handling

- Use `NSError **` for error reporting
- Provide descriptive error messages
- Include error codes and domains
- Handle all error cases

### Platform Compatibility

- Use compatibility shims from `Compat/` directory
- Test on both macOS and Linux when possible
- Use conditional compilation when necessary:
  ```objc
  #if TARGET_OS_LINUX
  // Linux-specific code
  #elif __APPLE__
  // macOS-specific code
  #endif
  ```

## Quality Gates

Before pushing, ensure:

1. ✅ Code compiles without warnings
2. ✅ All tests pass
3. ✅ Documentation is updated
4. ✅ Code follows style guidelines
5. ✅ No new security issues

Run these commands:

```bash
# Build
xcodegen generate
xcodebuild -scheme AllTests build

# Test
./build/tests/AllTests

# Check documentation links
python3 scripts/test-doc-links.py

# Build documentation
./scripts/build-docs.sh
```

## Getting Help

- **Documentation**: See `docs/` directory
- **Architecture**: See `AGENTS.md`
- **Issues**: Check existing issues or create a new one
- **Questions**: Open a discussion or issue

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

Thank you for contributing to ATProto PDS! 🎉
