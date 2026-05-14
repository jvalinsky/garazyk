#!/usr/bin/env bash
# common.sh — Shared bash library for Garazyk ATProto scripts
#
# Source from any script with:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/lib/common.sh"
#   # Or for scripts in subdirectories:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
#
# Provides: colors, logging, wait_for_http, service configuration,
#           process management, and project path resolution.
#
# Caller contract:
#   - The caller chooses its own strict-mode settings before or after sourcing.
#   - The caller may define cleanup(); error_exit will invoke it before exiting.
#   - Service ports and secrets can be overridden with environment variables
#     before this file is sourced.

# ── Strict mode reminder ────────────────────────────────────────────────────
# Scripts should still set their own: set -euo pipefail
# This library does NOT set strict mode to avoid surprising callers.

# ── Project paths ───────────────────────────────────────────────────────────

# Resolve the repository root relative to the caller's directory.
#
# Prefer git's idea of the worktree so scripts continue to work when invoked
# from subdirectories. If the checkout metadata is unavailable, fall back to the
# parent of the script directory, which is correct for top-level scripts and
# harmless for local ad-hoc usage.
resolve_project_root() {
    local script_dir="$1"
    git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || \
        (cd "$script_dir/.." && pwd)
}

# Resolve the directory containing service binaries.
#
# BUILD_DIR is intentionally honored here rather than in each caller so that
# all scripts agree on the same override point when running out-of-source
# builds or demo-specific binary directories.
resolve_build_dir() {
    local project_root="$1"
    echo "${BUILD_DIR:-$project_root/build/bin}"
}

# ── Colors (NO_COLOR-aware) ─────────────────────────────────────────────────

if [[ -t 1 ]] && [[ "${NO_COLOR:-false}" != "true" ]]; then
    readonly _LIB_RED='\033[0;31m'
    readonly _LIB_GREEN='\033[0;32m'
    readonly _LIB_YELLOW='\033[1;33m'
    readonly _LIB_BLUE='\033[0;34m'
    readonly _LIB_PURPLE='\033[0;35m'
    readonly _LIB_CYAN='\033[0;36m'
    readonly _LIB_WHITE='\033[1;37m'
    readonly _LIB_BOLD='\033[1m'
    readonly _LIB_NC='\033[0m'
else
    readonly _LIB_RED=''
    readonly _LIB_GREEN=''
    readonly _LIB_YELLOW=''
    readonly _LIB_BLUE=''
    readonly _LIB_PURPLE=''
    readonly _LIB_CYAN=''
    readonly _LIB_WHITE=''
    readonly _LIB_BOLD=''
    readonly _LIB_NC=''
fi

# ── Logging ─────────────────────────────────────────────────────────────────

# VERBOSE and QUIET can be set by the caller before or after sourcing.
# Defaults are applied only if not already set.
VERBOSE="${VERBOSE:-false}"
QUIET="${QUIET:-false}"

log_debug() {
    if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" != "true" ]]; then
        echo -e "${_LIB_BLUE}[DEBUG]${_LIB_NC} $1" >&2
    fi
}

log_info() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${_LIB_CYAN}[INFO]${_LIB_NC}  $1" >&2
    fi
}

log_ok() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${_LIB_GREEN}[OK]${_LIB_NC}    $1" >&2
    fi
}

log_warn() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${_LIB_YELLOW}[WARN]${_LIB_NC}  $1" >&2
    fi
}

log_error() {
    echo -e "${_LIB_RED}[ERROR]${_LIB_NC} $1" >&2
}

# Print a fatal error, run caller cleanup if present, and exit.
#
# Scripts source this library rather than executing it, so a shared fatal path
# keeps cleanup behavior consistent without forcing each caller to duplicate the
# same trap-aware shutdown logic.
error_exit() {
    local message="$1"
    local code="${2:-1}"
    log_error "$message"
    # If the caller defines a cleanup function, call it
    if declare -f cleanup >/dev/null 2>&1; then
        cleanup
    fi
    exit "$code"
}

# ── Service configuration ──────────────────────────────────────────────────
# Single source of truth for port assignments, binary names, and health
# endpoints. Override via environment variables.
#
# Uses plain variables (not associative arrays) for bash 3.2 compatibility
# (macOS system bash). Access pattern: SERVICE_PORT_PLC, SERVICE_URL_PDS, etc.

