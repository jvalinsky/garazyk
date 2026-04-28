## Detailed Guidelines

### Script Initialization

**Shebang Selection:**
```bash
#!/bin/bash           # For bash-specific features
#!/usr/bin/env bash    # For portability across systems
#!/bin/sh             # For POSIX compliance only
```

**Essential Shell Options:**
```bash
set -e                # Exit on any command failure
set -u                # Exit on undefined variables
set -o pipefail       # Exit if any command in pipeline fails
```

**Script Metadata Template:**
```bash
#!/usr/bin/env bash
#
# Script Name: backup_database.sh
# Description: Creates compressed database backups
# Author: Your Name
# Version: 1.0.0
# Date: 2024-01-01
# License: MIT
#

set -euo pipefail

# Get script directory for relative path handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
```

### Error Handling

**Comprehensive Trap Setup:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Global variables for cleanup
TEMP_FILES=()
LOCK_FILE=""

cleanup() {
    # Remove temporary files
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file"
    done
    
    # Release lock
    if [[ -n "$LOCK_FILE" ]] && [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
}

error_exit() {
    local message="$1"
    local code="${2:-1}"
    echo "ERROR: $message" >&2
    cleanup
    exit "$code"
}

# Set traps
trap cleanup EXIT
trap 'error_exit "Script interrupted by user" 130' INT TERM
```

**Exit Code Standards:**
```bash
# Success codes
EXIT_SUCCESS=0

# Error codes (1-255)
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_MISSING_DEPS=3
EXIT_PERMISSION_DENIED=4
EXIT_FILE_NOT_FOUND=5
```

### Input Validation

**Command-Line Argument Parsing:**
```bash
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                BACKUP_FILE="$2"
                shift 2
                ;;
            -d|--directory)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1" "$EXIT_INVALID_ARGS"
                ;;
        esac
    done
}

