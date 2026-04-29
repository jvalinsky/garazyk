"""Backward-compatible re-export from scripts.lib.atproto.client."""

import sys
from pathlib import Path

_scripts_dir = str(Path(__file__).resolve().parent.parent.parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from scripts.lib.atproto.client import XrpcClient, XrpcError, _safe_json  # noqa: F401