# Ports
SERVICE_PORT_PLC="${PLC_PORT:-2582}"
SERVICE_PORT_PDS="${PDS_PORT:-2583}"
SERVICE_PORT_RELAY="${RELAY_PORT:-2584}"
SERVICE_PORT_APPVIEW="${APPVIEW_PORT:-3200}"
SERVICE_PORT_CHAT="${CHAT_PORT:-2585}"
SERVICE_PORT_VIDEO="${VIDEO_PORT:-2586}"
SERVICE_PORT_PDS2="${PDS2_PORT:-2587}"
SERVICE_PORT_UI="${UI_PORT:-2590}"

# URLs
SERVICE_URL_PLC="http://127.0.0.1:$SERVICE_PORT_PLC"
SERVICE_URL_PDS="http://127.0.0.1:$SERVICE_PORT_PDS"
SERVICE_URL_RELAY="http://127.0.0.1:$SERVICE_PORT_RELAY"
SERVICE_URL_APPVIEW="http://127.0.0.1:$SERVICE_PORT_APPVIEW"
SERVICE_URL_CHAT="http://127.0.0.1:$SERVICE_PORT_CHAT"
SERVICE_URL_VIDEO="http://127.0.0.1:$SERVICE_PORT_VIDEO"
SERVICE_URL_PDS2="http://127.0.0.1:$SERVICE_PORT_PDS2"
SERVICE_URL_UI="http://127.0.0.1:$SERVICE_PORT_UI"

# Binaries
SERVICE_BINARY_PLC="campagnola"
SERVICE_BINARY_PDS="kaszlak"
SERVICE_BINARY_RELAY="zuk"
SERVICE_BINARY_APPVIEW="syrena"
SERVICE_BINARY_CHAT="syrena-chat"
SERVICE_BINARY_VIDEO="jelcz"
SERVICE_BINARY_PDS2="kaszlak"
SERVICE_BINARY_UI="garazyk-ui"

# Health paths
SERVICE_HEALTH_PLC="${PLC_HEALTH_PATH:-/_health}"
SERVICE_HEALTH_PDS="${PDS_HEALTH_PATH:-/xrpc/com.atproto.server.describeServer}"
SERVICE_HEALTH_RELAY="${RELAY_HEALTH_PATH:-/api/relay/health}"
SERVICE_HEALTH_APPVIEW="${APPVIEW_HEALTH_PATH:-/admin/backfill/status}"
SERVICE_HEALTH_CHAT="${CHAT_HEALTH_PATH:-/_health}"
SERVICE_HEALTH_VIDEO="${VIDEO_HEALTH_PATH:-/_health}"
SERVICE_HEALTH_PDS2="${PDS2_HEALTH_PATH:-/xrpc/com.atproto.server.describeServer}"
SERVICE_HEALTH_UI="${UI_HEALTH_PATH:-/admin}"

# Health URLs
SERVICE_HEALTH_URL_PLC="$SERVICE_URL_PLC$SERVICE_HEALTH_PLC"
SERVICE_HEALTH_URL_PDS="$SERVICE_URL_PDS$SERVICE_HEALTH_PDS"
SERVICE_HEALTH_URL_RELAY="$SERVICE_URL_RELAY$SERVICE_HEALTH_RELAY"
SERVICE_HEALTH_URL_APPVIEW="$SERVICE_URL_APPVIEW$SERVICE_HEALTH_APPVIEW"
SERVICE_HEALTH_URL_CHAT="$SERVICE_URL_CHAT$SERVICE_HEALTH_CHAT"
SERVICE_HEALTH_URL_VIDEO="$SERVICE_URL_VIDEO$SERVICE_HEALTH_VIDEO"
SERVICE_HEALTH_URL_PDS2="$SERVICE_URL_PDS2$SERVICE_HEALTH_PDS2"
SERVICE_HEALTH_URL_UI="$SERVICE_URL_UI$SERVICE_HEALTH_UI"

# All service keys (for iteration)
_LIB_ALL_SERVICES="plc pds relay appview chat video pds2 ui"

