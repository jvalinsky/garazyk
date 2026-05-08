#!/usr/bin/env bash
set -euo pipefail

root_dir="${1:-.}"
out_dir="${2:-/tmp/objc-rate-limiting-dos-audit}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required but not installed" >&2
  exit 1
fi

scan_path="$root_dir"
if [[ -d "$root_dir/Garazyk/Sources" ]]; then
  scan_path="$root_dir/Garazyk/Sources"
fi

mkdir -p "$out_dir"

unbounded_loop_hits="$out_dir/unbounded_loop_hits.txt"
unbounded_collection_hits="$out_dir/unbounded_collection_hits.txt"
memory_alloc_hits="$out_dir/memory_alloc_hits.txt"
websocket_hits="$out_dir/websocket_hits.txt"
http_handler_hits="$out_dir/http_handler_hits.txt"
ratelimit_hits="$out_dir/ratelimit_hits.txt"
file_size_hits="$out_dir/file_size_hits.txt"
nested_async_hits="$out_dir/nested_async_hits.txt"

rg -n --glob '*.{m,mm,h}' \
  -e 'while\s*\(\s*YES\s*\)' \
  -e 'for\s*\(\s*;;\s*\)' \
  -e 'while\s*\(\s*true\s*\)' \
  "$scan_path" >"$unbounded_loop_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e '\[NSMutableArray array\]' \
  -e '\[NSMutableSet set\]' \
  -e '\[NSMutableDictionary dictionary\]' \
  -e '\[NSMutableData data\]' \
  -e '\[NSMutableString string\]' \
  "$scan_path" >"$unbounded_collection_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'dataWithContentsOfFile' \
  -e 'dataWithContentsOfURL' \
  -e 'stringWithContentsOfFile' \
  -e 'initWithData:.*length' \
  -e 'malloc\s*\(' \
  -e 'calloc\s*\(' \
  -e 'realloc\s*\(' \
  "$scan_path" >"$memory_alloc_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'webSocket:didReceiveMessage' \
  -e 'webSocket:didOpen' \
  -e 'WebSocketConnection' \
  -e 'WebSocketServer' \
  "$scan_path" >"$websocket_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'handleRequest:' \
  -e 'HttpHandler' \
  -e 'XrpcHandler' \
  -e 'route:method:' \
  "$scan_path" >"$http_handler_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'RateLimiter' \
  -e 'rateLimit' \
  -e 'shouldRateLimit' \
  "$scan_path" >"$ratelimit_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'fileSize' \
  -e 'length\s*>\s*[0-9]+' \
  -e 'maxLength' \
  -e 'maxSize' \
  "$scan_path" >"$file_size_hits" || true

rg -n --glob '*.{m,mm,h}' \
  -e 'dispatch_async.*dispatch_async' \
  -e 'dispatch_sync.*dispatch_async' \
  "$scan_path" >"$nested_async_hits" || true

timeout_hits="$out_dir/timeout_hits.txt"
rg -n --glob '*.{m,mm,h}' \
  -e 'timeoutInterval' \
  -e 'timeout' \
  -e 'NSURLRequest.*timeout' \
  "$scan_path" >"$timeout_hits" || true

cut -d: -f1 "$http_handler_hits" | sort -u >"$out_dir/handler_files.txt"
cut -d: -f1 "$ratelimit_hits" | sort -u >"$out_dir/ratelimit_files.txt"

comm -23 "$out_dir/handler_files.txt" "$out_dir/ratelimit_files.txt" >"$out_dir/handlers_without_ratelimit.txt"

summary="$out_dir/summary.md"
{
  echo "# Objective-C Rate Limiting and DoS Scan"
  echo
  echo "- Root: $root_dir"
  echo "- Scan path: $scan_path"
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "## Counts"
  echo "- Unbounded loops: $(wc -l < "$unbounded_loop_hits" | tr -d ' ')"
  echo "- Unbounded collections: $(wc -l < "$unbounded_collection_hits" | tr -d ' ')"
  echo "- Memory allocation sites: $(wc -l < "$memory_alloc_hits" | tr -d ' ')"
  echo "- WebSocket handlers: $(wc -l < "$websocket_hits" | tr -d ' ')"
  echo "- HTTP handlers: $(wc -l < "$http_handler_hits" | tr -d ' ')"
  echo "- Rate limiting usage: $(wc -l < "$ratelimit_hits" | tr -d ' ')"
  echo "- File size checks: $(wc -l < "$file_size_hits" | tr -d ' ')"
  echo "- Timeout configurations: $(wc -l < "$timeout_hits" | tr -d ' ')"
  echo
  echo "## High priority (handlers without rate limiting)"
  if [[ -s "$out_dir/handlers_without_ratelimit.txt" ]]; then
    sed 's/^/- /' "$out_dir/handlers_without_ratelimit.txt"
  else
    echo "- none detected (all handlers have rate limiting references)"
  fi
  echo
  echo "## Detailed findings"
  echo
  echo "### Unbounded loops"
  if [[ -s "$unbounded_loop_hits" ]]; then
    head -10 "$unbounded_loop_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$unbounded_loop_hits") -gt 10 ]]; then
      echo "  ... and $(( $(wc -l < "$unbounded_loop_hits") - 10 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### Memory allocation without size limits"
  if [[ -s "$memory_alloc_hits" ]]; then
    head -15 "$memory_alloc_hits" | sed 's/^/  /'
    if [[ $(wc -l < "$memory_alloc_hits") -gt 15 ]]; then
      echo "  ... and $(( $(wc -l < "$memory_alloc_hits") - 15 )) more"
    fi
  else
    echo "  none"
  fi
  echo
  echo "### WebSocket entry points"
  if [[ -s "$websocket_hits" ]]; then
    head -10 "$websocket_hits" | sed 's/^/  /'
  else
    echo "  none"
  fi
  echo
  echo "## Notes"
  echo "- Unbounded loops need explicit break conditions."
  echo "- Handlers without rate limiting need manual review."
  echo "- Memory allocations need size validation for user input."
  echo "- WebSocket needs message size limits and backpressure."
} >"$summary"

echo "wrote $summary"
