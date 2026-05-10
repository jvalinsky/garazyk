"""Backward-compatible re-export from scripts.lib.atproto.config."""

import sys
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto.config import (  # noqa: F401
    SERVICE_PORTS,
    SERVICE_URLS,
    SERVICE_BINARIES,
    SERVICE_HEALTH_PATHS,
    service_url,
    service_health_url,
    find_project_root,
    find_build_dir,
    PDS_ADMIN_PASSWORD,
    PDS_MASTER_SECRET,
    APPVIEW_ADMIN_SECRET,
    UI_ADMIN_PASSWORD,
    DEFAULT_ACCOUNTS,
    DEFAULT_POSTS_TEMPLATES,
)
