"""Backward-compatible re-export from scripts.lib.atproto.assertions."""

import sys
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto.assertions import (  # noqa: F401
    assert_success,
    assert_contains,
    assert_status,
    assert_error,
    assert_xrpc_raises,
)
