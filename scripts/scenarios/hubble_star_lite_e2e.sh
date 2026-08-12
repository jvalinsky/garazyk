#!/usr/bin/env bash
# hubble_star_lite_e2e.sh — end-to-end check of STAR-lite v0 interop with Hubble.
#
# Brings up the hubble-star-lite topology (Garazyk PLC + PDS, plus Hubble
# built from source and patched to run against a local, non-TLS, non-
# production-PLC network -- see docker/hubble/), seeds a few accounts,
# and verifies Hubble backfills them via application/x.microcosm.star-lite.
#
# Usage:
#   ./scripts/scenarios/hubble_star_lite_e2e.sh                # setup, test, teardown
#   ./scripts/scenarios/hubble_star_lite_e2e.sh --keep-running  # leave services up after
#   ./scripts/scenarios/hubble_star_lite_e2e.sh --no-setup      # test against already-running services
#
# The first run builds the Hubble image from source (nightly Rust + rocksdb),
# which takes several minutes. Subsequent runs reuse Docker's layer cache.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KEEP_RUNNING=false
NO_SETUP=false
RUN_ID="hubble-star-lite-$(date +%s)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-running) KEEP_RUNNING=true ;;
        --no-setup) NO_SETUP=true ;;
        --run-id)
            [[ $# -ge 2 ]] || { echo "Error: --run-id requires a value" >&2; exit 2; }
            RUN_ID="$2"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--keep-running] [--no-setup] [--run-id ID]"
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

cd "$REPO_ROOT"

if [[ "$NO_SETUP" != "true" ]]; then
    RUN_DIR="${ATPROTO_E2E_BASE_DIR:-/tmp/garazyk-atproto-e2e}/$RUN_ID"

    # setup_local_network.sh (packages/hamownia/atproto_network.ts) compiles the
    # topology's compose file but does not clone source-build roles' repos --
    # that's prepare_topology.sh's job, and it isn't called automatically. Run
    # it first so the Hubble build context exists before `docker compose up`.
    echo "==> Preparing source builds for hubble-star-lite (run-dir: $RUN_DIR)"
    ./scripts/scenarios/prepare_topology.sh \
        --preset hubble-star-lite \
        --run-dir "$RUN_DIR" \
        --repo-root "$REPO_ROOT"

    echo "==> Bringing up hubble-star-lite topology (run-id: $RUN_ID)"
    ./scripts/scenarios/setup_local_network.sh \
        --topology hubble-star-lite \
        --run-id "$RUN_ID" \
        --keep-running
fi

echo "==> Running smoke test"
SMOKE_EXIT=0
deno run -A ./scripts/scenarios/hubble_star_lite_smoke.ts || SMOKE_EXIT=$?

if [[ "$KEEP_RUNNING" != "true" && "$NO_SETUP" != "true" ]]; then
    echo "==> Tearing down (run-id: $RUN_ID)"
    ./scripts/scenarios/teardown_local_network.sh --run-id "$RUN_ID"
fi

exit "$SMOKE_EXIT"
