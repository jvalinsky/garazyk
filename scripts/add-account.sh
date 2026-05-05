#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="${PROJECT_DIR}/build-linux/bin/kaszlak"
CONFIG="${PROJECT_DIR}/config/production.json"

EMAIL=""
HANDLE=""
PASSWORD=""
CF_TOKEN=""
CF_ZONE_ID=""

usage() {
    cat <<EOF
Usage: $(basename "$0") --email EMAIL --handle HANDLE [--password PASS] --cf-token TOKEN --cf-zone-id ZONE_ID

Create a new account on the PDS and add its DNS record.
If --password is omitted, a random one is generated.
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
[[ -z "$CF_TOKEN" ]]   && die "--cf-token is required"
[[ -z "$CF_ZONE_ID" ]] && die "--cf-zone-id is required"

if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(openssl rand -base64 24)
    info "Generated password: ${PASSWORD}"
fi

SUBDOMAIN="${HANDLE%%.*}"

# Create account
info "Creating account: ${HANDLE} (${EMAIL})"
account_output=$(
    "$BINARY" account create \
        --email "$EMAIL" \
        --handle "$HANDLE" \
        --password "$PASSWORD" \
        --config "$CONFIG" \
        2>&1
) || die "Failed to create account:\n${account_output}"

echo "$account_output"

DID=$(echo "$account_output" | grep -oE 'did:plc:[a-z2-7]{24}' | head -1 || true)
[[ -n "$DID" ]] && info "DID: ${DID}"

# Verify DID at plc.directory
if [[ -n "$DID" ]]; then
    for attempt in $(seq 1 10); do
        if curl -sf "https://plc.directory/${DID}" > /dev/null 2>&1; then
            info "DID verified at plc.directory"
            break
        fi
        [[ $attempt -eq 10 ]] && warn "DID not yet visible at plc.directory"
        sleep 2
    done
fi

# Create DNS record
info "Creating CNAME: ${SUBDOMAIN}.garazyk.xyz → DEPLOY_HOST"
"${SCRIPT_DIR}/cloudflare-dns.sh" \
    --token "$CF_TOKEN" \
    --zone-id "$CF_ZONE_ID" \
    --subdomain "${SUBDOMAIN}.garazyk.xyz" \
    --target "DEPLOY_HOST"

# Backup keys
KEYS_DIR="DEPLOY_DIR/pds-data/keys"
SECRETS_DIR="${HOME}/.secrets"
if [[ -d "$KEYS_DIR" ]] && ls "${KEYS_DIR}"/* > /dev/null 2>&1; then
    mkdir -p "$SECRETS_DIR" && chmod 0700 "$SECRETS_DIR"
    BACKUP="${SECRETS_DIR}/pds-keys-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "$BACKUP" -C DEPLOY_DIR/pds-data keys/
    chmod 0600 "$BACKUP"
    info "Keys backed up to: ${BACKUP}"
fi

echo -e "\n${BOLD}Account created:${NC} ${CYAN}${HANDLE}${NC}"
[[ -n "$DID" ]] && echo -e "${BOLD}DID:${NC} ${CYAN}${DID}${NC}"
echo -e "${BOLD}DNS:${NC} Wait ~60s for TLS cert, then verify: ${CYAN}curl https://${HANDLE}/.well-known/atproto-did${NC}"
