#!/usr/bin/env bash
# stage-docker-binaries.sh — Build Linux ELF binaries inside Docker for local-network
#
# The local-network Dockerfile.local copies pre-built binaries from staging/bin/.
# These must be Linux ELF executables, not macOS Mach-O. This script builds the
# binaries inside a Docker container using the same Dockerfile.gnustep builder
# stage, then copies them to the staging directory.
#
# Usage:
#   ./stage-docker-binaries.sh           # Build all binaries
#   ./stage-docker-binaries.sh --check   # Verify staging binaries are Linux ELF
#
# Prerequisites:
#   - Docker
#   - git submodule update --init (secp256k1 must be checked out)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/..")"
STAGING_DIR="$REPO_ROOT/docker/local-network/staging"
DOCKERFILE="$REPO_ROOT/docker/Dockerfile.gnustep"
BUILDER_TARGET="builder"
IMAGE_TAG="garazyk-staging-builder:latest"

BINARIES=(kaszlak campagnola zuk syrena)
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK_ONLY=true ;;
        --help|-h)
            echo "Usage: $0 [--check]"
            echo ""
            echo "  --check    Verify staging binaries are Linux ELF (don't build)"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

# ── Check mode ──────────────────────────────────────────────────────────────
if [[ "$CHECK_ONLY" == "true" ]]; then
    ok=true
    for binary in "${BINARIES[@]}"; do
        path="$STAGING_DIR/bin/$binary"
        if [[ ! -f "$path" ]]; then
            echo "MISSING: $path"
            ok=false
        elif file "$path" | grep -q "ELF"; then
            echo "OK:     $path ($(file -b "$path"))"
        else
            echo "WRONG:  $path ($(file -b "$path")) — expected ELF"
            ok=false
        fi
    done
    if [[ "$ok" == "true" ]]; then
        echo "All staging binaries are Linux ELF."
        exit 0
    else
        echo "Some staging binaries are missing or wrong format. Run: $0"
        exit 1
    fi
fi

# ── Build mode ──────────────────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is required" >&2
    exit 3
fi

echo "[stage] Building Linux binaries inside Docker..."
echo "[stage] Using Dockerfile: $DOCKERFILE"

# Build the builder stage only (doesn't build the full runtime image)
docker build -f "$DOCKERFILE" --target "$BUILDER_TARGET" -t "$IMAGE_TAG" "$REPO_ROOT"

echo "[stage] Extracting binaries from Docker image..."

# Create a temporary container and copy binaries out
CONTAINER_ID=$(docker create "$IMAGE_TAG" /bin/true)

mkdir -p "$STAGING_DIR/bin"

for binary in "${BINARIES[@]}"; do
    echo "[stage] Copying $binary..."
    docker cp "$CONTAINER_ID:/src/build/bin/$binary" "$STAGING_DIR/bin/$binary"
    chmod +x "$STAGING_DIR/bin/$binary"
done

echo "[stage] Extracting libraries..."
mkdir -p "$STAGING_DIR/lib"
# Copy GNUstep and Dispatch libraries
docker cp "$CONTAINER_ID:/usr/GNUstep/Local/Library/Libraries/." "$STAGING_DIR/lib/"
docker cp "$CONTAINER_ID:/usr/GNUstep/Local/lib/." "$STAGING_DIR/lib/" || true

# Copy lexicons if not already present
if [[ ! -d "$STAGING_DIR/lexicons" ]]; then
    echo "[stage] Copying lexicons..."
    docker cp "$CONTAINER_ID:/src/Garazyk/Resources/lexicons" "$STAGING_DIR/lexicons"
fi

# Copy PLC assets if not already present
if [[ ! -d "$STAGING_DIR/PLC-assets" ]]; then
    echo "[stage] Copying PLC assets..."
    docker cp "$CONTAINER_ID:/src/Garazyk/Sources/PLC/Assets" "$STAGING_DIR/PLC-assets"
fi

# Copy Auth assets if not already present
if [[ ! -d "$STAGING_DIR/Auth-assets" ]]; then
    echo "[stage] Copying Auth assets..."
    docker cp "$CONTAINER_ID:/src/Garazyk/Sources/Auth/Assets" "$STAGING_DIR/Auth-assets"
fi

# Copy shared design system CSS if not already present
if [[ ! -d "$STAGING_DIR/css-shared" ]]; then
    echo "[stage] Copying shared design system CSS..."
    cp -r "$REPO_ROOT/Garazyk/Sources/Shared/DesignSystem/css" "$STAGING_DIR/css-shared"
fi

# Clean up the temporary container
docker rm "$CONTAINER_ID" >/dev/null

echo "[stage] Verifying binaries..."
for binary in "${BINARIES[@]}"; do
    path="$STAGING_DIR/bin/$binary"
    info="$(file -b "$path")"
    if echo "$info" | grep -q "ELF"; then
        echo "  OK:   $binary — $info"
    else
        echo "  FAIL: $binary — $info (expected ELF)"
        exit 1
    fi
done

echo "[stage] Done. Linux ELF binaries are in $STAGING_DIR/bin/"
