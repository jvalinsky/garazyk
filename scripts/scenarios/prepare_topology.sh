#!/usr/bin/env bash
# prepare_topology.sh — Clone source repos for topology adapters that use source builds.
#
# Reads the topology compiler's output and clones each source repo at the pinned
# ref into <run-dir>/sources/<name>. If a clone already exists and the ref matches,
# it is reused (no re-clone). If the ref differs, the directory is removed and
# re-cloned.
#
# Usage:
#   ./scripts/scenarios/prepare_topology.sh \
#     --preset parakeet \
#     --run-dir /tmp/garazyk-e2e-xxx \
#     --repo-root /path/to/garazyk
#
# This script is called by setup_local_network.sh when --topology is used.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

REPO_ROOT="$(resolve_project_root "$SCRIPT_DIR")"

PRESET=""
RUN_DIR=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)
            [[ $# -ge 2 ]] || { echo "Error: --preset requires a value" >&2; exit 2; }
            PRESET="$2"
            shift
            ;;
        --run-dir)
            [[ $# -ge 2 ]] || { echo "Error: --run-dir requires a value" >&2; exit 2; }
            RUN_DIR="$2"
            shift
            ;;
        --repo-root)
            [[ $# -ge 2 ]] || { echo "Error: --repo-root requires a value" >&2; exit 2; }
            REPO_ROOT="$2"
            shift
            ;;
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            echo "Usage: $0 --preset <name> --run-dir <dir> [--repo-root <dir>] [--verbose]"
            echo ""
            echo "  Clone source repos for topology adapters that use source builds."
            echo ""
            echo "  --preset NAME       Topology preset name (required)"
            echo "  --run-dir DIR       Run directory for cloned sources (required)"
            echo "  --repo-root DIR     Repository root (default: auto-detect)"
            echo "  --verbose           Show detailed clone output"
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -z "$PRESET" ]]; then
    echo "Error: --preset is required" >&2
    exit 2
fi
if [[ -z "$RUN_DIR" ]]; then
    echo "Error: --run-dir is required" >&2
    exit 2
fi

# Compile the topology to get the source list
SOURCES_DIR="$RUN_DIR/sources"
SOURCES_JSON="$RUN_DIR/topology_sources.json"

log_info "Compiling topology preset: $PRESET"
deno run -A "$SCRIPT_DIR/compile_topology.ts" \
    --preset "$PRESET" \
    --output "$RUN_DIR/docker-compose.topology.yml" \
    --run-dir "$RUN_DIR" \
    --repo-root "$REPO_ROOT" \
    --sources-json "$SOURCES_JSON"

if [[ ! -f "$SOURCES_JSON" ]]; then
    log_info "No source builds required for preset: $PRESET"
    exit 0
fi

# Read source entries and clone each one
# The JSON file is an array of objects:
# [{ name, repo, ref, dockerDir, dockerfile, buildArgs, cloneDir }, ...]
SOURCE_COUNT=$(python3 -c "import json; print(len(json.load(open('$SOURCES_JSON'))))" 2>/dev/null || echo "0")

if [[ "$SOURCE_COUNT" -eq 0 ]]; then
    log_info "No source builds required for preset: $PRESET"
    exit 0
fi

log_info "Preparing $SOURCE_COUNT source build(s) for preset: $PRESET"

for i in $(seq 0 $((SOURCE_COUNT - 1))); do
    NAME=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['name'])")
    REPO=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['repo'])")
    REF=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['ref'])")
    CLONE_DIR=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['cloneDir'])")

    if [[ -z "$NAME" || -z "$REPO" || -z "$REF" ]]; then
        log_warn "Skipping source entry $i: missing name, repo, or ref"
        continue
    fi

    # Check if the clone already exists with the correct ref
    if [[ -d "$CLONE_DIR/.git" ]]; then
        CURRENT_REF=$(git -C "$CLONE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        CURRENT_TAG=$(git -C "$CLONE_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)
        if [[ "$CURRENT_REF" == "$REF" || "$CURRENT_TAG" == "$REF" ]]; then
            log_ok "Source $NAME: already cloned at $REF, reusing"
            continue
        fi
        # Ref mismatch — remove and re-clone
        log_info "Source $NAME: ref changed ($CURRENT_REF/$CURRENT_TAG -> $REF), re-cloning"
        rm -rf "$CLONE_DIR"
    fi

    log_info "Source $NAME: cloning $REPO at $REF"
    mkdir -p "$(dirname "$CLONE_DIR")"

    # Determine if ref is a branch/tag (shallow clone) or a commit SHA (full clone + checkout)
    if [[ "$REF" =~ ^[0-9a-f]{7,40}$ ]]; then
        # Commit SHA — need full clone
        if [[ "$VERBOSE" == "true" ]]; then
            git clone "$REPO" "$CLONE_DIR"
        else
            git clone --quiet "$REPO" "$CLONE_DIR"
        fi
        git -C "$CLONE_DIR" checkout "$REF"
    else
        # Branch or tag — shallow clone
        if [[ "$VERBOSE" == "true" ]]; then
            git clone --depth 1 --branch "$REF" "$REPO" "$CLONE_DIR"
        else
            git clone --quiet --depth 1 --branch "$REF" "$REPO" "$CLONE_DIR"
        fi
    fi

    log_ok "Source $NAME: cloned at $REF -> $CLONE_DIR"
done

log_ok "All source builds prepared for preset: $PRESET"
