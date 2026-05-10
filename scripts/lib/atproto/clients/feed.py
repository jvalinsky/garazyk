from __future__ import annotations

from typing import Optional

from ..transport import TransportLayer


class FeedClient:
    def __init__(self, transport: TransportLayer):
        self._t = transport

    def get_profile(self, actor: str, token: Optional[str] = None) -> dict:
        return self._t.get("app.bsky.actor.getProfile", {"actor": actor}, token=token)

    def get_timeline(self, token: str, limit: int = 50) -> dict:
        return self._t.get("app.bsky.feed.getTimeline", {"limit": limit}, token=token)

    def get_author_feed(self, actor: str, token: Optional[str] = None, limit: int = 50) -> dict:
        return self._t.get(
            "app.bsky.feed.getAuthorFeed", {"actor": actor, "limit": limit}, token=token
        )

    def get_post_thread(self, uri: str, token: Optional[str] = None) -> dict:
        return self._t.get("app.bsky.feed.getPostThread", {"uri": uri}, token=token)

    def get_likes(self, uri: str, token: Optional[str] = None, limit: int = 50) -> dict:
        return self._t.get("app.bsky.feed.getLikes", {"uri": uri, "limit": limit}, token=token)

    def search_actors(self, query: str, token: Optional[str] = None, limit: int = 10) -> dict:
        return self._t.get(
            "app.bsky.actor.searchActors", {"q": query, "limit": limit}, token=token
        )

    def get_actor_likes(
        self, actor: str, token: Optional[str] = None, limit: int = 50
    ) -> dict:
        return self._t.get(
            "app.bsky.feed.getActorLikes", {"actor": actor, "limit": limit}, token=token
        )

    def get_posts(self, uris: list[str], token: Optional[str] = None) -> dict:
        return self._t.get(
            "app.bsky.feed.getPosts", {"uris": ",".join(uris)}, token=token
        )

    def get_reposted_by(
        self, uri: str, token: Optional[str] = None, limit: int = 50
    ) -> dict:
        return self._t.get(
            "app.bsky.feed.getRepostedBy", {"uri": uri, "limit": limit}, token=token
        )

    def get_feed(self, feed_uri: str, token: str, limit: int = 50) -> dict:
        return self._t.get(
            "app.bsky.feed.getFeed", {"feed": feed_uri, "limit": limit}, token=token
        )

    def get_feed_generators(self, uris: list[str], token: Optional[str] = None) -> dict:
        return self._t.get(
            "app.bsky.feed.getFeedGenerators", {"uris": ",".join(uris)}, token=token
        )