# Helper to look up a variable by service key prefix
# Usage: _svc_port plc  →  $SERVICE_PORT_PLC
#        _svc_url pds   →  $SERVICE_URL_PDS
_svc_var() { eval echo "\"\${$1:-}\""; }

# ── E2E run context and diagnostics ─────────────────────────────────────────

atproto_e2e_sanitize_run_id() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]_.-' '-'
}

atproto_e2e_default_run_id() {
    printf '%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
}

atproto_e2e_load_latest_run_id() {
    local name="$1"
    local base_dir="${ATPROTO_E2E_BASE_DIR:-/tmp/garazyk-atproto-e2e}"
    local latest_file="$base_dir/latest-$name-run-id"
    if [[ -z "${ATPROTO_E2E_RUN_ID:-}" && -f "$latest_file" ]]; then
        ATPROTO_E2E_RUN_ID="$(head -n 1 "$latest_file")"
        export ATPROTO_E2E_RUN_ID
    fi
}

atproto_e2e_store_latest_run_id() {
    local name="$1"
    local base_dir="${ATPROTO_E2E_BASE_DIR:-/tmp/garazyk-atproto-e2e}"
    mkdir -p "$base_dir"
    printf '%s\n' "$ATPROTO_E2E_RUN_ID" > "$base_dir/latest-$name-run-id"
}

# Initialize the shared run directory used by scenario, demo, and e2e scripts.
#
# Callers may set ATPROTO_E2E_RUN_ID, ATPROTO_E2E_RUN_DIR, or
# ATPROTO_E2E_DIAGNOSTICS_DIR before calling this function. The function
# exports the resolved values so child Python seeders and helper scripts write
# into the same run context.
atproto_e2e_init_run() {
    local requested_run_id="${ATPROTO_E2E_RUN_ID:-}"
    if [[ -z "$requested_run_id" ]]; then
        requested_run_id="$(atproto_e2e_default_run_id)"
    fi

    ATPROTO_E2E_RUN_ID="$(atproto_e2e_sanitize_run_id "$requested_run_id")"
    ATPROTO_E2E_BASE_DIR="${ATPROTO_E2E_BASE_DIR:-/tmp/garazyk-atproto-e2e}"
    ATPROTO_E2E_RUN_DIR="${ATPROTO_E2E_RUN_DIR:-$ATPROTO_E2E_BASE_DIR/$ATPROTO_E2E_RUN_ID}"
    ATPROTO_E2E_DIAGNOSTICS_DIR="${ATPROTO_E2E_DIAGNOSTICS_DIR:-$ATPROTO_E2E_RUN_DIR/diagnostics}"
    ATPROTO_E2E_LOG_DIR="${ATPROTO_E2E_LOG_DIR:-$ATPROTO_E2E_RUN_DIR/logs}"
    ATPROTO_E2E_PID_FILE="${ATPROTO_E2E_PID_FILE:-$ATPROTO_E2E_RUN_DIR/pids.txt}"
    local compose_run_id
    compose_run_id="$(printf '%s' "$ATPROTO_E2E_RUN_ID" | tr '._' '--' | tr -c '[:alnum:]-' '-')"
    ATPROTO_E2E_COMPOSE_PROJECT="${ATPROTO_E2E_COMPOSE_PROJECT:-garazyk-e2e-$compose_run_id}"

    export ATPROTO_E2E_RUN_ID
    export ATPROTO_E2E_BASE_DIR
    export ATPROTO_E2E_RUN_DIR
    export ATPROTO_E2E_DIAGNOSTICS_DIR
    export ATPROTO_E2E_LOG_DIR
    export ATPROTO_E2E_PID_FILE
    export ATPROTO_E2E_COMPOSE_PROJECT

    mkdir -p "$ATPROTO_E2E_RUN_DIR" "$ATPROTO_E2E_DIAGNOSTICS_DIR" "$ATPROTO_E2E_LOG_DIR"
}

