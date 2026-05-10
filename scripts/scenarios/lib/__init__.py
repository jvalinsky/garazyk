"""ATProto scenario simulation shared library.

Re-exports from scripts.lib.atproto for backward compatibility.
Existing scenario scripts that import from scenarios.lib continue to work.
"""

import sys
from pathlib import Path

# Add project root to sys.path so scripts.lib.atproto is importable
# __init__.py -> lib/ -> scenarios/ -> scripts/ -> project_root
_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient,
    XrpcError,
    Character,
    CHARACTERS,
    get_character,
    get_characters_by_role,
    get_characters_by_pds,
    reset_characters,
    assert_success,
    assert_contains,
    assert_status,
    assert_error,
    ScenarioResult,
    StepResult,
    StepStatus,
    timed_call,
)

# Re-export PDS URL constants for scenario convenience
from scripts.lib.atproto.characters import PDS1, PDS2  # noqa: F401

# Re-export service config for admin scenarios
from scripts.lib.atproto.config import (  # noqa: F401
    SERVICE_URLS,
    APPVIEW_ADMIN_SECRET,
    PDS_ADMIN_PASSWORD,
)

__all__ = [
    "XrpcClient",
    "XrpcError",
    "Character",
    "CHARACTERS",
    "get_character",
    "get_characters_by_role",
    "get_characters_by_pds",
    "reset_characters",
    "PDS1",
    "PDS2",
    "assert_success",
    "assert_contains",
    "assert_status",
    "assert_error",
    "ScenarioResult",
    "StepResult",
    "StepStatus",
    "timed_call",
    "SERVICE_URLS",
    "APPVIEW_ADMIN_SECRET",
    "PDS_ADMIN_PASSWORD",
]
