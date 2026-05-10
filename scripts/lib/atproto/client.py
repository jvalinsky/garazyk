"""XRPC/HTTP client facade for Garazyk scenario and seed scripts.

The ``XrpcClient`` composes domain-specific sub-clients and exposes them as
named attributes. Each sub-client wraps a group of related ATProto methods
and delegates HTTP transport to ``TransportLayer``.

Example:
    client = XrpcClient("http://localhost:2583")
    session = client.accounts.create_account("alice.test", "alice@test.com", "password123")
    client.records.create_record(
        session["did"],
        "app.bsky.feed.post",
        {"$type": "app.bsky.feed.post", "text": "hello"},
        session["accessJwt"],
    )
"""

from __future__ import annotations

from .transport import TransportLayer, XrpcError
from .clients import (
    AccountsClient,
    IdentityClient,
    RecordsClient,
    BlobsClient,
    GraphClient,
    FeedClient,
    NotificationsClient,
    DraftsClient,
    SearchClient,
    ContactClient,
    AgeAssuranceClient,
    AdminClient,
    RawClient,
)

__all__ = ["XrpcClient", "XrpcError"]


class XrpcClient:
    """Facade over domain-specific ATProto sub-clients.

    Attributes:
        accounts: Account & session management.
        identity: Handle resolution and updates.
        records: Repo record CRUD and batch writes.
        blobs: Blob uploads.
        graph: Follows, followers, blocks, mutes, relationships, starter packs.
        feed: Timeline, author feed, likes, reposts, feed generators.
        notifications: Notification listing, push registration, preferences.
        drafts: Draft post CRUD.
        search: Actor typeahead, skeleton searches, preferences.
        contact: Phone verification, contact import/sync.
        age_assurance: Age verification flow.
        admin: Subject status, reports, labels.
        raw: Non-XRPC HTTP admin routes.
    """

    def __init__(self, base_url: str = "http://localhost:2583"):
        t = TransportLayer(base_url)
        self.accounts = AccountsClient(t)
        self.identity = IdentityClient(t)
        self.records = RecordsClient(t)
        self.blobs = BlobsClient(t)
        self.graph = GraphClient(t)
        self.feed = FeedClient(t)
        self.notifications = NotificationsClient(t)
        self.drafts = DraftsClient(t)
        self.search = SearchClient(t)
        self.contact = ContactClient(t)
        self.age_assurance = AgeAssuranceClient(t)
        self.admin = AdminClient(t)
        self.raw = RawClient(t)
        self._transport = t

    @property
    def last_responses(self):
        return self._transport.last_responses

    @property
    def last_response(self):
        return self._transport.last_response

    def health_check(self) -> bool:
        return self._transport.health_check()

    def wait_for_healthy(self, timeout: int = 30) -> None:
        return self._transport.wait_for_healthy(timeout)
