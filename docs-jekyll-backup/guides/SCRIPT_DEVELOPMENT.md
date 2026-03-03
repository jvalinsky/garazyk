# Script Development and Quality Standards

This document defines the shell-script standards used in this repository and summarizes the script updates applied to the ATProto PDS project.

## Bash Scripting Standards

All scripts follow these external references:
- Google's Bash Style Guide
- Greg's Wiki BashGuide
- POSIX Shell Specification
- ShellCheck best practices

## Script Quality Standards

All repository shell scripts follow these standards:

### 1. Script Structure
- **Shebang**: Use `#!/usr/bin/env bash` for portability
- **Shell Options**: Always set `set -euo pipefail`
- **Documentation**: Header with script name, purpose, and usage notes
- **Error Handling**: Proper trap handlers for cleanup and signal handling
- **Logging**: Structured logging with debug, info, warn, and error levels

### 2. Code Quality
- **ShellCheck Compliance**: All scripts pass ShellCheck with zero warnings
- **SC2155 Compliance**: Declare and assign variables separately to avoid masking return values
- **Input Validation**: All inputs validated and sanitized
- **Security**: Safe path handling, secure temporary files, input sanitization
- **Color Output**: Consistent color mapping for status output

### 3. Error Handling
- **Exit Codes**: Use standard exit codes (0=success, 1=error, 2=invalid args, etc.)
- **Cleanup**: Proper cleanup of temporary files and resources
- **Error Messages**: Clear, actionable error messages without exposing internals

### 4. Performance
- **Built-ins**: Prefer bash built-ins over external commands when possible
- **Efficiency**: Avoid unnecessary subshells and optimize loops
- **Profiling**: Include timing information for performance-critical operations

## Upgraded Scripts

### simple_test.sh
**Purpose**: Integration smoke testing for the ATProto PDS server

**Improvements**:
- Reworked structure for predictable setup/teardown
- Error handling and cleanup on failure paths
- Structured logging with multiple levels
- Input validation and dependency checking
- Environment variable support (VERBOSE, PORT, DB_PATH)
- Test isolation and resource cleanup

**Usage**:
```bash
# Basic test run
./scripts/simple_test.sh

# Verbose output
VERBOSE=true ./scripts/simple_test.sh

# Custom port
PORT=3000 ./scripts/simple_test.sh
```

### start_server.sh
**Purpose**: Server startup with process management and validation

**Improvements**:
- Initialization checks before launch
- Proper PID file management
- Process conflict detection
- Environment variable configuration support
- Structured logging and error reporting
- Graceful cleanup on interruption

**Usage**:
```bash
# Standard startup
./scripts/start_server.sh

# Custom configuration
SERVER_BINARY=/path/to/server LOG_FILE=/tmp/server.log ./scripts/start_server.sh
```

### quality_gate.sh
**Purpose**: Code quality and static analysis gate

**Improvements**:
- Error handling and validation
- Dependency checks for required tools
- Structured progress reporting
- Configurable thresholds for quality metrics
- Integration with the build workflow
- Detailed error reporting with failed check tracking

**Usage**:
```bash
# Run quality checks
./scripts/quality_gate.sh

 # Verbose output
 VERBOSE=true ./scripts/quality_gate.sh
 ```

 ### test_social_features.sh (NEW)
 **Purpose**: E2E testing of social features (feeds, follows, likes, profiles)

 **Features**:
 - Multi-user test scenarios (Alice & Bob)
 - Post creation, following, and liking functionality
 - Timeline and author feed testing
 - Actor search capabilities
 - Colored output and assertions
 - Error handling and cleanup

 **Usage**:
 ```bash
 # Run social features e2e test
 ./scripts/test_social_features.sh

 # With verbose debugging
 VERBOSE=true ./scripts/test_social_features.sh
 ```

 ### test_moderation.sh (NEW)
 **Purpose**: E2E testing of moderation features (reports, labels, account moderation)

 **Features**:
 - Admin authentication setup
 - Content reporting functionality
 - Content labeling operations
 - Account moderation testing
 - Subject status updates
 - Graceful handling of unimplemented features

 **Usage**:
 ```bash
 # Run moderation e2e test
 ./scripts/test_moderation.sh

 # With verbose debugging
 VERBOSE=true ./scripts/test_moderation.sh
 ```

### run-tests.sh
**Purpose**: Test suite runner

**Improvements**:
- Predictable argument and environment handling
- Test binary validation
- Environment variable configuration
- Structured logging and progress reporting
- Proper error handling and cleanup
- Timing information for performance monitoring

