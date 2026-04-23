#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-secrets-detection-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/ATProtoPDS/Sources" ]]; then
  scan_path="$root_dir/ATProtoPDS/Sources"
fi

mkdir -p "$out_dir"

password_hits="$out_dir/password_hits.txt"
apikey_hits="$out_dir/apikey_hits.txt"
secret_hits="$out_dir/secret_hits.txt"
token_hits="$out_dir/token_hits.txt"
privatekey_hits="$out_dir/privatekey_hits.txt"
base64_hits="$out_dir/base64_hits.txt"
connection_hits="$out_dir/connection_hits.txt"
env_file_hits="$out_dir/env_file_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'password\s*=\s*@"[^"]{4,}"' \
  -e 'password\s*:\s*@"[^"]{4,}"' \
  "$scan_path" >"$password_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'api[_-]?key\s*=\s*@"[^"]{8,}"' \
  -e 'apiKey\s*=\s*@"[^"]{8,}"' \
  -e 'api_key\s*:\s*@"[^"]{8,}"' \
  "$scan_path" >"$apikey_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'secret\s*=\s*@"[^"]{8,}"' \
  -e 'secret\s*:\s*@"[^"]{8,}"' \
  -e 'client_secret\s*=\s*@"[^"]{8,}"' \
  "$scan_path" >"$secret_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'token\s*=\s*@"[^"]{16,}"' \
  -e 'access_token\s*=\s*@"[^"]{16,}"' \
  -e 'refresh_token\s*=\s*@"[^"]{16,}"' \
  -e 'auth_token\s*=\s*@"[^"]{16,}"' \
  "$scan_path" >"$token_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'private[_-]?key\s*=\s*@"[^"]{20,}"' \
  -e 'privateKey\s*=\s*@"[^"]{20,}"' \
  -e '-----BEGIN.*PRIVATE KEY-----' \
  "$scan_path" >"$privatekey_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '[A-Za-z0-9+/]{40,}={0,2}' \
  "$scan_path" | grep -v '^[^:]*:.*//.*base64' | grep -v 'test' >"$base64_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '(mysql|postgres|mongodb|redis|amqp)://[^@]+:[^@]+@' \
  "$scan_path" >"$connection_hits" || true

rg -n --glob '.env*' \
  -e '[A-Z_]+\s*=\s*[A-Za-z0-9]{16,}' \
  "$root_dir" >"$env_file_hits" || true

cat "$password_hits" "$apikey_hits" "$secret_hits" "$token_hits" "$privatekey_hits" "$connection_hits" \
  | cut -d: -f1 | sort -u >"$out_dir/files_with_secrets.txt" || true

summary="$out_dir/summary.md"
{
  echo "# Objective-C Secrets Detection Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Password assignments: $(wc -l < "$password_hits" | tr -d ' ')"
  echo "- API key assignments: $(wc -l < "$apikey_hits" | tr -d ' ')"
  echo "- Secret assignments: $(wc -l < "$secret_hits" | tr -d ' ')"
  echo "- Token assignments: $(wc -l < "$token_hits" | tr -d ' ')"
  echo "- Private key references: $(wc -l < "$privatekey_hits" | tr -d ' ')"
  echo "- Connection strings: $(wc -l < "$connection_hits" | tr -d ' ')"
  echo "- .env file matches: $(wc -l < "$env_file_hits" | tr -d ' ')"
  echo
  echo "## Files with potential secrets"
  if [[ -s "$out_dir/files_with_secrets.txt" ]]; then
    sed 's/^/- /' "$out_dir/files_with_secrets.txt"
  else
    echo "- none detected"
  fi
  echo
  echo "## Detailed findings"
  echo
  echo "### Password assignments"
  if [[ -s "$password_hits" ]]; then
    head -20 "$password_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$password_hits") -gt 20 ]]; then
      echo "  ... and $(( $(wc -l < "$password_hits") - 20 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### API key assignments"
  if [[ -s "$apikey_hits" ]]; then
    head -20 "$apikey_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$apikey_hits") -gt 20 ]]; then
      echo "  ... and $(( $(wc -l < "$apikey_hits") - 20 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### Private key references"
  if [[ -s "$privatekey_hits" ]]; then
    head -20 "$privatekey_hits" | sed 's/^/  /'
  else
    echo "  none"
  fi
  echo
  echo "## Notes"
  echo "- These are pattern-based heuristics; manual review required."
  echo "- Check context to determine if test fixtures or production secrets."
  echo "- Verify secrets are not committed to version control history."
  echo "- Run \`gitleaks\` or \`trufflehog\` for git history scanning."
} >"$summary"

echo "wrote $summary"
