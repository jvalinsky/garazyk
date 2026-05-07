"""Network management helpers for ATProto scenario scripts.

Scenario tests can run against either Docker Compose services or binaries from
the local build directory. This module delegates startup/teardown to the shell
script that owns the environment details, then performs Python-side health
verification before scenarios begin.
"""

from __future__ import annotations

import os
import logging
import subprocess
import time
from pathlib import Path

from .diagnostics import E2ERunContext, create_run_context

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
    """Return the repository root used to locate scenario shell scripts."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

def _append_context_args(cmd: list[str], context: E2ERunContext | None) -> None:
    if context is None:
        return
    cmd.extend(["--run-id", context.run_id])
    cmd.extend(["--diagnostics-dir", str(context.diagnostics_dir)])


def start_local_network(
    with_pds2: bool = False,
    use_binary: bool = False,
    *,
    context: E2ERunContext | None = None,
) -> None:
    """Start the local network and wait for required services to be healthy.

    with_pds2 enables the federation topology. use_binary selects local
    binaries instead of Docker Compose, which is useful when testing uncommitted
    service changes.
    """
    if context is None:
        context = create_run_context()
    repo_root = _find_repo_root()
    setup_script = os.path.join(repo_root, "scripts/scenarios/setup_local_network.sh")

    if use_binary:
        logger.info("Starting local network via binaries (with_pds2=%s)...", with_pds2)
        cmd = [setup_script, "--binary"]
        if with_pds2:
            cmd.append("--pds2")
        _append_context_args(cmd, context)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Binary setup failed: {result.stderr}")
    else:
        logger.info("Starting local network via Docker (with_pds2=%s)...", with_pds2)
        cmd = [setup_script]
        if with_pds2:
            cmd.append("--pds2")
        _append_context_args(cmd, context)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Docker setup failed: {result.stderr}")

    logger.info("Local network is healthy. Run directory: %s", context.run_dir)

def stop_local_network(
    use_binary: bool = False,
    *,
    context: E2ERunContext | None = None,
    collect_diagnostics: bool = False,
) -> None:
    """Stop the local-network environment started by start_local_network."""
    if context is None:
        context = create_run_context()
    repo_root = _find_repo_root()
    setup_script = os.path.join(repo_root, "scripts/scenarios/setup_local_network.sh")

    logger.info("Stopping local network (binary=%s)...", use_binary)
    cmd = [setup_script, "--teardown"]
    if use_binary:
        cmd.append("--binary")
    if collect_diagnostics:
        cmd.append("--collect-diagnostics")
    _append_context_args(cmd, context)

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.warning("Teardown had issues: %s", result.stderr)
    else:
        logger.info("Local network stopped.")


def collect_local_network_diagnostics(
    *,
    use_binary: bool = False,
    context: E2ERunContext | None = None,
) -> Path:
    """Ask the shell harness to collect local-network diagnostics."""
    if context is None:
        context = create_run_context()
    repo_root = _find_repo_root()
    setup_script = os.path.join(repo_root, "scripts/scenarios/setup_local_network.sh")
    cmd = [setup_script, "--collect-diagnostics"]
    if use_binary:
        cmd.append("--binary")
    _append_context_args(cmd, context)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        logger.warning("Diagnostic collection had issues: %s", result.stderr)
    return context.diagnostics_dir

def get_service_url(service: str) -> str:
    """Return the default localhost URL for a named scenario service."""
    port = SERVICE_PORTS[service]
    return f"http://localhost:{port}"

def _wait_for_healthy_url(url: str, service_name: str, headers: dict = None, timeout: int = 120) -> None:
    """Poll a health URL until it returns HTTP 200 or timeout expires."""
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
    """Return the relay health endpoint payload."""
    import requests
    resp = requests.get("http://localhost:2584/api/relay/health", timeout=5)
    return resp.json()

def check_appview_status() -> dict:
    """Return the AppView admin backfill-status payload."""
    import requests
    resp = requests.get(
        "http://localhost:3200/admin/backfill/status",
        headers={"Authorization": "Bearer localdevadmin"},
        timeout=5,
    )
    return resp.json()
