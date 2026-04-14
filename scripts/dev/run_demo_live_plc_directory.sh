#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_demo_live_plc_directory.sh [options]

Starts the PDS and seeds demo data while using the PUBLIC PLC directory at:
  https://plc.directory

This will POST operations to plc.directory (writes are public and hard to undo).

Options:
  --port <port>              PDS port (default: 2583)
  --data-dir <path>          Data directory (default: /tmp/objpds-demo-live-plc-data)
  --plc-url <url>            PLC directory URL (default: https://plc.directory)
  --listen-host <ip|name>    Bind address for the HTTP listener (default: 127.0.0.1)
  --local-url-host <host>    Host used for local health checks/seed requests (default: 127.0.0.1)
  --server-host <host>       Hostname written into PLC operations as the PDS service endpoint (default: localhost)
  --issuer <url>             JWT issuer (default: derived from server-host/port)
  --pds-bin <path>           Path to PDS binary (default: ./build/bin/kaszlak)
  --log-level <level>        debug|info|warn|error (default: debug)
  --log-file <path>          PDS stdout/stderr log file (default: /tmp/objpds-demo-live-plc-pds.log)
  --pid-file <path>          PID file path (default: /tmp/objpds-demo-live-plc-pds.pid)
  --keep-data                Don't wipe the data directory before starting
  --no-seed                  Start server but skip demo seeding
  --seed-mode <mode>         create|login (default: create)
  --handle-domain <domain>   Handle domain for demo accounts (default: test)
  --account-prefixes <list>  Comma-separated prefixes (default: alice,bob)
  --posts-per-account <n>    Number of posts per account (default: 3)
  --no-profiles              Don't create profile records
  --suffix <text>            Fixed suffix for handles/emails (default: random)
  --password <pw>            Fixed password for demo accounts (default: hunter<suffix>)
  --email-domain <domain>    Email domain (default: test.invalid)
  --yes                      Skip the interactive confirmation prompt
  --help                     Show this help

Environment overrides:
  PDS_EXPLORE_CACHE_DIR Explorer cache directory
EOF
}

die() {
  echo "Error: $*" >&2
  exit 2
}

json_escape() {
  local s="${1}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "${s}"
}

normalize_url() {
  local url="${1}"
  # Strip trailing slash (common in env vars)
  while [[ "${url}" == */ ]]; do
    url="${url%/}"
  done
  printf '%s' "${url}"
}

is_remote_plc_url() {
  local url="${1}"
  case "${url}" in
    ""|"mock") return 1 ;;
    http://127.0.0.1*|http://localhost*|http://0.0.0.0*|https://127.0.0.1*|https://localhost*|https://0.0.0.0*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

