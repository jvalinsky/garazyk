## Complete Example Script

```bash
#!/usr/bin/env bash
#
# Name: secure_backup.sh
# Description: Secure database backup with validation and cleanup
# Author: Professional Bash Script Example
# Version: 1.0.0
#

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_BACKUP_DIR="${HOME}/backups"
readonly DEFAULT_RETENTION_DAYS=30

# Global variables
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
RETENTION_DAYS="${RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}"
VERBOSE="${VERBOSE:-false}"
LOG_FILE=""
TEMP_FILES=()

# Logging functions
log_debug() { [[ "$VERBOSE" == "true" ]] && echo "[DEBUG] $1" >&2; }
log_info()  { echo "[INFO] $1" >&2; }
log_warn()  { echo "[WARN] $1" >&2; }
log_error() { echo "[ERROR] $1" >&2; }

# Cleanup function
cleanup() {
    log_debug "Cleaning up temporary files"
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
}

# Error exit function
error_exit() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    cleanup
    exit "$code"
}

# Trap signals
trap cleanup EXIT
trap 'error_exit "Script interrupted" 130' INT TERM

# Validation functions
validate_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error_exit "File does not exist: $file" 5
    fi
    
    if [[ ! -r "$file" ]]; then
        error_exit "Cannot read file: $file" 4
    fi
}

validate_directory() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        log_info "Creating backup directory: $dir"
        mkdir -p "$dir" || error_exit "Cannot create directory: $dir" 4
    fi
    
    if [[ ! -w "$dir" ]]; then
        error_exit "Cannot write to directory: $dir" 4
    fi
}

validate_number() {
    local num="$1"
    local name="$2"
    
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        error_exit "Invalid $name: $num" 2
    fi
    
    if (( num < 1 || num > 365 )); then
        error_exit "$name must be between 1-365: $num" 2
    fi
}

# Argument parsing
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                SOURCE_FILE="$2"
                shift 2
                ;;
            -d|--directory)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1" 2
                ;;
        esac
    done
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] -f SOURCE_FILE

Create secure database backups with automatic cleanup.

Options:
  -f, --file FILE        Source file to backup (required)
  -d, --directory DIR    Backup directory (default: $DEFAULT_BACKUP_DIR)
  -r, --retention DAYS   Keep backups for N days (default: $DEFAULT_RETENTION_DAYS)
  -v, --verbose          Enable verbose output
  -l, --log FILE         Log to file
  -h, --help            Show this help

Examples:
  $0 -f database.db
  $0 -f /var/db/prod.db -d /mnt/backups -r 7 -v

EOF
}

# Create backup
create_backup() {
    local source_file="$1"
    local dest_dir="$2"
    local timestamp
    local backup_name
    local backup_path
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_name="backup_${timestamp}.tar.gz"
    backup_path="$dest_dir/$backup_name"
    
    log_info "Creating backup: $backup_path"
    
    if ! tar -czf "$backup_path" -C "$(dirname "$source_file")" "$(basename "$source_file")"; then
        error_exit "Failed to create backup archive"
    fi
    
    # Set secure permissions
    chmod 600 "$backup_path"
    
    log_info "Backup created successfully: $backup_path"
    echo "$backup_path"
}

# Cleanup old backups
cleanup_old_backups() {
    local backup_dir="$1"
    local retention_days="$2"
    
    log_debug "Cleaning up backups older than $retention_days days"
    
    find "$backup_dir" -name "backup_*.tar.gz" -type f -mtime "+$retention_days" -delete
}

# Dependency check
check_dependencies() {
    local deps=("tar" "gzip" "find" "date")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if (( ${#missing[@]} > 0 )); then
        error_exit "Missing dependencies: ${missing[*]}" 3
    fi
}

# Main function
main() {
    local source_file
    local backup_path
    
    # Parse and validate arguments
    parse_args "$@"
    
    if [[ -z "${SOURCE_FILE:-}" ]]; then
        error_exit "Source file not specified. Use -f/--file" 2
    fi
    
    # Validate inputs
    source_file=$(realpath "$SOURCE_FILE" 2>/dev/null) || error_exit "Invalid source file: $SOURCE_FILE"
    validate_file "$source_file"
    validate_directory "$BACKUP_DIR"
    validate_number "$RETENTION_DAYS" "retention days"
    
    # Check dependencies
    check_dependencies
    
    # Create backup
    backup_path=$(create_backup "$source_file" "$BACKUP_DIR")
    
    # Cleanup old backups
    cleanup_old_backups "$BACKUP_DIR" "$RETENTION_DAYS"
    
    log_info "Backup operation completed successfully"
    log_info "Backup location: $backup_path"
}

# Run main function with all arguments
main "$@"
```
