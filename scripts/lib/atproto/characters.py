"""Character definitions for ATProto scenario simulations.

Each character has a name, handle, email, password, persona description,
role (user, admin, mod), and the PDS URL they belong to.

Handles are made unique per process run by appending a short run ID
(e.g. "luna-a3f2.test") to avoid collisions when re-running scenarios
against the same PDS instance.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Character:
    """A simulated account used by the scenario suite.

    Static fields describe the actor's intended role and persona. Runtime
    fields are populated after account creation so later scenario steps can use
    the same object for DID lookup and authenticated requests.
    """

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


# ── Run ID: short hex suffix for unique handles per process ────────

_RUN_ID: str = os.environ.get(
    "ATPROTO_SCENARIO_RUN_ID",
    format(int(time.time() * 100) % 0xFFFF, "04x"),
)


def _unique_handle(base_handle: str) -> str:
    """Append the run ID before the TLD to make handles unique per run.

    E.g. "luna.test" -> "luna-a3f2.test"
         "nova.second.test" -> "nova-a3f2.second.test"
    """
    parts = base_handle.rsplit(".", 1)
    if len(parts) == 2:
        return f"{parts[0]}-{_RUN_ID}.{parts[1]}"
    return f"{base_handle}-{_RUN_ID}"


def _unique_email(base_email: str) -> str:
    """Append the run ID to the local part of the email.

    E.g. "luna@test.com" -> "luna-a3f2@test.com"
    """
    local, domain = base_email.split("@", 1)
    return f"{local}-{_RUN_ID}@{domain}"


# ── PDS endpoints ──────────────────────────────────────────────────

PDS1 = "http://localhost:2583"
PDS2 = "http://localhost:2585"

# ── Base character templates (before unique suffixes) ──────────────

_BASE_CHARACTERS: dict[str, dict] = {
    "luna": dict(
        name="Luna Starfield",
        handle="luna.test",
        email="luna@test.com",
        password="luna_pass_123",
        persona="Astronomy enthusiast, posts about space, follows science accounts, friendly",
        role="user",
        pds_url=PDS1,
    ),
    "marcus": dict(
        name="Marcus Code",
        handle="marcus.test",
        email="marcus@test.com",
        password="marcus_pass_123",
        persona="Developer, posts about ATProto, builds tools, helpful",
        role="user",
        pds_url=PDS1,
    ),
    "rosa": dict(
        name="Chef Rosa",
        handle="rosa.test",
        email="rosa@test.com",
        password="rosa_pass_123",
        persona="Food blogger, posts recipes, uploads food photos, social butterfly",
        role="user",
        pds_url=PDS1,
    ),
    "volt": dict(
        name="DJ Volt",
        handle="volt.test",
        email="volt@test.com",
        password="volt_pass_123",
        persona="Music producer, posts about beats and shows, energetic",
        role="user",
        pds_url=PDS1,
    ),
    "troll": dict(
        name="Trollface McGee",
        handle="troll.test",
        email="troll@test.com",
        password="troll_pass_123",
        persona="Bad actor, posts spam and harassment, gets reported",
        role="user",
        pds_url=PDS1,
    ),
    "quiet": dict(
        name="Quiet Observer",
        handle="quiet.test",
        email="quiet@test.com",
        password="quiet_pass_123",
        persona="Lurker, reads feeds, few posts, follows many",
        role="user",
        pds_url=PDS1,
    ),
    "admin": dict(
        name="Admin Sentinel",
        handle="admin.test",
        email="admin@test.com",
        password="admin_pass_123",
        persona="Server administrator, handles reports and takedowns, posts announcements",
        role="admin",
        pds_url=PDS1,
    ),
    "mod": dict(
        name="Mod Justice",
        handle="mod.test",
        email="mod@test.com",
        password="mod_pass_123",
        persona="Ozone moderator, reviews reports, applies labels, uses tools.ozone",
        role="mod",
        pds_url=PDS1,
    ),
    # ── PDS 2: "The Other Side" ────────────────────────────────────
    "nova": dict(
        name="Nova Bright",
        handle="nova.second.test",
        email="nova@second.test",
        password="nova_pass_123",
        persona="Cross-PDS user, interacts with PDS 1 users, tests federation",
        role="user",
        pds_url=PDS2,
    ),
    "rex": dict(
        name="Rex Storm",
        handle="rex.second.test",
        email="rex@second.test",
        password="rex_pass_123",
        persona="Cross-PDS troll, gets into conflicts across PDS boundaries",
        role="user",
        pds_url=PDS2,
    ),
}


def _build_characters() -> dict[str, Character]:
    """Build the character registry with unique handles and emails.

    A fresh suffix is generated for each rebuild so multiple scenarios running
    in the same Python process do not collide with accounts created by earlier
    scenarios.
    """
    # Use a per-call unique suffix to avoid collisions between scenarios in same process.
    suffix = format(int(time.time() * 1000) % 0xFFFF, "04x")
    chars: dict[str, Character] = {}
    for key, tpl in _BASE_CHARACTERS.items():
        base_handle = tpl["handle"]
        parts = base_handle.rsplit(".", 1)
        handle = f"{parts[0]}-{suffix}.{parts[1]}" if len(parts) == 2 else f"{base_handle}-{suffix}"

        base_email = tpl["email"]
        e_parts = base_email.split("@", 1)
        email = f"{e_parts[0]}-{suffix}@{e_parts[1]}"

        chars[key] = Character(
            name=tpl["name"],
            handle=handle,
            email=email,
            password=tpl["password"],
            persona=tpl["persona"],
            role=tpl["role"],
            pds_url=tpl["pds_url"],
        )
    return chars


# ── Public character registry (refreshed per module reload) ──────────

CHARACTERS: dict[str, Character] = _build_characters()


def reset_characters() -> None:
    """Refresh the module-level character registry with new unique handles."""
    global CHARACTERS
    CHARACTERS = _build_characters()


def get_character(name: str) -> Character:
    """Look up a character by registry key.

    Raises KeyError for unknown names so scenario setup fails fast when a step
    references a fixture that is not defined.
    """
    return CHARACTERS[name]


def get_characters_by_role(role: str) -> list[Character]:
    """Return all characters assigned to the given scenario role."""
    return [c for c in CHARACTERS.values() if c.role == role]


def get_characters_by_pds(pds_url: str) -> list[Character]:
    """Return all characters whose accounts should be created on a PDS URL."""
    return [c for c in CHARACTERS.values() if c.pds_url == pds_url]
