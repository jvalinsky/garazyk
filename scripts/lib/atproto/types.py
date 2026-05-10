"""Typed dataclasses for common ATProto response shapes.

Domain sub-clients return raw dicts for flexibility. Callers that want
typed access can use the ``from_api()`` classmethods provided here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass(frozen=True)
class Session:
    """Authenticated session returned by createAccount / createSession."""
    did: str
    handle: str
    access_jwt: str
    refresh_jwt: str

    @classmethod
    def from_api(cls, data: dict[str, Any]) -> Session:
        return cls(
            did=data["did"],
            handle=data.get("handle", ""),
            access_jwt=data.get("accessJwt", ""),
            refresh_jwt=data.get("refreshJwt", ""),
        )


@dataclass(frozen=True)
class RecordRef:
    uri: str
    cid: str

    @classmethod
    def from_api(cls, data: dict[str, Any]) -> RecordRef:
        return cls(uri=data["uri"], cid=data.get("cid", ""))


@dataclass(frozen=True)
class Profile:
    did: str
    handle: str
    display_name: str
    description: str

    @classmethod
    def from_api(cls, data: dict[str, Any]) -> Profile:
        return cls(
            did=data.get("did", ""),
            handle=data.get("handle", ""),
            display_name=data.get("displayName", ""),
            description=data.get("description", ""),
        )