confirm_remote_plc_directory() {
  local plc_url="${1}"
  local service_endpoint="${2}"
  local handle_domain="${3}"
  local prefixes="${4}"

  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi
  if ! is_remote_plc_url "${plc_url}"; then
    return 0
  fi

  cat >&2 <<EOF
WARNING: This demo will WRITE to a PLC directory:
  ${plc_url}

Continuing will POST PLC operations to that directory, minting new did:plc identifiers.
These writes are public and are not meant for throwaway/local demos unless you
understand the implications.

This run will advertise this PDS endpoint in the PLC operations:
  ${service_endpoint}

Demo handles will look like:
  <prefix><suffix>.${handle_domain}
Prefixes: ${prefixes}

EOF

  local reply=""
  if [[ -t 0 ]]; then
    read -r -p "Type 'yes' to continue: " reply
  else
    # Non-interactive: require --yes
    echo "Error: refusing to run non-interactively without --yes" >&2
    exit 2
  fi

  if [[ "${reply}" != "yes" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
cd "${PROJECT_ROOT}"

AUTO_YES="false"
PDS_PORT="2583"
DATA_DIR="/tmp/objpds-demo-live-plc-data"
PLC_URL="https://plc.directory"
LISTEN_HOST="127.0.0.1"
LOCAL_URL_HOST="127.0.0.1"
SERVER_HOST="localhost"
ISSUER=""
PDS_BIN="${PROJECT_ROOT}/build/bin/kaszlak"
LOG_LEVEL="debug"
LOG_FILE="/tmp/objpds-demo-live-plc-pds.log"
PID_FILE="/tmp/objpds-demo-live-plc-pds.pid"
WIPE_DATA="true"
SEED="true"
SEED_MODE="create"

DEMO_HANDLE_DOMAIN="test"
DEMO_ACCOUNT_PREFIXES="alice,bob"
DEMO_EMAIL_DOMAIN="test.invalid"
DEMO_POSTS_PER_ACCOUNT="3"
DEMO_CREATE_PROFILES="true"
DEMO_SUFFIX=""
DEMO_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PDS_PORT="${2:-}"
      shift 2
      ;;
    --data-dir)
      DATA_DIR="${2:-}"
      shift 2
      ;;
    --plc-url)
      PLC_URL="${2:-}"
      shift 2
      ;;
    --listen-host)
      LISTEN_HOST="${2:-}"
      shift 2
      ;;
    --local-url-host)
      LOCAL_URL_HOST="${2:-}"
      shift 2
      ;;
    --server-host)
      SERVER_HOST="${2:-}"
      shift 2
      ;;
    --issuer)
      ISSUER="${2:-}"
      shift 2
      ;;
    --pds-bin)
      PDS_BIN="${2:-}"
      shift 2
      ;;
    --log-level)
      LOG_LEVEL="${2:-}"
      shift 2
      ;;
    --log-file)
      LOG_FILE="${2:-}"
      shift 2
      ;;
    --pid-file)
      PID_FILE="${2:-}"
      shift 2
      ;;
    --keep-data)
      WIPE_DATA="false"
      shift
      ;;
    --no-seed)
      SEED="false"
      shift
      ;;
    --seed-mode)
      SEED_MODE="${2:-}"
      shift 2
      ;;
    --handle-domain)
      DEMO_HANDLE_DOMAIN="${2:-}"
      shift 2
      ;;
    --account-prefixes)
      DEMO_ACCOUNT_PREFIXES="${2:-}"
      shift 2
      ;;
    --posts-per-account)
      DEMO_POSTS_PER_ACCOUNT="${2:-}"
      shift 2
      ;;
    --no-profiles)
      DEMO_CREATE_PROFILES="false"
      shift
      ;;
    --suffix)
      DEMO_SUFFIX="${2:-}"
      shift 2
      ;;
    --password)
      DEMO_PASSWORD="${2:-}"
      shift 2
      ;;
    --email-domain)
      DEMO_EMAIL_DOMAIN="${2:-}"
      shift 2
      ;;
    --yes)
      AUTO_YES="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ -n "${PDS_PORT}" ]] || die "--port requires a value"
[[ -n "${DATA_DIR}" ]] || die "--data-dir requires a value"
[[ -n "${PLC_URL}" ]] || die "--plc-url requires a value"
[[ -n "${LISTEN_HOST}" ]] || die "--listen-host requires a value"
[[ -n "${LOCAL_URL_HOST}" ]] || die "--local-url-host requires a value"
[[ -n "${SERVER_HOST}" ]] || die "--server-host requires a value"
[[ -n "${PDS_BIN}" ]] || die "--pds-bin requires a value"
[[ -n "${LOG_LEVEL}" ]] || die "--log-level requires a value"

PLC_URL="$(normalize_url "${PLC_URL}")"

if [[ -z "${ISSUER}" ]]; then
  ISSUER="http://${SERVER_HOST}:${PDS_PORT}"
fi

if [[ ! -x "${PDS_BIN}" ]]; then
  echo "Error: PDS binary not found/executable: ${PDS_BIN}" >&2
  echo "Build it with: xcodebuild -scheme ATProtoPDS-CLI build" >&2
  exit 1
fi

SERVICE_ENDPOINT="http://${SERVER_HOST}:${PDS_PORT}"
confirm_remote_plc_directory "${PLC_URL}" "${SERVICE_ENDPOINT}" "${DEMO_HANDLE_DOMAIN}" "${DEMO_ACCOUNT_PREFIXES}"

cleanup() {
  if [[ -n "${PDS_PID:-}" ]]; then
    kill "${PDS_PID}" 2>/dev/null || true
    wait "${PDS_PID}" 2>/dev/null || true
  fi
  [[ -n "${CONFIG_PATH:-}" ]] && rm -f "${CONFIG_PATH}" 2>/dev/null || true
  [[ -n "${PID_FILE:-}" ]] && rm -f "${PID_FILE}" 2>/dev/null || true
}
trap cleanup EXIT

