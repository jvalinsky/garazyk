#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="${PROJECT_DIR}/build-linux/bin/kaszlak"
CONFIG="${PROJECT_DIR}/config/production.json"
DATA_DIR="${DEPLOY_DIR:-$HOME/pds-data}"
KEYS_DIR="${DATA_DIR}/keys"
SECRETS_DIR="${HOME}/.secrets"

# Arguments
EMAIL=""
HANDLE=""
PASSWORD=""
CF_TOKEN=""
CF_ZONE_ID=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --email EMAIL --handle HANDLE --password PASS --cf-token TOKEN --cf-zone-id ZONE_ID

Set up a fresh PDS instance with an admin account.

Arguments:
  --email       Admin account email address
  --handle      Admin handle (e.g. alice.garazyk.xyz)
  --password    Admin account password
  --cf-token    Cloudflare API token for DNS management
  --cf-zone-id  Cloudflare zone ID for garazyk.xyz
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --email)      EMAIL="$2"; shift 2 ;;
        --handle)     HANDLE="$2"; shift 2 ;;
        --password)   PASSWORD="$2"; shift 2 ;;
        --cf-token)   CF_TOKEN="$2"; shift 2 ;;
        --cf-zone-id) CF_ZONE_ID="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *)            die "Unknown argument: $1" ;;
    esac
done

[[ -z "$EMAIL" ]]      && die "--email is required"
[[ -z "$HANDLE" ]]     && die "--handle is required"
[[ -z "$PASSWORD" ]]   && die "--password is required"
[[ -z "$CF_TOKEN" ]]   && die "--cf-token is required"
[[ -z "$CF_ZONE_ID" ]] && die "--cf-zone-id is required"

# Extract subdomain from handle (e.g. "alice" from "alice.garazyk.xyz")
SUBDOMAIN="${HANDLE%%.*}"

# ─────────────────────────────────────────────────────────────
section "Pre-flight checks"

# Check binary exists
if [[ -x "$BINARY" ]]; then
    info "Binary found: ${BINARY}"
else
    die "Binary not found or not executable: ${BINARY}"
fi

# Check config exists
if [[ -f "$CONFIG" ]]; then
    info "Config found: ${CONFIG}"
else
    die "Config not found: ${CONFIG}"
fi

# Check plc.directory is reachable
if curl -sf --max-time 5 "https://plc.directory/health" > /dev/null 2>&1; then
    info "plc.directory is reachable"
else
    # Try a simple HEAD request as fallback
    if curl -sf --max-time 5 -o /dev/null "https://plc.directory" 2>/dev/null; then
        info "plc.directory is reachable"
    else
        die "Cannot reach https://plc.directory — is the network up?"
    fi
fi

# ─────────────────────────────────────────────────────────────
section "Creating data directories"

mkdir -p "$DATA_DIR"
chmod 0750 "$DATA_DIR"
info "Created ${DATA_DIR} (0750)"

mkdir -p "$KEYS_DIR"
chmod 0700 "$KEYS_DIR"
info "Created ${KEYS_DIR} (0700)"

# ─────────────────────────────────────────────────────────────
section "Creating admin account"

info "Creating account: ${HANDLE} (${EMAIL})"
account_output=$(
    "$BINARY" account create \
        --email "$EMAIL" \
        --handle "$HANDLE" \
        --password "$PASSWORD" \
        --config "$CONFIG" \
        --verbose \
        2>&1
) || die "Failed to create account:\n${account_output}"

echo "$account_output"

# Extract DID from verbose log output ("Generated and Registered DID: did:plc:...")
DID=$(echo "$account_output" | grep -oE 'did:plc:[a-z2-7]{24}' | head -1 || true)

# Fallback: look up DID by handle
if [[ -z "$DID" ]]; then
    DID=$(
        "$BINARY" account list --config "$CONFIG" 2>&1 \
        | grep "$HANDLE" \
        | grep -oE 'did:plc:[a-z2-7]{24}' \
        | head -1 || true
    )
fi

if [[ -n "$DID" ]]; then
    info "Account created with DID: ${DID}"
else
    warn "Account created but could not extract DID"
    warn "Continuing — DID verification will be skipped"
fi

# ─────────────────────────────────────────────────────────────
section "Verifying DID registration at plc.directory"