atproto_redact_stream() {
    sed -E \
        -e 's/(Authorization:[[:space:]]*Bearer )[A-Za-z0-9._~+\/=-]+/\1[REDACTED]/g' \
        -e 's/("(accessJwt|refreshJwt|token|password|secret|masterSecret|adminPassword)"[[:space:]]*:[[:space:]]*")[^"]+"/\1[REDACTED]"/g' \
        -e 's/((JWT|TOKEN|PASSWORD|SECRET|MASTER_SECRET|ADMIN_SECRET)=)[^[:space:]]+/\1[REDACTED]/g'
}

atproto_write_run_metadata() {
    local output_dir="${1:-$ATPROTO_E2E_DIAGNOSTICS_DIR}"
    mkdir -p "$output_dir"
    {
        printf 'run_id=%s\n' "${ATPROTO_E2E_RUN_ID:-unknown}"
        printf 'run_dir=%s\n' "${ATPROTO_E2E_RUN_DIR:-unknown}"
        printf 'diagnostics_dir=%s\n' "${ATPROTO_E2E_DIAGNOSTICS_DIR:-unknown}"
        printf 'compose_project=%s\n' "${ATPROTO_E2E_COMPOSE_PROJECT:-}"
        printf 'repo_root=%s\n' "${REPO_ROOT:-}"
        printf 'build_dir=%s\n' "${BUILD_DIR:-}"
        printf 'created_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if command -v git >/dev/null 2>&1 && [[ -n "${REPO_ROOT:-}" ]]; then
            git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null | sed 's/^/git_commit=/' || true
            git -C "$REPO_ROOT" status --short 2>/dev/null | sed 's/^/git_status=/' || true
        fi
    } | atproto_redact_stream > "$output_dir/run-metadata.txt"
}

atproto_collect_http_endpoint() {
    local output_dir="$1"
    local name="$2"
    local url="$3"
    shift 3

    local http_dir="$output_dir/http"
    local raw_path="$http_dir/$name.raw"
    local redacted_path="$http_dir/$name.txt"
    mkdir -p "$http_dir"

    {
        printf 'url=%s\n' "$url"
        curl -sS -L --max-time 8 -w '\nhttp_status=%{http_code}\ncontent_type=%{content_type}\n' "$@" "$url" || true
    } > "$raw_path" 2>&1
    atproto_redact_stream < "$raw_path" > "$redacted_path"
    rm -f "$raw_path"
}