validate_args() {
    # Check required arguments
    if [[ -z "${BACKUP_FILE:-}" ]]; then
        error_exit "Backup file not specified. Use -f/--file" "$EXIT_INVALID_ARGS"
    fi
    
    # Validate file paths
    if [[ ! -f "$BACKUP_FILE" ]]; then
        error_exit "Backup file does not exist: $BACKUP_FILE" "$EXIT_FILE_NOT_FOUND"
    fi
    
    # Validate permissions
    if [[ ! -r "$BACKUP_FILE" ]]; then
        error_exit "Cannot read backup file: $BACKUP_FILE" "$EXIT_PERMISSION_DENIED"
    fi
}
```

**Input Sanitization:**
```bash
# Safe path handling
sanitize_path() {
    local path="$1"
    
    # Remove null bytes and control characters
    path="${path//[$'\0'$'\r'$'\n']}"
    
    # Prevent directory traversal
    if [[ "$path" == *"../"* ]] || [[ "$path" == *"..\\"* ]]; then
        error_exit "Invalid path: directory traversal not allowed"
    fi
    
    # Convert to absolute path
    if [[ "$path" != /* ]]; then
        path="$(realpath "$path" 2>/dev/null)" || error_exit "Invalid path: $path"
    fi
    
    echo "$path"
}

# Validate numeric inputs
validate_number() {
    local num="$1"
    local min="${2:-}"
    local max="${3:-}"
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        error_exit "Invalid number: $num"
    fi
    
    if [[ -n "$min" ]] && (( num < min )); then
        error_exit "Number too small: $num (minimum: $min)"
    fi
    
    if [[ -n "$max" ]] && (( num > max )); then
        error_exit "Number too large: $num (maximum: $max)"
    fi
}
```

### Code Organization

**Function Structure:**
```bash
# Function naming: snake_case, descriptive names
create_backup() {
    local source_file="$1"
    local dest_dir="$2"
    local timestamp
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${timestamp}.tar.gz"
    local backup_path="$dest_dir/$backup_name"
    
    log_info "Creating backup: $backup_path"
    
    if ! tar -czf "$backup_path" "$source_file"; then
        error_exit "Failed to create backup archive"
    fi
    
    echo "$backup_path"
}

# Main function for script logic
main() {
    local backup_file
    local backup_path
    
    parse_args "$@"
    validate_args
    
    backup_file=$(sanitize_path "$BACKUP_FILE")
    backup_path=$(create_backup "$backup_file" "${BACKUP_DIR:-.}")
    
    log_info "Backup completed successfully: $backup_path"
}
```

**Configuration Management:**
```bash
# Configuration with defaults
readonly DEFAULT_BACKUP_DIR="${HOME}/backups"
readonly DEFAULT_RETENTION_DAYS=30
readonly DEFAULT_COMPRESSION_LEVEL=6

# Load configuration from file if it exists
load_config() {
    local config_file="${1:-${SCRIPT_DIR}/config.conf}"
    
    if [[ -f "$config_file" ]]; then
        # Source config file safely
        if ! source "$config_file"; then
            log_warn "Failed to load config file: $config_file"
        fi
    fi
}

# Export final configuration
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
RETENTION_DAYS="${RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-$DEFAULT_COMPRESSION_LEVEL}"
```

### Security Best Practices

**Safe Temporary File Creation:**
```bash
create_temp_file() {
    local template="${1:-temp_XXXXXX}"
    local temp_file
    
    # Use mktemp for secure temporary files
    if ! temp_file=$(mktemp -t "$template" 2>/dev/null); then
        error_exit "Failed to create temporary file"
    fi
    
    # Track for cleanup
    TEMP_FILES+=("$temp_file")
    
    echo "$temp_file"
}

# Safe command execution
safe_exec() {
    local cmd=("$@")
    
    # Log command (without sensitive data)
    log_debug "Executing: ${cmd[0]}"
    
    if ! "${cmd[@]}"; then
        error_exit "Command failed: ${cmd[0]}"
    fi
}
```

**Input Sanitization for Commands:**
```bash
# Whitelist validation for commands
validate_command() {
    local cmd="$1"
    local allowed_commands=("tar" "gzip" "rsync" "scp")
    
    for allowed in "${allowed_commands[@]}"; do
        if [[ "$cmd" == "$allowed" ]]; then
            return 0
        fi
    done
    
    error_exit "Command not allowed: $cmd"
}

# Safe eval alternative using arrays
safe_execute() {
    local cmd_array=("$@")
    
    # Validate each argument
    for arg in "${cmd_array[@]}"; do
        if [[ "$arg" == *"|"* ]] || [[ "$arg" == *";"* ]] || [[ "$arg" == *"\`"* ]]; then
            error_exit "Potentially dangerous argument: $arg"
        fi
    done
    
    "${cmd_array[@]}"
}
```

### Performance Optimization

**Efficient Constructs:**
```bash
# Prefer built-ins over external commands
# ✅ GOOD: Use parameter expansion
filename="${filepath##*/}"
extension="${filename##*.}"

# ❌ BAD: Use external commands unnecessarily
# filename=$(basename "$filepath")
# extension=$(basename "$filepath" | sed 's/.*\.//')

# Efficient looping
# ✅ GOOD: Use while read for large files
while IFS= read -r line; do
    process_line "$line"
done < "$large_file"

# ❌ BAD: Read entire file into memory
# while read -r line; do
#     process_line "$line"
# done <<< "$(cat "$large_file")"

# Avoid subshells in loops
# ✅ GOOD: Use process substitution
while IFS= read -r file; do
    process_file "$file"
done < <(find "$directory" -name "*.txt" -type f)

# ❌ BAD: Subshell in loop condition
# for file in $(find "$directory" -name "*.txt" -type f); do
```

**Profiling and Optimization:**
```bash
# Add timing to identify bottlenecks
time_operation() {
    local operation="$1"
    shift
    
    log_debug "Starting: $operation"
    local start_time
    start_time=$(date +%s.%N)
    
    "$@"
    
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
    
    log_debug "Completed: $operation (${duration}s)"
}

# Memory-efficient processing
process_large_file() {
    local file="$1"
    
    # Process in chunks instead of loading entire file
    local chunk_size=1000
    local line_num=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        
        if (( line_num % chunk_size == 0 )); then
            log_debug "Processed $line_num lines..."
        fi
        
        process_line "$line"
    done < "$file"
}
```

### Logging and Debugging

**Structured Logging with Colors:**
```bash
# Color definitions (terminal-aware)
if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly PURPLE='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly PURPLE=''
    readonly CYAN=''
    readonly WHITE=''
    readonly NC=''
fi

# Logging levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"
LOG_FILE="${LOG_FILE:-}"

log() {
    local level="$1"
    local message="$2"
    local level_num
    local color=""

    case "$level" in
        DEBUG) level_num=$LOG_LEVEL_DEBUG; color="$BLUE" ;;
        INFO)  level_num=$LOG_LEVEL_INFO; color="$CYAN" ;;
        WARN)  level_num=$LOG_LEVEL_WARN; color="$YELLOW" ;;
        ERROR) level_num=$LOG_LEVEL_ERROR; color="$RED" ;;
        *)     level_num=$LOG_LEVEL_INFO; color="$CYAN" ;;
    esac

    if (( level_num >= LOG_LEVEL )); then
        local timestamp
        timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
        local log_line="[$timestamp] [$level] $message"

        echo -e "${color}$log_line${NC}" >&2

        if [[ -n "$LOG_FILE" ]]; then
            # Strip colors for log file
            echo "$log_line" >> "$LOG_FILE"
        fi
    fi
}