if [[ -n "$DID" ]]; then
    verified=false
    for attempt in $(seq 1 10); do
        if curl -sf "https://plc.directory/${DID}" > /dev/null 2>&1; then
            info "DID verified at plc.directory (attempt ${attempt}/10)"
            verified=true
            break
        fi
        warn "Attempt ${attempt}/10 — DID not yet visible, retrying in 2s..."
        sleep 2
    done

    if [[ "$verified" != "true" ]]; then
        error "DID not found at plc.directory after 10 attempts"
        warn "This may resolve itself — the PLC operation may still be propagating"
    fi
else
    warn "Skipping DID verification (no DID extracted)"
fi

# ─────────────────────────────────────────────────────────────
section "Creating Cloudflare DNS record"

info "Creating CNAME: ${SUBDOMAIN}.garazyk.xyz → ${DEPLOY_HOST:?DEPLOY_HOST not set}"
"${SCRIPT_DIR}/cloudflare-dns.sh" \
    --token "$CF_TOKEN" \
    --zone-id "$CF_ZONE_ID" \
    --subdomain "${SUBDOMAIN}.garazyk.xyz" \
    --target "${DEPLOY_HOST}"

# Also ensure pds.garazyk.xyz CNAME exists
info "Ensuring pds.garazyk.xyz CNAME exists..."
"${SCRIPT_DIR}/cloudflare-dns.sh" \
    --token "$CF_TOKEN" \
    --zone-id "$CF_ZONE_ID" \
    --subdomain "pds.garazyk.xyz" \
    --target "${DEPLOY_HOST}"

# ─────────────────────────────────────────────────────────────
section "Generating invite codes"

INVITE_CODES=""
for i in $(seq 1 5); do
    raw=$(
        "$BINARY" invite create \
            --config "$CONFIG" \
            2>&1
    ) || { warn "Failed to generate invite code ${i}"; continue; }
    # Extract code from "  Code:     XXXX-XXXX-XXXX" output
    code_val=$(echo "$raw" | grep 'Code:' | awk '{print $NF}' || echo "")
    if [[ -z "$code_val" || "$code_val" == "(null)" ]]; then
        warn "Invite code ${i} returned empty"
        continue
    fi
    INVITE_CODES+="  ${i}. ${code_val}\n"
    info "Invite code ${i}: ${code_val}"
done

# ─────────────────────────────────────────────────────────────
section "Backing up server rotation key"

mkdir -p "$SECRETS_DIR"
chmod 0700 "$SECRETS_DIR"

if [[ -d "$KEYS_DIR" ]] && ls "${KEYS_DIR}"/* > /dev/null 2>&1; then
    BACKUP_FILE="${SECRETS_DIR}/pds-rotation-key-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$BACKUP_FILE" -C "$DATA_DIR" keys/
    chmod 0600 "$BACKUP_FILE"
    info "Rotation key backed up to: ${BACKUP_FILE}"
else
    warn "No key files found in ${KEYS_DIR} — skipping backup"
    warn "The server may generate keys on first start; back up ${KEYS_DIR} after starting"
fi

# ─────────────────────────────────────────────────────────────
section "Setup Complete"

echo -e ""
echo -e "${BOLD}PDS Setup Summary${NC}"
echo -e "─────────────────────────────────────────────────"
echo -e "  PDS hostname:    ${CYAN}pds.garazyk.xyz${NC}"
echo -e "  PDS port:        ${CYAN}2583${NC}"
echo -e "  Admin handle:    ${CYAN}${HANDLE}${NC}"
echo -e "  Admin email:     ${CYAN}${EMAIL}${NC}"
[[ -n "$DID" ]] && \
echo -e "  Admin DID:       ${CYAN}${DID}${NC}"
echo -e "  Data directory:  ${CYAN}${DATA_DIR}${NC}"
echo -e "  Config:          ${CYAN}${CONFIG}${NC}"
echo -e "  PLC directory:   ${CYAN}https://plc.directory${NC}"
echo -e "─────────────────────────────────────────────────"
echo -e ""
if [[ -n "$INVITE_CODES" ]]; then
    echo -e "${BOLD}Invite Codes:${NC}"
    echo -e "$INVITE_CODES"
fi
echo -e "${BOLD}Next steps:${NC}"
echo -e "  1. Install nginx config:  ${CYAN}sudo cp config/nginx-pds.conf /etc/nginx/sites-enabled/pds.conf${NC}"
echo -e "  2. Reload nginx:          ${CYAN}sudo nginx -t && sudo systemctl reload nginx${NC}"
echo -e "  3. Install systemd unit:  ${CYAN}sudo cp config/pds.service /etc/systemd/system/${NC}"
echo -e "  4. Start the PDS:         ${CYAN}sudo systemctl enable --now pds${NC}"
echo -e ""
