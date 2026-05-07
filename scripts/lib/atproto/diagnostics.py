"""Shared run context and diagnostics for ATProto e2e scripts.

The scenario runner and Python launchers use the same run-directory layout as
the Bash helpers in ``scripts/lib/common.sh``:

    /tmp/garazyk-atproto-e2e/<run-id>/
      logs/
      reports/
      diagnostics/

Diagnostics are intentionally file-based so shell, Python, Docker, and local
binary runs can all leave useful evidence without requiring a service to stay
alive after a failing test.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping

import requests

from .config import SERVICE_URLS, find_project_root


_BASE_DIR = Path("/tmp/garazyk-atproto-e2e")
_SECRET_PATTERNS = [
    re.compile(r"(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/=-]+", re.IGNORECASE),
    re.compile(
        r'("(?:accessJwt|refreshJwt|token|password|secret|masterSecret|adminPassword)"\s*:\s*")[^"]+"',
        re.IGNORECASE,
    ),
    re.compile(r"((?:JWT|TOKEN|PASSWORD|SECRET|MASTER_SECRET|ADMIN_SECRET)=)\S+"),
]


@dataclass(frozen=True)
class E2ERunContext:
    """Resolved filesystem locations for one e2e run."""

    run_id: str
    run_dir: Path
    logs_dir: Path
    reports_dir: Path
    diagnostics_dir: Path
    pid_file: Path
    compose_project: str


def sanitize_run_id(value: str) -> str:
    """Return a compose/filesystem-safe run id."""
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", value.strip()).strip("-").lower()
    return cleaned or default_run_id()


def default_run_id() -> str:
    """Return a unique default run id."""
    return f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-{os.getpid()}"


def create_run_context(
    run_id: str | None = None,
    diagnostics_dir: str | Path | None = None,
    run_dir: str | Path | None = None,
) -> E2ERunContext:
    """Create and export the shared run-directory context."""
    resolved_run_id = sanitize_run_id(
        run_id or os.environ.get("ATPROTO_E2E_RUN_ID", "") or default_run_id()
    )
    base_dir = Path(os.environ.get("ATPROTO_E2E_BASE_DIR", str(_BASE_DIR)))
    resolved_run_dir = Path(
        run_dir or os.environ.get("ATPROTO_E2E_RUN_DIR", base_dir / resolved_run_id)
    )
    resolved_logs_dir = Path(os.environ.get("ATPROTO_E2E_LOG_DIR", resolved_run_dir / "logs"))
    resolved_reports_dir = Path(
        os.environ.get("ATPROTO_E2E_REPORTS_DIR", resolved_run_dir / "reports")
    )
    resolved_diag_dir = Path(
        diagnostics_dir
        or os.environ.get("ATPROTO_E2E_DIAGNOSTICS_DIR", resolved_run_dir / "diagnostics")
    )
    resolved_pid_file = Path(
        os.environ.get("ATPROTO_E2E_PID_FILE", resolved_run_dir / "pids.txt")
    )
    compose_run_id = re.sub(r"[^a-z0-9-]+", "-", resolved_run_id.replace(".", "-").replace("_", "-"))
    compose_project = os.environ.get(
        "ATPROTO_E2E_COMPOSE_PROJECT", f"garazyk-e2e-{compose_run_id}"
    )

    for path in (resolved_run_dir, resolved_logs_dir, resolved_reports_dir, resolved_diag_dir):
        path.mkdir(parents=True, exist_ok=True)

    os.environ["ATPROTO_E2E_RUN_ID"] = resolved_run_id
    os.environ["ATPROTO_E2E_RUN_DIR"] = str(resolved_run_dir)
    os.environ["ATPROTO_E2E_LOG_DIR"] = str(resolved_logs_dir)
    os.environ["ATPROTO_E2E_REPORTS_DIR"] = str(resolved_reports_dir)
    os.environ["ATPROTO_E2E_DIAGNOSTICS_DIR"] = str(resolved_diag_dir)
    os.environ["ATPROTO_E2E_PID_FILE"] = str(resolved_pid_file)
    os.environ["ATPROTO_E2E_COMPOSE_PROJECT"] = compose_project

    return E2ERunContext(
        run_id=resolved_run_id,
        run_dir=resolved_run_dir,
        logs_dir=resolved_logs_dir,
        reports_dir=resolved_reports_dir,
        diagnostics_dir=resolved_diag_dir,
        pid_file=resolved_pid_file,
        compose_project=compose_project,
    )


def redact(value: str) -> str:
    """Redact common token/password shapes from diagnostic summaries."""
    redacted = value
    for pattern in _SECRET_PATTERNS:
        if "accessJwt" in pattern.pattern:
            redacted = pattern.sub(r'\1[REDACTED]"', redacted)
        else:
            redacted = pattern.sub(r"\1[REDACTED]", redacted)
    return redacted


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(redact(text), encoding="utf-8")


def collect_http_endpoint(
    output_dir: Path,
    name: str,
    url: str,
    headers: Mapping[str, str] | None = None,
    timeout: int = 8,
) -> None:
    """Capture one HTTP endpoint into a redacted diagnostic file."""
    target = output_dir / "http" / f"{name}.txt"
    try:
        resp = requests.get(url, headers=dict(headers or {}), timeout=timeout)
        body = resp.text[:50_000]
        text = (
            f"url={url}\n"
            f"http_status={resp.status_code}\n"
            f"content_type={resp.headers.get('Content-Type', '')}\n\n"
            f"{body}\n"
        )
    except requests.RequestException as exc:
        text = f"url={url}\nerror={exc}\n"
    write_text(target, text)


def collect_diagnostics(
    context: E2ERunContext,
    *,
    service_urls: Mapping[str, str] | None = None,
    appview_admin_secret: str | None = None,
    compose_dir: str | Path | None = None,
    compose_files: Iterable[str | Path] = (),
    compose_project: str | None = None,
    label: str = "atproto-e2e",
) -> Path:
    """Collect service health, logs, compose state, and run metadata."""
    output_dir = context.diagnostics_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    urls = dict(service_urls or SERVICE_URLS)
    appview_secret = appview_admin_secret or os.environ.get(
        "APPVIEW_ADMIN_SECRET", "localdevadmin"
    )

    metadata = {
        "label": label,
        "run_id": context.run_id,
        "run_dir": str(context.run_dir),
        "diagnostics_dir": str(output_dir),
        "compose_project": compose_project or context.compose_project,
        "created_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "service_urls": urls,
    }
    try:
        root = find_project_root()
        metadata["repo_root"] = str(root)
        metadata["git_commit"] = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip()
        metadata["git_status"] = subprocess.run(
            ["git", "-C", str(root), "status", "--short"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.splitlines()
    except Exception as exc:  # pragma: no cover - diagnostic best effort
        metadata["git_error"] = str(exc)

    write_text(output_dir / "run-metadata.json", json.dumps(metadata, indent=2))

    if context.pid_file.exists():
        shutil.copy2(context.pid_file, output_dir / "pids.txt")
    if context.logs_dir.exists():
        logs_out = output_dir / "service-logs"
        logs_out.mkdir(exist_ok=True)
        for log_path in context.logs_dir.glob("*.log"):
            shutil.copy2(log_path, logs_out / log_path.name)

    collect_http_endpoint(output_dir, "plc-health", f"{urls.get('plc', '')}/_health")
    collect_http_endpoint(
        output_dir,
        "pds-describe-server",
        f"{urls.get('pds', '')}/xrpc/com.atproto.server.describeServer",
    )
    collect_http_endpoint(output_dir, "relay-health", f"{urls.get('relay', '')}/api/relay/health")
    collect_http_endpoint(
        output_dir, "relay-upstreams", f"{urls.get('relay', '')}/api/relay/upstreams"
    )
    collect_http_endpoint(
        output_dir,
        "appview-backfill-status",
        f"{urls.get('appview', '')}/admin/backfill/status",
        headers={"Authorization": f"Bearer {appview_secret}"},
    )
    collect_http_endpoint(
        output_dir,
        "pds2-describe-server",
        f"{urls.get('chat', '')}/xrpc/com.atproto.server.describeServer",
    )
    collect_http_endpoint(output_dir, "chat-health", f"{urls.get('chat', '')}/_health")
    collect_http_endpoint(output_dir, "video-health", f"{urls.get('video', '')}/_health")
    collect_http_endpoint(output_dir, "ui-admin", f"{urls.get('ui', '')}/admin")

    compose_paths = [Path(path) for path in compose_files]
    if compose_dir and compose_paths and shutil.which("docker"):
        docker_out = output_dir / "docker"
        docker_out.mkdir(exist_ok=True)
        cmd_base = ["docker", "compose"]
        project = compose_project or context.compose_project
        if project:
            cmd_base.extend(["-p", project])
        for path in compose_paths:
            cmd_base.extend(["-f", str(path)])
        for name, args in {
            "ps": ["ps", "--all"],
            "config": ["config"],
            "logs": ["logs", "--no-color", "--timestamps", "--tail=300"],
        }.items():
            result = subprocess.run(
                cmd_base + args,
                cwd=str(compose_dir),
                capture_output=True,
                text=True,
                check=False,
            )
            write_text(docker_out / f"{name}.txt", result.stdout + result.stderr)

    return output_dir