log_debug() { log "DEBUG" "$1"; }
log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }
```

**Color Usage Guidelines:**
- **Green**: Success messages, PASS results, completed operations
- **Red**: Errors, FAIL results, critical issues
- **Yellow**: Warnings, SKIP messages, non-critical issues
- **Blue**: Debug information, verbose details
- **Cyan**: General information, progress updates
- **White**: Highlighted data (PIDs, DIDs, file paths)
- **Respect NO_COLOR**: Always check `NO_COLOR` environment variable

**Debug Mode:**
```bash
# Enable debug mode with -x or environment variable
if [[ "${DEBUG:-false}" == "true" ]] || [[ "${TRACE:-false}" == "true" ]]; then
    set -x  # Enable command tracing
fi

# Debug function for development
debug_dump_vars() {
    log_debug "=== Debug Information ==="
    log_debug "Script: ${BASH_SOURCE[0]}"
    log_debug "PID: $$"
    log_debug "PWD: $PWD"
    log_debug "Arguments: $*"
    
    # Dump important variables
    if [[ -n "${BACKUP_FILE:-}" ]]; then
        log_debug "BACKUP_FILE: $BACKUP_FILE"
    fi
    
    log_debug "========================"
}
```

### Documentation Standards

**Script Header Template:**
```bash
#!/usr/bin/env bash
#
# Name: backup_database.sh
# Description: Creates compressed database backups with rotation
# Author: Your Name <your.email@example.com>
# Version: 1.0.0
# Date: 2024-01-01
# License: MIT
# Dependencies: tar, gzip, find
#
# Usage: ./backup_database.sh [OPTIONS] DATABASE_FILE
#
# Options:
#   -f, --file FILE       Database file to backup (required)
#   -d, --directory DIR   Backup destination directory (default: ./backups)
#   -r, --retention DAYS  Keep backups for N days (default: 30)
#   -v, --verbose         Enable verbose output
#   -h, --help           Show this help message
#
# Examples:
#   ./backup_database.sh -f /var/db/production.db
#   ./backup_database.sh -f db.sqlite -d /mnt/backups -r 7 -v
#
# Exit Codes:
#   0  Success
#   1  General error
#   2  Invalid arguments
#   3  Missing dependencies
#   4  Permission denied
#   5  File not found
#
```

**Function Documentation:**
```bash
# create_backup: Create a compressed backup of a file
# Arguments:
#   $1 - source_file: Path to file to backup
#   $2 - dest_dir: Destination directory for backup
# Returns:
#   Path to created backup file
# Exit codes:
#   0 - Success
#   1 - Failed to create backup
create_backup() {
    # Implementation...
}

