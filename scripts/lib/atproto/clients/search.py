from __future__ import annotations

from typing import Optional

from ..transport import TransportLayer


class SearchClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def search_actors_typeahead(
        self, query: str, token: Optional[str] = None, limit: int = 10
    ) -> dict:
        return self._t.get(
            "app.bsky.actor.searchActorsTypeahead",
            {"q": query, "limit": limit},
            token=token,
        )

    def get_suggestions(self, token: str, limit: int = 25) -> dict:
        return self._t.get(
            "app.bsky.actor.getSuggestions", {"limit": limit}, token=token
        )

    def search_actors_skeleton(
        self, query: str, token: Optional[str] = None, limit: int = 25
    ) -> dict:
        return self._t.get(
            "app.bsky.unspecced.searchActorsSkeleton",
            {"q": query, "limit": limit},
            token=token,
        )

    def search_posts_skeleton(
        self, query: str, token: Optional[str] = None, limit: int = 25
    ) -> dict:
        return self._t.get(
            "app.bsky.unspecced.searchPostsSkeleton",
            {"q": query, "limit": limit},
            token=token,
        )

    def search_starter_packs_skeleton(
        self, query: str, token: Optional[str] = None, limit: int = 25
    ) -> dict:
        return self._t.get(
            "app.bsky.unspecced.searchStarterPacksSkeleton",
            {"q": query, "limit": limit},
            token=token,
        )

    def get_preferences(self, token: str) -> dict:
        return self._t.get("app.bsky.actor.getPreferences", token=token)

    def put_preferences(self, preferences: list, token: str) -> dict:
        return self._t.post(
            "app.bsky.actor.putPreferences",
            {"preferences": preferences},
            token=token,
        )