atproto_copy_service_logs() {
    local output_dir="$1"
    local log_dir="${2:-${ATPROTO_E2E_LOG_DIR:-}}"

    if [[ -n "$log_dir" && -d "$log_dir" ]]; then
        mkdir -p "$output_dir/service-logs"
        cp -p "$log_dir"/*.log "$output_dir/service-logs/" 2>/dev/null || true
    fi
    if [[ -n "${ATPROTO_E2E_PID_FILE:-}" && -f "$ATPROTO_E2E_PID_FILE" ]]; then
        cp -p "$ATPROTO_E2E_PID_FILE" "$output_dir/pids.txt" 2>/dev/null || true
    fi
}

# Collect a diagnostic bundle for the standard local ATProto service ports.
#
# Usage:
#   atproto_collect_diagnostics <dir> [compose_dir compose_project compose_file...]
#
# The docker section is optional. HTTP captures are redacted; service log files
# are copied locally so developers can inspect exact process output when needed.
atproto_collect_diagnostics() {
    local output_dir="${1:-$ATPROTO_E2E_DIAGNOSTICS_DIR}"
    shift || true
    local compose_dir="${1:-}"
    local compose_project="${2:-${ATPROTO_E2E_COMPOSE_PROJECT:-}}"
    if (( $# >= 2 )); then
        shift 2
    else
        set --
    fi
    local compose_files=("$@")

    mkdir -p "$output_dir"
    atproto_write_run_metadata "$output_dir"
    atproto_copy_service_logs "$output_dir"

    atproto_collect_http_endpoint "$output_dir" "plc-health" "$SERVICE_URL_PLC/_health"
    atproto_collect_http_endpoint "$output_dir" "pds-describe-server" "$SERVICE_URL_PDS/xrpc/com.atproto.server.describeServer"
    atproto_collect_http_endpoint "$output_dir" "relay-health" "$SERVICE_URL_RELAY/api/relay/health"
    atproto_collect_http_endpoint "$output_dir" "relay-upstreams" "$SERVICE_URL_RELAY/api/relay/upstreams"
    atproto_collect_http_endpoint "$output_dir" "appview-backfill-status" "$SERVICE_URL_APPVIEW/admin/backfill/status" \
        -H "Authorization: Bearer ${APPVIEW_ADMIN_SECRET:-localdevadmin}"
    atproto_collect_http_endpoint "$output_dir" "pds2-describe-server" "$SERVICE_URL_PDS2/xrpc/com.atproto.server.describeServer"
    atproto_collect_http_endpoint "$output_dir" "chat-health" "$SERVICE_URL_CHAT/_health"
    atproto_collect_http_endpoint "$output_dir" "video-health" "$SERVICE_URL_VIDEO/_health"
    atproto_collect_http_endpoint "$output_dir" "ui-admin" "$SERVICE_URL_UI/admin"

    if [[ -n "$compose_dir" ]] && (( ${#compose_files[@]} > 0 )) && command -v docker >/dev/null 2>&1; then
        mkdir -p "$output_dir/docker"
        local compose_cmd=(docker compose)
        if [[ -n "$compose_project" ]]; then
            compose_cmd+=(-p "$compose_project")
        fi
        local compose_file
        for compose_file in "${compose_files[@]}"; do
            compose_cmd+=(-f "$compose_file")
        done

        (
            cd "$compose_dir"
            "${compose_cmd[@]}" ps --all > "$output_dir/docker/ps.txt" 2>&1 || true
            "${compose_cmd[@]}" config > "$output_dir/docker/config.txt" 2>&1 || true
            "${compose_cmd[@]}" logs --no-color --timestamps --tail=3000 > "$output_dir/docker/logs.raw" 2>&1 || true
        )
        atproto_redact_stream < "$output_dir/docker/logs.raw" > "$output_dir/docker/logs.txt"
        rm -f "$output_dir/docker/logs.raw"
    fi

    log_info "Diagnostics written to $output_dir"
}

# ── Health check ────────────────────────────────────────────────────────────

# Wait for an HTTP endpoint to become available.
#
# Usage: wait_for_http <url> <label> [timeout_seconds]
# Returns 0 once curl -f accepts the response, otherwise returns 1 after the
# timeout. The caller decides whether a timeout is fatal because some optional
# services are useful even when their health endpoint is temporarily missing.
wait_for_http() {
    local url="$1"
    local label="${2:-$url}"
    local timeout="${3:-30}"

    local deadline=$(( $(date +%s) + timeout ))
    while [[ $(date +%s) -lt $deadline ]]; do
        if curl -s -f "$url" >/dev/null 2>&1; then
            log_ok "$label is healthy"
            return 0
        fi
        sleep 0.5
    done
    log_warn "$label not healthy after ${timeout}s ($url)"
    return 1
}

# Wait for a named service by its key (plc, pds, relay, etc.).
#
# Usage: wait_for_service <service_key> [timeout_seconds]
# Looks up the service's health URL from the shared SERVICE_* variables. AppView
# uses an admin endpoint for readiness, so this helper injects the local admin
# bearer token when polling that service.
wait_for_service() {
    local service_key="$1"
    local timeout="${2:-30}"
    local service_upper
    service_upper="$(echo "$service_key" | tr '[:lower:]' '[:upper:]')"
    local url="$(_svc_var "SERVICE_HEALTH_URL_$service_upper")"
    local label="$service_upper"

    if [[ -z "$url" ]]; then
        log_error "Unknown service key: $service_key"
        return 1
    fi

    # AppView health endpoint requires auth
    local extra_args=()
    if [[ "$service_key" == "appview" ]]; then
        extra_args=(-H "Authorization: Bearer ${APPVIEW_ADMIN_SECRET:-localdevadmin}")
    fi

    local deadline=$(( $(date +%s) + timeout ))
    while [[ $(date +%s) -lt $deadline ]]; do
        if curl -s -f ${extra_args[@]+"${extra_args[@]}"} "$url" >/dev/null 2>&1; then
            log_ok "$label is healthy"
            return 0
        fi
        sleep 0.5
    done
    log_warn "$label not healthy after ${timeout}s ($url)"
    return 1
}

# ── Process management ───────────────────────────────────────────────────────

# Kill stray instances of known local service processes.
#
# The scripts regularly start and stop short-lived demo stacks. Matching by the
# expected binary and port avoids disturbing unrelated processes with the same
# binary name while still cleaning up listeners that were orphaned by an
# interrupted run.
# Usage: kill_stray_processes [service_key ...]
#   With no args, kills all services. With args, kills only named services.
kill_stray_processes() {
    local services=("$@")
    if (( ${#services[@]} == 0 )); then
        services=($_LIB_ALL_SERVICES)
    fi

    for _svc in "${services[@]}"; do
        local binary="$(_svc_var "SERVICE_BINARY_$(echo "$_svc" | tr '[:lower:]' '[:upper:]')")"
        local port="$(_svc_var "SERVICE_PORT_$(echo "$_svc" | tr '[:lower:]' '[:upper:]')")"
        if [[ -n "$binary" ]] && [[ -n "$port" ]]; then
            local pids=()
            if command -v pgrep >/dev/null 2>&1; then
                while read -r pid; do
                    if [[ "$pid" =~ ^[0-9]+$ ]]; then
                        pids+=("$pid")
                    fi
                done < <(pgrep -f "${binary}.*${port}" 2>/dev/null || true)
            else
                pkill -f "${binary}.*${port}" 2>/dev/null || true
            fi
            if command -v lsof >/dev/null 2>&1; then
                while read -r pid; do
                    if [[ "$pid" =~ ^[0-9]+$ ]]; then
                        pids+=("$pid")
                    fi
                done < <(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
            fi

            local pid
            for pid in ${pids[@]+"${pids[@]}"}; do
                kill "$pid" 2>/dev/null || true
            done

            local deadline=$(( $(date +%s) + 5 ))
            while [[ $(date +%s) -lt $deadline ]]; do
                local still_running=false
                if command -v lsof >/dev/null 2>&1 && lsof -tiTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
                    still_running=true
                else
                    for pid in ${pids[@]+"${pids[@]}"}; do
                        if kill -0 "$pid" 2>/dev/null; then
                            still_running=true
                            break
                        fi
                    done
                fi
                [[ "$still_running" == "true" ]] || break
                sleep 0.2
            done

            if command -v lsof >/dev/null 2>&1; then
                local listener_pids=()
                local listener_count=0
                while read -r pid; do
                    if [[ "$pid" =~ ^[0-9]+$ ]]; then
                        listener_pids+=("$pid")
                        listener_count=$(( listener_count + 1 ))
                    fi
                done < <(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
                if (( listener_count > 0 )); then
                    log_warn "Force-killing ${binary} listener(s) on port $port"
                    for pid in ${listener_pids[@]+"${listener_pids[@]}"}; do
                        kill -9 "$pid" 2>/dev/null || true
                    done
                fi
            fi
        fi
    done
    unset _svc
}

# Check that required service binaries exist and are executable.
#
# This intentionally fails before any network listeners or data directories are
# created, making missing-build errors fast and leaving the workspace unchanged.
# Usage: check_binaries <build_dir> [service_key ...]
#   Exits with error if any binary is missing.
check_binaries() {
    local build_dir="$1"
    shift
    local services=("$@")
    if (( ${#services[@]} == 0 )); then
        services=($_LIB_ALL_SERVICES)
    fi

    for _svc in "${services[@]}"; do
        local binary="$(_svc_var "SERVICE_BINARY_$(echo "$_svc" | tr '[:lower:]' '[:upper:]')")"
        local path="$build_dir/$binary"
        if [[ ! -x "$path" ]]; then
            error_exit "Binary not found: $path (build with: cmake --build build --target $binary)" 3
        fi
    done
    unset _svc
    log_ok "All service binaries found"
}

# ── Dependency check ─────────────────────────────────────────────────────────

# Check that required commands are available on PATH.
#
# Callers should include only the tools they actually use. Keeping the list
# local to each script makes partial workflows such as "start only PLC" easier
# to run on minimal development machines.
# Usage: check_dependencies cmd1 cmd2 ...
check_dependencies() {
    local deps=("$@")
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