# show_help: Display usage information
# Arguments: None
# Returns: None (prints to stdout)
# Exit codes: None (always succeeds)
show_help() {
    cat << 'EOF'
Usage: backup_database.sh [OPTIONS] DATABASE_FILE

Creates compressed database backups with automatic rotation.

Options:
  -f, --file FILE       Database file to backup (required)
  -d, --directory DIR   Backup destination directory (default: ./backups)
  -r, --retention DAYS  Keep backups for N days (default: 30)
  -v, --verbose         Enable verbose output
  -h, --help           Show this help message

Examples:
  ./backup_database.sh -f /var/db/production.db
  ./backup_database.sh -f db.sqlite -d /mnt/backups -r 7 -v

EOF
}
```

### Testing and Validation

**ShellCheck Integration:**
```bash
# Run ShellCheck before committing
check_script() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        log_warn "ShellCheck not found. Install for better script validation."
        return 0
    fi
    
    if ! shellcheck "$0"; then
        error_exit "ShellCheck found issues. Fix before proceeding."
    fi
    
    log_info "ShellCheck validation passed"
}

# Dependency checking
check_dependencies() {
    local deps=("tar" "gzip" "date")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if (( ${#missing[@]} > 0 )); then
        error_exit "Missing dependencies: ${missing[*]}" "$EXIT_MISSING_DEPS"
    fi
}
```

**Test Scenarios:**
```bash
# test_backup_script.sh
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_database.sh"

# Test data setup
setup_test_data() {
    TEST_DB=$(mktemp -t test_db_XXXXXX.sqlite)
    TEST_BACKUP_DIR=$(mktemp -d -t test_backups_XXXXXX)
    
    # Create test database file
    echo "CREATE TABLE test (id INTEGER, data TEXT);" > "$TEST_DB"
    echo "INSERT INTO test VALUES (1, 'test data');" >> "$TEST_DB"
}

cleanup_test_data() {
    rm -f "$TEST_DB"
    rm -rf "$TEST_BACKUP_DIR"
}

# Test functions
test_successful_backup() {
    local backup_file
    
    backup_file=$("$BACKUP_SCRIPT" -f "$TEST_DB" -d "$TEST_BACKUP_DIR" 2>/dev/null)
    
    if [[ ! -f "$backup_file" ]]; then
        echo "FAIL: Backup file not created"
        return 1
    fi
    
    if ! tar -tzf "$backup_file" >/dev/null; then
        echo "FAIL: Backup file is not valid tar.gz"
        return 1
    fi
    
    echo "PASS: Successful backup"
}

test_invalid_file() {
    if "$BACKUP_SCRIPT" -f "/nonexistent/file.db" -d "$TEST_BACKUP_DIR" 2>/dev/null; then
        echo "FAIL: Should have failed with nonexistent file"
        return 1
    fi
    
    echo "PASS: Correctly rejected invalid file"
}

# Run tests
run_tests() {
    local failed=0
    
    setup_test_data
    
    echo "Running backup script tests..."
    
    if ! test_successful_backup; then
        ((failed++))
    fi
    
    if ! test_invalid_file; then
        ((failed++))
    fi
    
    cleanup_test_data
    
    if (( failed > 0 )); then
        echo "FAILED: $failed tests failed"
        exit 1
    else
        echo "SUCCESS: All tests passed"
    fi
}

run_tests
```
