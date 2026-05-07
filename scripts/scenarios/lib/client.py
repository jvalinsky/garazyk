"""Backward-compatible re-export from scripts.lib.atproto.client."""

import sys
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto.client import XrpcClient, XrpcError, _safe_json  # noqa: F401