**Usage**:
```bash
# Run test suite
./scripts/run-tests.sh

# Verbose output
VERBOSE=true ./scripts/run-tests.sh
```

## Development Workflow

### Creating New Scripts

1. **Follow Standards**: Apply the patterns documented in this guide
2. **Use Templates**: Start with the provided script structure and patterns
3. **Validate Early**: Run ShellCheck during development: `shellcheck script.sh`
4. **Test Thoroughly**: Test on target environment with various input scenarios
5. **Document**: Update this guide and script headers with usage information

### Script Review Process

1. **Automated Checks**: All scripts must pass ShellCheck with zero warnings
2. **Manual Review**: Follow the skill guidelines for code review
3. **Testing**: Scripts must work correctly on target systems
4. **Documentation**: Update relevant documentation and guides

### Maintenance

- **Regular Updates**: Review and update scripts following new best practices
- **Dependency Monitoring**: Check for deprecated commands or changed interfaces
- **Performance**: Profile and optimize performance-critical scripts
- **Security**: Review script handling of secrets, paths, and temporary files

## Quality Metrics

### Current Status
- ✅ All scripts pass ShellCheck with 0 warnings
- ✅ SC2155 compliance (proper variable declaration)
- ✅ Error handling and cleanup paths implemented
- ✅ Structured logging throughout
- ✅ Input validation and sanitization
- ✅ Security best practices followed
- ✅ Colored output (when terminal supports it)
- ✅ New E2E test coverage: Social features and moderation
- ✅ Complete test suite: Unit tests + E2E tests + Performance tests

### Color Support
Scripts automatically detect terminal capabilities and use ANSI color codes for enhanced readability:
- **Green**: Success messages and PASS results
- **Red**: Error messages and FAIL results
- **Yellow**: Warnings and SKIP messages
- **Blue**: Debug information (when verbose)
- **Cyan**: Info messages
- **White**: Highlighted data (like DIDs, PIDs)

Colors are automatically disabled when:
- Output is not to a terminal (`[[ -t 1 ]]`)
- `NO_COLOR=true` environment variable is set
- Terminal doesn't support colors

### Performance Notes
- Prefer shell built-ins over spawning external processes in hot loops.
- Avoid subshell-heavy pipelines when simple parameter expansion works.
- Measure before/after on representative workloads when tuning scripts.

## Tools and Dependencies

### Required Tools
- **ShellCheck**: Static analysis for shell scripts
- **bash**: Version 4.0+ for advanced features
- **curl**: For HTTP testing (where applicable)

### Installation
```bash
# Install ShellCheck
brew install shellcheck

# Verify installation
shellcheck --version
```

### Integration
- **CI/CD**: Scripts are designed to work in automated environments
- **Build System**: Integrated with CMake/xcodebuild workflow
- **Testing**: Compatible with existing test infrastructure

## Troubleshooting

### Common Issues

#### ShellCheck Failures
```bash
# Run ShellCheck on specific script
shellcheck scripts/simple_test.sh

# Fix SC2155 warnings
# Change: readonly VAR="$(cmd)"
# To: VAR="$(cmd)"; readonly VAR
```

#### Permission Issues
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Check permissions
ls -la scripts/
```

#### Path Issues
```bash
# Use absolute paths in scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validate paths exist
if [[ ! -f "$SCRIPT_DIR/../build/bin/kaszlak" ]]; then
    echo "ERROR: Server binary not found"
    exit 1
fi
```

## Future Improvements

- **Automated Testing**: Integration with automated script testing frameworks
- **Configuration Management**: Centralized configuration for all scripts
- **Monitoring**: Script performance and reliability monitoring
- **Documentation**: Automated script documentation generation
- **Security**: Enhanced security scanning and vulnerability assessment

## References

- [Google's Bash Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Greg's BashGuide](https://mywiki.wooledge.org/BashGuide)
- [ShellCheck](https://github.com/koalaman/shellcheck)
- [POSIX Shell Specification](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)

## Related Documentation

- **[Developer Guide](DEVELOPER_GUIDE.md)** - Build system and project structure
- **[Setup Guide](SETUP_GUIDE.md)** - Server startup and verification scripts
- **[Testing Guide](../TESTING.md)** - Test suite execution
- **[Deployment Guide](DEPLOYMENT.md)** - Production script integration
- **[Development Workflows](DEVELOPMENT_WORKFLOWS.md)** - Build and test process diagrams
- **[CI/CD Pipeline](../../.github/workflows/ci.yml)** - Automated workflow configuration
