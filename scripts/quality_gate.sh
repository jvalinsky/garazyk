#!/usr/bin/env bash
#
# Name: quality_gate.sh
# Description: Run comprehensive code quality checks including static analysis
# Author: Professional Bash Script Example
# Version: 1.0.0
# Date: 2024-01-01
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_ROOT
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
readonly BUILD_DIR
REPORT_DIR="${REPORT_DIR:-$BUILD_DIR/reports}"
readonly REPORT_DIR
COMPILE_COMMANDS="$BUILD_DIR/compile_commands.json"
readonly COMPILE_COMMANDS
VERBOSE="${VERBOSE:-false}"
readonly VERBOSE

# Quality thresholds
readonly OCLINT_PRIORITY1_MAX=0
readonly OCLINT_PRIORITY2_MAX=20
readonly LONG_LINE_THRESHOLD=150

# Global variables
FAILED_CHECKS=()

# Color definitions
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

# Logging functions with colors
log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" >&2
    fi
}
log_info()  { echo -e "${CYAN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Error exit function
error_exit() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"

    if (( ${#FAILED_CHECKS[@]} > 0 )); then
        log_error "Failed checks: ${FAILED_CHECKS[*]}"
    fi

    exit "$code"
}

# Dependency check
check_dependencies() {
    local deps=("cmake" "python3" "find")
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

# Validate project structure
validate_project() {
    if [[ ! -d "$PROJECT_ROOT/ATProtoPDS" ]]; then
        error_exit "Project directory not found: $PROJECT_ROOT/ATProtoPDS" 5
    fi

    if [[ ! -d "$PROJECT_ROOT/ATProtoPDS/Sources" ]]; then
        error_exit "Sources directory not found: $PROJECT_ROOT/ATProtoPDS/Sources" 5
    fi

    log_debug "Project structure validated"
}

# Create report directory
setup_reports() {
    if ! mkdir -p "$REPORT_DIR"; then
        error_exit "Cannot create report directory: $REPORT_DIR" 4
    fi

    log_debug "Report directory: $REPORT_DIR"
}

# Generate compile_commands.json if needed
generate_compile_commands() {
    log_info "Checking compile_commands.json"

    if [[ -f "$COMPILE_COMMANDS" ]]; then
        log_debug "compile_commands.json already exists"
        return 0
    fi

    log_info "Generating compile_commands.json"

    if [[ ! -d "$BUILD_DIR" ]]; then
        log_info "Creating build directory: $BUILD_DIR"
        mkdir -p "$BUILD_DIR" || error_exit "Cannot create build directory: $BUILD_DIR" 4
    fi

    cd "$BUILD_DIR"
    if ! cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..; then
        cd "$PROJECT_ROOT"
        error_exit "Failed to generate compile_commands.json" 1
    fi
    cd "$PROJECT_ROOT"

    if [[ ! -f "$COMPILE_COMMANDS" ]]; then
        error_exit "compile_commands.json was not generated" 1
    fi

    log_info "compile_commands.json generated successfully"
}

# Run Clang-Tidy (currently disabled but structured for future use)
run_clang_tidy() {
    log_info "Clang-Tidy check (currently disabled)"

    # NOTE: Clang-Tidy is currently disabled due to performance concerns
    # To enable, uncomment the following:

    # log_info "Running Clang-Tidy"
    # local clang_tidy_files
    # mapfile -t clang_tidy_files < <(find "$PROJECT_ROOT/ATProtoPDS/Sources" -name "*.m" -type f)

    # if (( ${#clang_tidy_files[@]} == 0 )); then
    #     log_warn "No Objective-C source files found for Clang-Tidy"
    #     return 0
    # fi

    # if ! clang-tidy -p "$BUILD_DIR" "${clang_tidy_files[@]}"; then
    #     FAILED_CHECKS+=("clang-tidy")
    #     return 1
    # fi

    log_debug "Clang-Tidy check completed (skipped)"
}

# Run OCLint analysis
run_oclint() {
    log_info "Running OCLint analysis"

    if ! command -v oclint-json-compilation-database >/dev/null 2>&1; then
        log_warn "oclint-json-compilation-database not found. Skipping OCLint."
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "python3 not found. Cannot process OCLint results."
        return 0
    fi

    local oclint_report="$REPORT_DIR/oclint.json"

    cd "$BUILD_DIR"
    if ! oclint-json-compilation-database -e build -e Tests -- \
        -report-type json \
        -o "$oclint_report" \
        -max-priority-1="$OCLINT_PRIORITY1_MAX" \
        -max-priority-2="$OCLINT_PRIORITY2_MAX" \
        -rc "LONG_LINE=$LONG_LINE_THRESHOLD"; then
        cd "$PROJECT_ROOT"
        FAILED_CHECKS+=("oclint")
        log_error "OCLint analysis failed"
        return 1
    fi
    cd "$PROJECT_ROOT"

    if [[ ! -f "$oclint_report" ]]; then
        FAILED_CHECKS+=("oclint")
        log_error "OCLint report not generated"
        return 1
    fi

    # Process OCLint results
    if ! python3 "$SCRIPT_DIR/process_oclint_report.py" "$oclint_report" --threshold "$OCLINT_PRIORITY2_MAX"; then
        FAILED_CHECKS+=("oclint")
        log_error "OCLint violations exceed threshold"
        return 1
    fi

    log_info "OCLint analysis passed"
}

# Main quality gate check
run_quality_checks() {
    log_info "Starting quality gate checks"
    local start_time
    start_time=$(date +%s)

    # Run individual checks
    run_clang_tidy || true  # Currently disabled, don't fail
    run_oclint

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if (( ${#FAILED_CHECKS[@]} == 0 )); then
        log_info "All quality checks passed in ${duration}s"
        return 0
    else
        log_error "Quality checks failed in ${duration}s: ${FAILED_CHECKS[*]}"
        return 1
    fi
}

# Main function
main() {
    log_info "=== Starting Quality Gate Check ==="
    log_info "Date: $(date)"
    log_info "Project: $PROJECT_ROOT"
    log_info "Reports: $REPORT_DIR"

    # Validate prerequisites
    check_dependencies
    validate_project
    setup_reports

    # Prepare build environment
    generate_compile_commands

    # Run quality checks
    if ! run_quality_checks; then
        error_exit "=== Quality Gate FAILED ===" 1
    fi

    log_info "=== Quality Gate PASSED ==="
}

# Run main function with all arguments
main "$@"
