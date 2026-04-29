"""Backward-compatible re-export from scripts.lib.atproto.assertions."""

import sys
from pathlib import Path

_scripts_dir = str(Path(__file__).resolve().parent.parent.parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from scripts.lib.atproto.assertions import assert_success, assert_contains, assert_status, assert_error  # noqa: F401
