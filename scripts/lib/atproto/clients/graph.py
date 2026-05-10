from __future__ import annotations

from typing import Optional

from ..transport import TransportLayer


class GraphClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def get_follows(self, actor: str, token: Optional[str] = None, limit: int = 50) -> dict:
        return self._t.get(
            "app.bsky.graph.getFollows", {"actor": actor, "limit": limit}, token=token
        )

    def get_followers(self, actor: str, token: Optional[str] = None, limit: int = 50) -> dict:
        return self._t.get(
            "app.bsky.graph.getFollowers", {"actor": actor, "limit": limit}, token=token
        )

    def get_blocks(self, token: str, limit: int = 50) -> dict:
        return self._t.get("app.bsky.graph.getBlocks", {"limit": limit}, token=token)

    def get_mutes(self, token: str, limit: int = 50) -> dict:
        return self._t.get("app.bsky.graph.getMutes", {"limit": limit}, token=token)

    def mute_actor(self, actor_did: str, token: str) -> dict:
        return self._t.post("app.bsky.graph.muteActor", {"actor": actor_did}, token=token)

    def unmute_actor(self, actor_did: str, token: str) -> dict:
        return self._t.post("app.bsky.graph.unmuteActor", {"actor": actor_did}, token=token)

    def get_relationships(
        self, actor: str, targets: list[str], token: Optional[str] = None
    ) -> dict:
        return self._t.get(
            "app.bsky.graph.getRelationships",
            {"actor": actor, "others": targets},
            token=token,
        )

    def get_starter_pack(self, uri: str, token: Optional[str] = None) -> dict:
        return self._t.get("app.bsky.graph.getStarterPack", {"uri": uri}, token=token)

    def get_actor_starter_packs(
        self, actor: str, token: Optional[str] = None, limit: int = 50
    ) -> dict:
        return self._t.get(
            "app.bsky.graph.getActorStarterPacks",
            {"actor": actor, "limit": limit},
            token=token,
        )

    def get_starter_packs(self, uris: list[str], token: Optional[str] = None) -> dict:
        return self._t.get(
            "app.bsky.graph.getStarterPacks",
            {"uris": ",".join(uris)},
            token=token,
        )
