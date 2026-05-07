"""Backward-compatible re-export from scripts.lib.atproto.characters."""

import sys
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto.characters import Character, CHARACTERS, get_character, get_characters_by_role, get_characters_by_pds, reset_characters, PDS1, PDS2  # noqa: F401
