#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

# Defaults
TOKEN=""
ZONE_ID=""
SUBDOMAIN=""
TARGET="DEPLOY_HOST"

usage() {
    cat <<EOF
Usage: $(basename "$0") --token TOKEN --zone-id ZONE_ID --subdomain SUB [--target TARGET]

Create a CNAME record in Cloudflare (DNS Only, not proxied).

Arguments:
  --token      Cloudflare API token
  --zone-id    Cloudflare zone ID for the domain
  --subdomain  Subdomain to create (e.g. "alice" for alice.garazyk.xyz)
  --target     CNAME target (default: DEPLOY_HOST)
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)     TOKEN="$2"; shift 2 ;;
        --zone-id)   ZONE_ID="$2"; shift 2 ;;
        --subdomain) SUBDOMAIN="$2"; shift 2 ;;
        --target)    TARGET="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *)           die "Unknown argument: $1" ;;
    esac
done

[[ -z "$TOKEN" ]]     && die "--token is required"
[[ -z "$ZONE_ID" ]]   && die "--zone-id is required"
[[ -z "$SUBDOMAIN" ]] && die "--subdomain is required"

CF_API="https://api.cloudflare.com/client/v4"
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

# Check if record already exists
info "Checking if CNAME for '${SUBDOMAIN}' already exists..."
existing=$(curl -s -X GET \
    "${CF_API}/zones/${ZONE_ID}/dns_records?type=CNAME&name=${SUBDOMAIN}" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json")

result_count=$(echo "$existing" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('result',[])))" 2>/dev/null || echo "0")

if [[ "$result_count" -gt 0 ]]; then
    warn "CNAME record for '${SUBDOMAIN}' already exists — skipping creation"
    # Print existing record info
    echo "$existing" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data.get('result', []):
    print(f\"  Name: {r['name']}  →  {r['content']}  (proxied: {r['proxied']})\")
" 2>/dev/null || true
    exit 0
fi

# Create the CNAME record (DNS Only = proxied: false)
info "Creating CNAME: ${SUBDOMAIN} → ${TARGET} (DNS Only)..."
response=$(curl -s -X POST \
    "${CF_API}/zones/${ZONE_ID}/dns_records" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    --data "$(cat <<JSON
{
  "type": "CNAME",
  "name": "${SUBDOMAIN}",
  "content": "${TARGET}",
  "ttl": 1,
  "proxied": false,
  "comment": "AT Protocol handle for ${SUBDOMAIN}"
}
JSON
)")

success=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")

if [[ "$success" == "True" ]]; then
    info "CNAME record created successfully: ${SUBDOMAIN} → ${TARGET}"
else
    error "Failed to create CNAME record"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
    exit 1
fi
