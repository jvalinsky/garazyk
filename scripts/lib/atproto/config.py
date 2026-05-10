"""Service configuration for Garazyk ATProto scripts.

This module is the Python companion to scripts/lib/common.sh. It centralizes
the default local ports, service URLs, binary names, shared secrets, and seed
fixtures used by Python scenario runners. Environment variables are read at
import time so each script gets a stable view of its execution environment.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any


# ── Project paths ──────────────────────────────────────────────────────────

def find_project_root() -> Path:
    """Return the repository root directory.

    git is preferred because scenario scripts are often launched from nested
    directories. The fallback walks up from this package, which keeps the
    helpers usable in source archives or test sandboxes without .git metadata.
    """
    try:
        import subprocess
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path(__file__).resolve().parent.parent.parent.parent


def find_build_dir() -> Path:
    """Return the directory that should contain local service binaries.

    BUILD_DIR lets callers point at an out-of-source CMake/Xcode build without
    changing every script that starts services.
    """
    root = find_project_root()
    return Path(os.environ.get("BUILD_DIR", str(root / "build" / "bin")))


# ── Service ports ──────────────────────────────────────────────────────────

SERVICE_PORTS: dict[str, int] = {
    "plc": int(os.environ.get("PLC_PORT", "2582")),
    "pds": int(os.environ.get("PDS_PORT", "2583")),
    "relay": int(os.environ.get("RELAY_PORT", "2584")),
    "appview": int(os.environ.get("APPVIEW_PORT", "3200")),
    "chat": int(os.environ.get("CHAT_PORT", "2585")),
    "video": int(os.environ.get("VIDEO_PORT", "2586")),
    "ui": int(os.environ.get("UI_PORT", "2590")),
}

SERVICE_BINARIES: dict[str, str] = {
    "plc": "campagnola",
    "pds": "kaszlak",
    "relay": "zuk",
    "appview": "syrena",
    "chat": "syrena-chat",
    "video": "jelcz",
    "ui": "garazyk-ui",
}

SERVICE_HEALTH_PATHS: dict[str, str] = {
    "plc": "/_health",
    "pds": "/xrpc/com.atproto.server.describeServer",
    "relay": "/api/relay/health",
    "appview": "/admin/backfill/status",
    "chat": "/_health",
    "video": "/_health",
    "ui": "/admin",
}


SERVICE_URLS: dict[str, str] = {
    key: f"http://127.0.0.1:{port}" for key, port in SERVICE_PORTS.items()
}


def service_url(key: str) -> str:
    """Return the HTTP base URL for a known service key."""
    return SERVICE_URLS[key]


def service_health_url(key: str) -> str:
    """Return the service-specific readiness URL for a known service key."""
    base = service_url(key)
    path = SERVICE_HEALTH_PATHS.get(key, "/_health")
    return f"{base}{path}"


# ── Secrets ─────────────────────────────────────────────────────────────────

PDS_ADMIN_PASSWORD = os.environ.get("PDS_ADMIN_PASSWORD", "admin-localdev")
PDS_MASTER_SECRET = os.environ.get("PDS_MASTER_SECRET", "test-master-secret-123")
APPVIEW_ADMIN_SECRET = os.environ.get("APPVIEW_ADMIN_SECRET", "localdevadmin")
UI_ADMIN_PASSWORD = os.environ.get("UI_ADMIN_PASSWORD", "localdev")


# ── Default seed data ──────────────────────────────────────────────────────

DEFAULT_ACCOUNTS: list[dict[str, str]] = [
    {"handle": "alice.test", "email": "alice@test.local", "password": "alicepass"},
    {"handle": "bob.test", "email": "bob@test.local", "password": "bobpass"},
    {"handle": "carol.test", "email": "carol@test.local", "password": "carolpass"},
]

DEFAULT_POSTS_TEMPLATES: list[str] = [
    "Hello from {handle}! Excited to be on the ATProto network!",
    "Just set up my PDS instance. Decentralization rocks!",
    "Working on some cool features today. #atproto #coding",
    "Beautiful day to build something new!",
    "The future of social is decentralized. Here we go!",
    "Just learned about MST (Merkle Search Tree) -- fascinating tech!",
    "Shoutout to the Bluesky team for the protocol design!",
    "Testing out the firehose relay functionality today.",
    "Record indexing is working great with the new backfill logic.",
    "Admin UI makes managing the PDS so much easier!",
]