# Fresh data dir for repeatable demos
if [[ "${WIPE_DATA}" == "true" ]]; then
  rm -rf "${DATA_DIR}"
fi
mkdir -p "${DATA_DIR}/service"

CONFIG_PATH="$(mktemp -t objpds-live-plc-config.XXXXXX.json)"
SERVER_HOST_JSON="$(json_escape "${SERVER_HOST}")"
DATA_DIR_JSON="$(json_escape "${DATA_DIR}")"
PLC_URL_JSON="$(json_escape "${PLC_URL}")"

cat > "${CONFIG_PATH}" <<EOF
{
  "server": {
    "host": "${SERVER_HOST_JSON}",
    "port": ${PDS_PORT},
    "data_dir": "${DATA_DIR_JSON}"
  },
  "plc": {
    "url": "${PLC_URL_JSON}",
    "retry_count": 3,
    "retry_delay_ms": 1000
  },
  "debug": {
    "skip_plc_operations": false,
    "verbose_logging": true,
    "in_memory_databases": false,
    "reset_on_startup": false
  },
  "session": {
    "invite_code_required": false
  }
}
EOF

PDS_LOCAL_URL="http://${LOCAL_URL_HOST}:${PDS_PORT}"

echo "Starting PDS on ${PDS_LOCAL_URL} (data dir: ${DATA_DIR})"
echo "Config: ${CONFIG_PATH}"
echo "Log: ${LOG_FILE}"

export PDS_LISTEN_HOST="${LISTEN_HOST}"
export PDS_PLC_URL="${PLC_URL}"
export PDS_DEBUG_SKIP_PLC="0"
export PDS_ISSUER="${ISSUER}"
export PDS_LOG_LEVEL="${LOG_LEVEL}"
export PDS_EXPLORE_CACHE_DIR="${PDS_EXPLORE_CACHE_DIR:-/tmp/pds-explore-cache}"
export PYTHONDONTWRITEBYTECODE="1"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/tmp/objpds-python-cache}"
mkdir -p "${PYTHONPYCACHEPREFIX}"

"${PDS_BIN}" serve \
  --port "${PDS_PORT}" \
  --data-dir "${DATA_DIR}" \
  --config "${CONFIG_PATH}" \
  --log-level "${LOG_LEVEL}" > "${LOG_FILE}" 2>&1 &
PDS_PID=$!
echo "${PDS_PID}" > "${PID_FILE}"

echo "Waiting for PDS to be ready..."
for _ in {1..40}; do
  if curl -s --max-time 1 "${PDS_LOCAL_URL}/_health" >/dev/null 2>&1; then
    echo "PDS is up."
    break
  fi
  sleep 0.25
done

if ! curl -s --max-time 1 "${PDS_LOCAL_URL}/_health" >/dev/null 2>&1; then
  echo "Error: PDS failed to start. Log tail:" >&2
  tail -n 120 "${LOG_FILE}" >&2 || true
  exit 1
fi

if [[ "${SEED}" == "true" ]]; then
  echo "Seeding demo data (this may register DIDs with ${PLC_URL})..."
  PDS_URL="${PDS_LOCAL_URL}" \
    DEMO_SEED_MODE="${SEED_MODE}" \
    DEMO_HANDLE_DOMAIN="${DEMO_HANDLE_DOMAIN}" \
    DEMO_ACCOUNT_PREFIXES="${DEMO_ACCOUNT_PREFIXES}" \
    DEMO_EMAIL_DOMAIN="${DEMO_EMAIL_DOMAIN}" \
    DEMO_POSTS_PER_ACCOUNT="${DEMO_POSTS_PER_ACCOUNT}" \
    DEMO_CREATE_PROFILES="${DEMO_CREATE_PROFILES}" \
    DEMO_SUFFIX="${DEMO_SUFFIX}" \
    DEMO_PASSWORD="${DEMO_PASSWORD}" \
    python3 "${SCRIPT_DIR}/seed_demo_via_xrpc.py"
fi

echo ""
echo "Demo complete."
echo "PDS: ${PDS_LOCAL_URL}"
echo "Explorer: ${PDS_LOCAL_URL}/explore/"
echo "Log: ${LOG_FILE}"
echo "Press Ctrl+C to stop."

wait
