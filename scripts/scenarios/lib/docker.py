"""Docker Compose helpers for ATProto scenario scripts.

Manages the local-network Docker environment: starting/stopping services,
waiting for health checks, and retrieving service URLs.
"""

from __future__ import annotations

import logging
import subprocess
import time
from typing import Optional

logger = logging.getLogger("atproto.scenario")

COMPOSE_FILE = "docker/local-network/docker-compose.yml"
COMPOSE_OVERRIDE = "docker/local-network/docker-compose.scenarios.yml"

# Service → (container_name, health_url_template)
SERVICES = {
    "plc": ("local-plc", "http://localhost:{port}/_health"),
    "pds": ("local-pds", "http://localhost:{port}/xrpc/com.atproto.server.describeServer"),
    "relay": ("local-relay", "http://localhost:{port}/api/relay/health"),
    "appview": ("local-appview", "http://localhost:{port}/_health"),
    "pds2": ("local-pds2", "http://localhost:{port}/xrpc/com.atproto.server.describeServer"),
}

SERVICE_PORTS = {
    "plc": 2582,
    "pds": 2583,
    "relay": 2584,
    "appview": 3200,
    "pds2": 2585,
}


def _run_compose(*args: str, with_override: bool = False) -> subprocess.CompletedProcess:
    """Run a docker compose command."""
    repo_root = _find_repo_root()
    cmd = ["docker", "compose"]
    cmd.extend(["-f", os.path.join(repo_root, COMPOSE_FILE)])
    if with_override and os.path.exists(os.path.join(repo_root, COMPOSE_OVERRIDE)):
        cmd.extend(["-f", os.path.join(repo_root, COMPOSE_OVERRIDE)])
    cmd.extend(args)
    logger.debug("Running: %s", " ".join(cmd))
    return subprocess.run(cmd, capture_output=True, text=True, cwd=repo_root)


def _find_repo_root() -> str:
    """Find the repository root directory."""
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True,
    )
    if result.returncode == 0:
        return result.stdout.strip()
    # Fallback: relative to this file
    import os
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


import os  # noqa: E402 — needed above in _find_repo_root fallback


def start_local_network(with_pds2: bool = False) -> None:
    """Start the local-network Docker environment and wait for healthy."""
    logger.info("Starting local network (with_pds2=%s)...", with_pds2)
    result = _run_compose("up", "-d", with_override=with_pds2)
    if result.returncode != 0:
        raise RuntimeError(f"docker compose up failed: {result.stderr}")

    # Wait for each service
    services_to_wait = ["plc", "pds", "relay", "appview"]
    if with_pds2:
        services_to_wait.append("pds2")

    for service in services_to_wait:
        port = SERVICE_PORTS[service]
        health_url = SERVICES[service][1].format(port=port)
        _wait_for_healthy_url(health_url, service, timeout=120)

    logger.info("Local network is healthy!")


def stop_local_network(wipe_volumes: bool = False) -> None:
    """Stop the local-network Docker environment."""
    logger.info("Stopping local network (wipe_volumes=%s)...", wipe_volumes)
    args = ["down"]
    if wipe_volumes:
        args.append("-v")
    result = _run_compose(*args)
    if result.returncode != 0:
        logger.warning("docker compose down had issues: %s", result.stderr)
    else:
        logger.info("Local network stopped.")


def get_service_url(service: str) -> str:
    """Get the HTTP URL for a service."""
    port = SERVICE_PORTS[service]
    return f"http://localhost:{port}"


def _wait_for_healthy_url(url: str, service_name: str, timeout: int = 120) -> None:
    """Poll a health URL until it returns 200 or timeout."""
    import requests

    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            resp = requests.get(url, timeout=2)
            if resp.status_code == 200:
                logger.info("  %s is healthy", service_name)
                return
            last_error = f"HTTP {resp.status_code}"
        except requests.RequestException as exc:
            last_error = str(exc)
        time.sleep(2)

    raise RuntimeError(
        f"Service {service_name} not healthy at {url} after {timeout}s (last: {last_error})"
    )


def check_relay_health() -> dict:
    """Check relay health endpoint."""
    import requests

    resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
    return resp.json()


def check_appview_status() -> dict:
    """Check AppView backfill status."""
    import requests

    resp = requests.get(
        "http://localhost:3200/admin/backfill/status",
        headers={"Authorization": "Bearer localdevadmin"},
        timeout=5,
    )
    return resp.json()
