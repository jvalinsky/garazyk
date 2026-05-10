"""Backward-compatible re-export from scripts.lib.atproto.config."""
import sys
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto.config import (  # noqa: F401
    SERVICE_URLS,
    APPVIEW_ADMIN_SECRET,
    PDS_ADMIN_PASSWORD,
)
