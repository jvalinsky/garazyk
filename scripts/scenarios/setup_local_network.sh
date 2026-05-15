#!/usr/bin/env bash
# setup_local_network.sh — Thin wrapper around the Deno-native local network manager.
#
# All logic has been moved to scripts/manage_local_network.ts which uses
# the Docker Engine API client for container discovery, event-driven health
# checks, and native fetch() instead of curl/polling. This script exists
# for backward compatibility with direct CLI usage.
#
# Usage:
#   ./setup_local_network.sh              # Start PLC + PDS + Relay + AppView (Docker)
#   ./setup_local_network.sh --binary     # Start from build/bin/ (no Docker)
#   ./setup_local_network.sh --pds2       # Also start second PDS for federation
#   ./setup_local_network.sh --wait-only  # Just wait for healthy, don't start
#   ./setup_local_network.sh --teardown   # Stop all services
#   ./setup_local_network.sh --otel      # Enable OpenTelemetry (SigNoz on port 3301)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"

exec deno run -A "$REPO_ROOT/scripts/manage_local_network.ts" "$@"
