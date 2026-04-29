"""Backward-compatible re-export from scripts.lib.atproto.characters."""

import sys
from pathlib import Path

_scripts_dir = str(Path(__file__).resolve().parent.parent.parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from scripts.lib.atproto.characters import Character, CHARACTERS, get_character, get_characters_by_role  # noqa: F401
