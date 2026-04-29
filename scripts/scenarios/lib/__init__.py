"""ATProto scenario simulation shared library.

Re-exports from scripts.lib.atproto for backward compatibility.
Existing scenario scripts that import from scenarios.lib continue to work.
"""

import sys
from pathlib import Path

# Add scripts/ to sys.path so scripts.lib.atproto is importable
_scripts_dir = str(Path(__file__).resolve().parent.parent.parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from scripts.lib.atproto import (
    XrpcClient,
    XrpcError,
    Character,
    CHARACTERS,
    get_character,
    get_characters_by_role,
    assert_success,
    assert_contains,
    assert_status,
    assert_error,
    ScenarioResult,
    StepResult,
    StepStatus,
)

__all__ = [
    "XrpcClient",
    "XrpcError",
    "Character",
    "CHARACTERS",
    "get_character",
    "get_characters_by_role",
    "assert_success",
    "assert_contains",
    "assert_status",
    "assert_error",
    "ScenarioResult",
    "StepResult",
    "StepStatus",
]
