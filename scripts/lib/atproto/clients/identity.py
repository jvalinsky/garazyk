from __future__ import annotations

from typing import Optional

from ..transport import TransportLayer


class IdentityClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def resolve_handle(self, handle: str) -> dict:
        return self._t.get("com.atproto.identity.resolveHandle", {"handle": handle})

    def update_handle(self, handle: str, token: str) -> dict:
        return self._t.post("com.atproto.identity.updateHandle", {"handle": handle}, token=token)
