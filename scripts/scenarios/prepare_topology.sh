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
SOURCES_JSON=""
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
        --sources-json)
            [[ $# -ge 2 ]] || { echo "Error: --sources-json requires a value" >&2; exit 2; }
            SOURCES_JSON="$2"
            shift
            ;;
        --repo-root)
            [[ $# -ge 2 ]] || { echo "Error: --repo-root requires a value" >&2; exit 2; }
            REPO_ROOT="$2"
            shift
            ;;
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            echo "Usage: $0 --preset <name> --run-dir <dir> [--repo-root <dir>] [--sources-json <path>] [--verbose]"
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
SOURCES_JSON="${SOURCES_JSON:-$RUN_DIR/topology_sources.json}"

if [[ ! -f "$SOURCES_JSON" ]]; then
    log_info "Compiling topology preset: $PRESET"
    deno run -A "$SCRIPT_DIR/compile_topology.ts" \
        --preset "$PRESET" \
        --output "$RUN_DIR/docker-compose.topology.yml" \
        --run-dir "$RUN_DIR" \
        --repo-root "$REPO_ROOT" \
        --sources-json "$SOURCES_JSON"
fi

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

CACHE_ROOT="$REPO_ROOT/docker/local-network/sources_cache"
mkdir -p "$CACHE_ROOT"

log_info "Preparing $SOURCE_COUNT source build(s) for preset: $PRESET"

for i in $(seq 0 $((SOURCE_COUNT - 1))); do
    NAME=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['name'])")
    REPO=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['repo'])")
    REF=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['ref'])")
    CLONE_DIR=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i]['cloneDir'])")

    DOCKERFILE_OVERLAY=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i].get('dockerfileOverlay', ''))")
    OVERLAY_DIR=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i].get('overlayDir', ''))")

    if [[ -z "$NAME" || -z "$REPO" || -z "$REF" ]]; then
        log_warn "Skipping source entry $i: missing name, repo, or ref"
        continue
    fi

    CACHE_DIR="$CACHE_ROOT/$NAME"

    # 1. Ensure CACHE_DIR has a valid clone
    if [[ ! -d "$CACHE_DIR/.git" ]]; then
        log_info "Source $NAME: initializing cache at $CACHE_DIR"
        rm -rf "$CACHE_DIR"
        mkdir -p "$CACHE_DIR"
        if [[ "$VERBOSE" == "true" ]]; then
            git clone "$REPO" "$CACHE_DIR"
        else
            git clone --quiet "$REPO" "$CACHE_DIR"
        fi
    else
        # Proactively fetch to ensure we have the requested ref
        if [[ "$VERBOSE" == "true" ]]; then
            git -C "$CACHE_DIR" fetch --tags origin
        else
            git -C "$CACHE_DIR" fetch --quiet --tags origin
        fi
    fi

    # 2. Sync CACHE_DIR to match requested REF
    log_info "Source $NAME: checking out $REF in cache"
    git -C "$CACHE_DIR" checkout --quiet "$REF"

    # 3. Fast local copy from cache to CLONE_DIR (per-run directory)
    log_info "Source $NAME: populating $CLONE_DIR from cache"
    mkdir -p "$(dirname "$CLONE_DIR")"
    rm -rf "$CLONE_DIR"
    
    # Use cp -a for fast local copy
    cp -a "$CACHE_DIR" "$CLONE_DIR"

    # Copy overlay Dockerfile from Garazyk repo into the cloned source
    if [[ -n "$DOCKERFILE_OVERLAY" ]]; then
        OVERLAY_SRC="$REPO_ROOT/$DOCKERFILE_OVERLAY"
        if [[ -f "$OVERLAY_SRC" ]]; then
            DOCKERFILE_NAME=$(python3 -c "import json; print(json.load(open('$SOURCES_JSON'))[$i].get('dockerfile', 'Dockerfile'))")
            cp "$OVERLAY_SRC" "$CLONE_DIR/$DOCKERFILE_NAME"
            log_ok "Source $NAME: copied Dockerfile overlay $OVERLAY_SRC -> $CLONE_DIR/$DOCKERFILE_NAME"
        else
            log_warn "Source $NAME: dockerfileOverlay '$DOCKERFILE_OVERLAY' not found at $OVERLAY_SRC, skipping"
        fi
    fi

    # Copy overlay directory from Garazyk repo into the cloned source.
    # The directory's contents are merged into the clone root (existing files overwritten).
    if [[ -n "$OVERLAY_DIR" ]]; then
        OVERLAY_DIR_SRC="$REPO_ROOT/$OVERLAY_DIR"
        if [[ -d "$OVERLAY_DIR_SRC" ]]; then
            # Copy directory contents (not the directory itself) into the clone
            # using tar to preserve permissions and avoid cp -r edge cases
            (cd "$OVERLAY_DIR_SRC" && tar cf - .) | (cd "$CLONE_DIR" && tar xf -)
            log_ok "Source $NAME: copied overlay dir $OVERLAY_DIR_SRC -> $CLONE_DIR"
        else
            log_warn "Source $NAME: overlayDir '$OVERLAY_DIR' not found at $OVERLAY_DIR_SRC, skipping"
        fi
    fi
done

log_ok "All source builds prepared for preset: $PRESET"
