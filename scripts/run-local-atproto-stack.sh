#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$REPO_ROOT/docker/local-network"
IMAGE_NAME="nspds:local"

cleanup() {
    echo "==> Stopping services..."
    (cd "$DOCKER_DIR" && docker compose down --remove-orphans 2>/dev/null || true)
}

setup() {
    echo "==> Checking prerequisites..."
    command -v docker >/dev/null 2>&1 || { echo "Error: docker required" >&2; exit 1; }
    command -v docker compose >/dev/null 2>&1 || { echo "Error: docker compose required" >&2; exit 1; }

    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "==> Building Docker image ($IMAGE_NAME)..."
        docker build -t "$IMAGE_NAME" -f "$REPO_ROOT/docker/Dockerfile.gnustep" --target runtime "$REPO_ROOT"
    fi
}

start_services() {
    echo "==> Starting ATProto stack..."
    cd "$DOCKER_DIR"
    docker compose up -d

    echo "==> Waiting for services to be healthy..."
    local max_attempts=30
    local attempt=0

    for svc in local-plc local-pds local-relay local-appview; do
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if docker compose ps "$svc" | grep -q "(healthy)"; then
                echo "  ✓ $svc is healthy"
                break
            fi
            attempt=$((attempt + 1))
            sleep 2
        done
        if [ $attempt -eq $max_attempts ]; then
            echo "Error: $svc failed to become healthy" >&2
            docker compose logs --tail=20 "$svc"
            exit 1
        fi
    done
}

status() {
    cd "$DOCKER_DIR"
    echo ""
    echo "==> ATProto Stack Status"
    echo "========================"
    docker compose ps
    echo ""
    echo "Services:"
    echo "  PLC     http://localhost:2582  (campagnola)"
    echo "  PDS    http://localhost:2583  (kaszlak)"
    echo "  Relay  http://localhost:2584  (zuk)"
    echo "  AppView http://localhost:3200 (syrena)"
    echo ""
    echo "Admin endpoints:"
    echo "  curl -H 'Authorization: Bearer localdevadmin' http://localhost:3200/admin/backfill/status"
}

logs() {
    cd "$DOCKER_DIR"
    docker compose logs -f "$@"
}

case "${1:-start}" in
    start)
        trap cleanup EXIT
        setup
        start_services
        status
        ;;
    stop)
        cleanup
        ;;
    restart)
        trap cleanup EXIT
        cleanup
        setup
        start_services
        status
        ;;
    status)
        status
        ;;
    logs)
        shift
        logs "$@"
        ;;
    build)
        setup
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|build}" >&2
        exit 1
        ;;
esac