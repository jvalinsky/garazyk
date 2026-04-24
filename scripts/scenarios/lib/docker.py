"""Network management helpers for ATProto scenario scripts.

Manages the local-network environment, supporting both Docker Compose
and local binary processes.
"""

from __future__ import annotations

import logging
import subprocess
import time
import os
from typing import Optional

logger = logging.getLogger("atproto.scenario")

COMPOSE_FILE = "docker/local-network/docker-compose.yml"
COMPOSE_OVERRIDE = "docker/local-network/docker-compose.scenarios.yml"

# Service → (container_name, health_url_template)
SERVICES = {
    "plc": ("local-plc", "http://localhost:{port}/_health"),
    "pds": ("local-pds", "http://localhost:{port}/xrpc/com.atproto.server.describeServer"),
    "relay": ("local-relay", "http://localhost:{port}/api/relay/health"),
    "appview": ("local-appview", "http://localhost:{port}/admin/backfill/status"),
    "pds2": ("local-pds2", "http://localhost:{port}/xrpc/com.atproto.server.describeServer"),
}

SERVICE_PORTS = {
    "plc": 2582,
    "pds": 2583,
    "relay": 2584,
    "appview": 3200,
    "pds2": 2585,
}

def _find_repo_root() -> str:
    """Find the repository root directory."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

def start_local_network(with_pds2: bool = False, use_binary: bool = False) -> None:
    """Start the local-network environment."""
    repo_root = _find_repo_root()
    setup_script = os.path.join(repo_root, "scripts/scenarios/setup_local_network.sh")

    if use_binary:
        logger.info("Starting local network via binaries (with_pds2=%s)...", with_pds2)
        cmd = [setup_script, "--binary"]
        if with_pds2:
            cmd.append("--pds2")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Binary setup failed: {result.stderr}")
    else:
        logger.info("Starting local network via Docker (with_pds2=%s)...", with_pds2)
        cmd = [setup_script]
        if with_pds2:
            cmd.append("--pds2")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Docker setup failed: {result.stderr}")

    # The shell script already waits, but we verify here too
    services_to_wait = ["plc", "pds", "relay", "appview"]
    if with_pds2:
        services_to_wait.append("pds2")

    for service in services_to_wait:
        port = SERVICE_PORTS[service]
        health_url = SERVICES[service][1].format(port=port)
        headers = {}
        if service == "appview":
            headers["Authorization"] = "Bearer localdevadmin"
        _wait_for_healthy_url(health_url, service, headers=headers, timeout=30)

    logger.info("Local network is healthy!")

def stop_local_network(use_binary: bool = False) -> None:
    """Stop the local-network environment."""
    repo_root = _find_repo_root()
    setup_script = os.path.join(repo_root, "scripts/scenarios/setup_local_network.sh")

    logger.info("Stopping local network (binary=%s)...", use_binary)
    cmd = [setup_script, "--teardown"]
    if use_binary:
        cmd.append("--binary")
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.warning("Teardown had issues: %s", result.stderr)
    else:
        logger.info("Local network stopped.")

def get_service_url(service: str) -> str:
    """Get the HTTP URL for a service."""
    port = SERVICE_PORTS[service]
    return f"http://localhost:{port}"

def _wait_for_healthy_url(url: str, service_name: str, headers: dict = None, timeout: int = 120) -> None:
    """Poll a health URL until it returns 200 or timeout."""
    import requests

    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            resp = requests.get(url, headers=headers, timeout=2)
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
