"""Character definitions for ATProto scenario simulations.

Each character has a name, handle, email, password, persona description,
role (user, admin, mod), and the PDS URL they belong to.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Character:
    """A simulated user in the ATProto scenario suite."""

    name: str
    handle: str
    email: str
    password: str
    persona: str
    role: str  # "user", "admin", "mod"
    pds_url: str = "http://localhost:2583"

    # Populated at runtime after account creation
    did: Optional[str] = None
    access_jwt: Optional[str] = None
    refresh_jwt: Optional[str] = None

    @property
    def token(self) -> Optional[str]:
        return self.access_jwt

    def __repr__(self) -> str:
        return f"Character({self.name!r}, {self.handle!r}, did={self.did!r})"


# ── PDS 1: "The Neighborhood" ──────────────────────────────────────

PDS1 = "http://localhost:2583"
PDS2 = "http://localhost:2585"

CHARACTERS: dict[str, Character] = {
    "luna": Character(
        name="Luna Starfield",
        handle="luna.test",
        email="luna@test.com",
        password="luna_pass_123",
        persona="Astronomy enthusiast, posts about space, follows science accounts, friendly",
        role="user",
        pds_url=PDS1,
    ),
    "marcus": Character(
        name="Marcus Code",
        handle="marcus.test",
        email="marcus@test.com",
        password="marcus_pass_123",
        persona="Developer, posts about ATProto, builds tools, helpful",
        role="user",
        pds_url=PDS1,
    ),
    "rosa": Character(
        name="Chef Rosa",
        handle="rosa.test",
        email="rosa@test.com",
        password="rosa_pass_123",
        persona="Food blogger, posts recipes, uploads food photos, social butterfly",
        role="user",
        pds_url=PDS1,
    ),
    "volt": Character(
        name="DJ Volt",
        handle="volt.test",
        email="volt@test.com",
        password="volt_pass_123",
        persona="Music producer, posts about beats and shows, energetic",
        role="user",
        pds_url=PDS1,
    ),
    "troll": Character(
        name="Trollface McGee",
        handle="troll.test",
        email="troll@test.com",
        password="troll_pass_123",
        persona="Bad actor, posts spam and harassment, gets reported",
        role="user",
        pds_url=PDS1,
    ),
    "quiet": Character(
        name="Quiet Observer",
        handle="quiet.test",
        email="quiet@test.com",
        password="quiet_pass_123",
        persona="Lurker, reads feeds, few posts, follows many",
        role="user",
        pds_url=PDS1,
    ),
    "admin": Character(
        name="Admin Sentinel",
        handle="admin.test",
        email="admin@test.com",
        password="admin_pass_123",
        persona="Server administrator, handles reports and takedowns, posts announcements",
        role="admin",
        pds_url=PDS1,
    ),
    "mod": Character(
        name="Mod Justice",
        handle="mod.test",
        email="mod@test.com",
        password="mod_pass_123",
        persona="Ozone moderator, reviews reports, applies labels, uses tools.ozone",
        role="mod",
        pds_url=PDS1,
    ),
    # ── PDS 2: "The Other Side" ────────────────────────────────────
    "nova": Character(
        name="Nova Bright",
        handle="nova.second.test",
        email="nova@second.test",
        password="nova_pass_123",
        persona="Cross-PDS user, interacts with PDS 1 users, tests federation",
        role="user",
        pds_url=PDS2,
    ),
    "rex": Character(
        name="Rex Storm",
        handle="rex.second.test",
        email="rex@second.test",
        password="rex_pass_123",
        persona="Cross-PDS troll, gets into conflicts across PDS boundaries",
        role="user",
        pds_url=PDS2,
    ),
}


def get_character(name: str) -> Character:
    """Look up a character by key. Raises KeyError if not found."""
    return CHARACTERS[name]


def get_characters_by_role(role: str) -> list[Character]:
    """Return all characters with the given role."""
    return [c for c in CHARACTERS.values() if c.role == role]


def get_characters_by_pds(pds_url: str) -> list[Character]:
    """Return all characters on a given PDS."""
    return [c for c in CHARACTERS.values() if c.pds_url == pds_url]
