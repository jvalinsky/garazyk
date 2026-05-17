#!/usr/bin/env bash
# generate-api-docs.sh - Generate Objective-C API documentation via Doxygen + M.CSS
#
# Usage:
#   ./scripts/docs/generate-api-docs.sh           # Full generation
#   ./scripts/docs/generate-api-docs.sh --mcss    # Use M.CSS for modern HTML
#   ./scripts/docs/generate-api-docs.sh --clean   # Clean generated docs
#   ./scripts/docs/generate-api-docs.sh --serve    # Serve docs locally
#
# Prerequisites:
#   brew install doxygen graphviz
#   pip3 install jinja2 Pygments  (only for --mcss)

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT_ROOT
readonly DOXYFILE="$PROJECT_ROOT/Doxyfile"
readonly OUTPUT_DIR="$PROJECT_ROOT/docs/api"
readonly MCSS_DIR="$PROJECT_ROOT/.cache/m.css"
readonly SERVE_PORT="8080"

TEMP_DOXYFILE=""

USE_MCSS=false
SERVE=false
CLEAN=false

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--mcss] [--serve] [--clean]

  --mcss   Use M.CSS for modern HTML rendering
  --serve  Serve generated docs on localhost:$SERVE_PORT
  --clean  Remove generated docs
  --help   Show this help text
EOF
}

cleanup() {
    if [[ -n "$TEMP_DOXYFILE" && -f "$TEMP_DOXYFILE" ]]; then
        rm -f "$TEMP_DOXYFILE"
    fi
}

error() {
    echo "Error: $*" >&2
}

require_command() {
    local command_name="$1"
    local install_hint="$2"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        error "$command_name not found. $install_hint"
        exit 1
    fi
}

parse_args() {
    local arg

    for arg in "$@"; do
        case "$arg" in
            --mcss)
                USE_MCSS=true
                ;;
            --serve)
                SERVE=true
                ;;
            --clean)
                CLEAN=true
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $arg"
                usage >&2
                exit 1
                ;;
        esac
    done
}

clean_docs() {
    echo "Cleaning generated API docs..."
    rm -rf "$OUTPUT_DIR"
    echo "Done."
}

verify_common_prerequisites() {
    if [[ ! -f "$DOXYFILE" ]]; then
        error "Doxyfile not found at $DOXYFILE"
        exit 1
    fi

    require_command "doxygen" "Install with: brew install doxygen"
    require_command "dot" "Install Graphviz with: brew install graphviz"
}

verify_mcss_prerequisites() {
    require_command "python3" "Install Python 3 before using --mcss."
    require_command "git" "Install Git before using --mcss."

    if ! python3 -c "import jinja2, pygments" >/dev/null 2>&1; then
        error "Python modules jinja2 and Pygments are required for --mcss. Install with: pip3 install jinja2 Pygments"
        exit 1
    fi
}

ensure_mcss_checkout() {
    if [[ -d "$MCSS_DIR" ]]; then
        return
    fi

    echo "Cloning M.CSS into $MCSS_DIR..."
    mkdir -p "$(dirname "$MCSS_DIR")"
    if ! git clone --depth 1 https://github.com/mosra/m.css "$MCSS_DIR"; then
        error "Unable to clone M.CSS. Check network access or clone https://github.com/mosra/m.css into $MCSS_DIR."
        exit 1
    fi
}

run_doxygen() {
    echo "Running Doxygen..."
    cd "$PROJECT_ROOT"

    if [[ "$USE_MCSS" == true ]]; then
        TEMP_DOXYFILE="$(mktemp "${TMPDIR:-/tmp}/garazyk-doxygen.XXXXXX")"
        sed \
            -e 's/^GENERATE_HTML[[:space:]]*=.*/GENERATE_HTML          = NO/' \
            -e 's/^GENERATE_XML[[:space:]]*=.*/GENERATE_XML           = YES/' \
            "$DOXYFILE" >"$TEMP_DOXYFILE"
        doxygen "$TEMP_DOXYFILE"
    else
        doxygen "$DOXYFILE"
    fi
}

run_mcss() {
    local mcss_script="$MCSS_DIR/documentation/doxygen.py"

    if [[ "$USE_MCSS" != true ]]; then
        echo "Doxygen output: $OUTPUT_DIR/html"
        return
    fi

    if [[ ! -f "$mcss_script" ]]; then
        error "M.CSS renderer not found at $mcss_script"
        exit 1
    fi

    echo "Running M.CSS rendering..."
    python3 "$mcss_script" "$OUTPUT_DIR/xml"
    echo "M.CSS output: $OUTPUT_DIR/html"
}

report_warnings() {
    local warn_log="$OUTPUT_DIR/doxygen-warnings.log"
    local warn_count

    if [[ ! -f "$warn_log" ]]; then
        return
    fi

    warn_count="$(grep -c "warning:" "$warn_log" || true)"
    if [[ "$warn_count" -gt 0 ]]; then
        echo ""
        echo "$warn_count documentation warnings found. See: $warn_log"
        echo "Top warnings:"
        grep "warning:" "$warn_log" | sort | uniq -c | sort -rn | head -10
    fi
}

serve_docs() {
    if [[ "$SERVE" != true ]]; then
        return
    fi

    require_command "python3" "Install Python 3 before using --serve."

    echo ""
    echo "Serving docs at http://localhost:$SERVE_PORT"
    echo "Press Ctrl+C to stop."
    python3 -m http.server "$SERVE_PORT" --directory "$OUTPUT_DIR/html"
}

main() {
    trap cleanup EXIT
    parse_args "$@"

    if [[ "$CLEAN" == true ]]; then
        clean_docs
        exit 0
    fi

    verify_common_prerequisites
    if [[ "$USE_MCSS" == true ]]; then
        verify_mcss_prerequisites
        ensure_mcss_checkout
    fi

    run_doxygen
    run_mcss
    report_warnings
    serve_docs

    echo ""
    echo "API documentation generated successfully."
    echo "Open: $OUTPUT_DIR/html/index.html"
}

main "$@"
