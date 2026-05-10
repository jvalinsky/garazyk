"""Domain-specific XRPC sub-clients.

Each file wraps a group of related ATProto methods. All sub-clients
receive a ``TransportLayer`` instance and delegate wire-protocol work to it.
"""

from .accounts import AccountsClient
from .identity import IdentityClient
from .records import RecordsClient
from .blobs import BlobsClient
from .graph import GraphClient
from .feed import FeedClient
from .notifications import NotificationsClient
from .drafts import DraftsClient
from .search import SearchClient
from .contact import ContactClient
from .age_assurance import AgeAssuranceClient
from .admin import AdminClient
from .raw import RawClient

__all__ = [
    "AccountsClient",
    "IdentityClient",
    "RecordsClient",
    "BlobsClient",
    "GraphClient",
    "FeedClient",
    "NotificationsClient",
    "DraftsClient",
    "SearchClient",
    "ContactClient",
    "AgeAssuranceClient",
    "AdminClient",
    "RawClient",
]
