"""XRPC/HTTP client for Garazyk scenario and seed scripts.

The helpers in this module intentionally stay close to the wire protocol:
methods are named after ATProto XRPC procedures and queries, return decoded
response dictionaries, and raise XrpcError with the original response payload
when a call fails. Scenario scripts can then report protocol-level failures
without losing status codes or server error bodies.

The shared requests.Session keeps cookies and connections local to a client
instance. GET and JSON POST calls retry transient transport and 5xx failures;
client-side validation errors are surfaced immediately.
"""

from __future__ import annotations

import json
import logging
import time
from typing import Any, Optional

import requests

logger = logging.getLogger("atproto.scenario")

# Default timeouts
_REQUEST_TIMEOUT = 20
_RETRY_ATTEMPTS = 3
_RETRY_BACKOFF = 1.0


class XrpcError(Exception):
    """Raised when an XRPC or adjacent admin call fails.

    Attributes:
        method: XRPC method id or HTTP path used for the request.
        status: HTTP status code; 0 means the request did not reach a server.
        body: Decoded JSON error body when available, otherwise response text.
    """

    def __init__(self, method: str, status: int, body: dict | str):
        self.method = method
        self.status = status
        self.body = body
        super().__init__(f"XRPC {method} failed ({status}): {body}")


class XrpcClient:
    """Convenience client for local PDS, AppView, Relay, and chat endpoints.

    The client wraps common XRPC methods used by scenario scripts while keeping
    response shapes unchanged. Callers should pass accessJwt or admin tokens
    explicitly; the client does not manage token refresh automatically.

    Example:
        client = XrpcClient("http://localhost:2583")
        session = client.create_account("alice.test", "alice@test.com", "password123")
        client.create_record(
            session["did"],
            "app.bsky.feed.post",
            {"$type": "app.bsky.feed.post", "text": "hello"},
            session["accessJwt"],
        )
    """

    def __init__(self, base_url: str = "http://localhost:2583"):
        self.base_url = base_url.rstrip("/")
        self._session = requests.Session()

    # ── Low-level XRPC ──────────────────────────────────────────────

    def xrpc_get(
        self,
        method: str,
        params: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        """Issue an XRPC query and return its decoded JSON response.

        Retries transport errors and 5xx responses using linear backoff. Any
        non-5xx response is treated as a deterministic protocol or validation
        failure and is raised immediately as XrpcError.
        """
        url = f"{self.base_url}/xrpc/{method}"
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        last_error = None
        for attempt in range(1, _RETRY_ATTEMPTS + 1):
            try:
                resp = self._session.get(
                    url, params=params, headers=headers, timeout=_REQUEST_TIMEOUT
                )
                if resp.status_code == 200:
                    return resp.json()
                body = _safe_json(resp)
                last_error = XrpcError(method, resp.status_code, body)
                if resp.status_code < 500:
                    raise last_error
            except requests.RequestException as exc:
                last_error = XrpcError(method, 0, str(exc))
            if attempt < _RETRY_ATTEMPTS:
                time.sleep(_RETRY_BACKOFF * attempt)

        raise last_error  # type: ignore[misc]

    def admin_login(self, password: str) -> str:
        """POST /admin/login with the admin password and return the bearer
        token used for com.atproto.admin.* and tools.ozone.* calls.

        Raises XrpcError on failure.
        """
        url = f"{self.base_url}/admin/login"
        try:
            resp = self._session.post(
                url,
                json={"password": password},
                headers={"Content-Type": "application/json"},
                timeout=_REQUEST_TIMEOUT,
            )
        except requests.RequestException as exc:
            raise XrpcError("/admin/login", 0, str(exc))

        if resp.status_code != 200:
            raise XrpcError("/admin/login", resp.status_code, _safe_json(resp))
        token = resp.json().get("token", "")
        if not token:
            raise XrpcError("/admin/login", 200, {"error": "missing token in response"})
        return token

    def xrpc_get_binary(
        self,
        method: str,
        params: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> tuple[int, str, bytes]:
        """Issue an XRPC query (GET) for endpoints that return binary data
        (e.g. com.atproto.sync.getRepo returns application/vnd.ipld.car).

        Returns (status_code, content_type, body_bytes). Raises XrpcError on
        a non-2xx response with a JSON-decoded error body when possible.
        """
        url = f"{self.base_url}/xrpc/{method}"
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        last_error = None
        for attempt in range(1, _RETRY_ATTEMPTS + 1):
            try:
                resp = self._session.get(
                    url, params=params, headers=headers, timeout=_REQUEST_TIMEOUT
                )
                if 200 <= resp.status_code < 300:
                    return (
                        resp.status_code,
                        resp.headers.get("Content-Type", ""),
                        resp.content,
                    )
                last_error = XrpcError(method, resp.status_code, _safe_json(resp))
                if resp.status_code < 500:
                    raise last_error
            except requests.RequestException as exc:
                last_error = XrpcError(method, 0, str(exc))
            if attempt < _RETRY_ATTEMPTS:
                time.sleep(_RETRY_BACKOFF * attempt)

        raise last_error  # type: ignore[misc]

    def xrpc_post(
        self,
        method: str,
        body: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        """Issue an XRPC procedure and return its decoded JSON response.

        JSON procedures use 200 or 201 for success in the local services. Like
        xrpc_get, this retries transient transport/server failures but does not
        retry validation, authentication, or authorization errors.
        """
        url = f"{self.base_url}/xrpc/{method}"
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        last_error = None
        for attempt in range(1, _RETRY_ATTEMPTS + 1):
            try:
                resp = self._session.post(
                    url,
                    json=body,
                    headers=headers,
                    timeout=_REQUEST_TIMEOUT,
                )
                if resp.status_code in (200, 201):
                    return resp.json()
                err_body = _safe_json(resp)
                last_error = XrpcError(method, resp.status_code, err_body)
                if resp.status_code < 500:
                    raise last_error
            except requests.RequestException as exc:
                last_error = XrpcError(method, 0, str(exc))
            if attempt < _RETRY_ATTEMPTS:
                time.sleep(_RETRY_BACKOFF * attempt)

        raise last_error  # type: ignore[misc]

    def xrpc_post_raw(
        self,
        method: str,
        data: bytes,
        content_type: str,
        token: Optional[str] = None,
    ) -> dict:
        """Issue an XRPC procedure whose body is raw bytes.

        This path is used for blob uploads where requests' JSON serialization
        would corrupt the payload. It performs a single request because upload
        retries can duplicate writes on endpoints that are not idempotent.
        """
        url = f"{self.base_url}/xrpc/{method}"
        headers = {"Content-Type": content_type}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        resp = self._session.post(url, data=data, headers=headers, timeout=60)
        if resp.status_code in (200, 201):
            return resp.json()
        raise XrpcError(method, resp.status_code, _safe_json(resp))

    # ── Account & Session ───────────────────────────────────────────

    def create_account(
        self, handle: str, email: str, password: str, _retries: int = 3
    ) -> dict:
        """Create a new account. Returns session dict with did, handle, accessJwt, refreshJwt.

        Retries on transient PLC/network errors since PDS→PLC communication
        can be flaky on first attempt.
        """
        logger.info("Creating account: %s", handle)
        last_error = None
        for attempt in range(1, _retries + 1):
            try:
                return self.xrpc_post(
                    "com.atproto.server.createAccount",
                    {"email": email, "handle": handle, "password": password},
                )
            except XrpcError as exc:
                last_error = exc
                # Retry on PLC/network-related 400s (not validation errors)
                if exc.status == 400 and isinstance(exc.body, dict):
                    msg = str(exc.body.get("message", "")).lower()
                    if any(
                        s in msg
                        for s in ("network connection", "could not connect", "timed out")
                    ):
                        logger.warning(
                            "Account creation retry %d/%d for %s: %s",
                            attempt, _retries, handle, exc.body.get("message"),
                        )
                        if attempt < _retries:
                            time.sleep(1.0 * attempt)
                            continue
                raise
        raise last_error  # type: ignore[misc]

    def create_session(
        self, identifier: str, password: str
    ) -> dict:
        """Log in. Returns session dict."""
        logger.info("Creating session: %s", identifier)
        return self.xrpc_post(
            "com.atproto.server.createSession",
            {"identifier": identifier, "password": password},
        )

    def get_session(self, token: str) -> dict:
        """Get current session info."""
        return self.xrpc_get("com.atproto.server.getSession", token=token)

    def refresh_session(self, refresh_jwt: str) -> dict:
        """Refresh a session."""
        return self.xrpc_post(
            "com.atproto.server.refreshSession",
            token=refresh_jwt,
        )

    def delete_session(self, token: str) -> None:
        """Delete (logout) a session."""
        try:
            self.xrpc_post("com.atproto.server.deleteSession", token=token)
        except XrpcError:
            pass  # Best-effort

    def describe_server(self) -> dict:
        """Get server description."""
        return self.xrpc_get("com.atproto.server.describeServer")

    # ── Identity ─────────────────────────────────────────────────────

    def resolve_handle(self, handle: str) -> dict:
        """Resolve a handle to a DID."""
        return self.xrpc_get(
            "com.atproto.identity.resolveHandle", {"handle": handle}
        )

    def update_handle(self, handle: str, token: str) -> dict:
        """Update the authenticated user's handle."""
        return self.xrpc_post(
            "com.atproto.identity.updateHandle",
            {"handle": handle},
            token=token,
        )

    # ── Repo / Records ──────────────────────────────────────────────

    def create_record(
        self,
        repo: str,
        collection: str,
        record: dict[str, Any],
        token: str,
        rkey: Optional[str] = None,
        validate: bool = True,
    ) -> dict:
        """Create a repo record and return the server's uri/cid response.

        repo is usually the actor DID. rkey is optional; when omitted the PDS
        allocates a TID. validate can be disabled for negative-path tests that
        intentionally submit malformed records.
        """
        body: dict[str, Any] = {
            "repo": repo,
            "collection": collection,
            "record": record,
            "validate": validate,
        }
        if rkey:
            body["rkey"] = rkey
        return self.xrpc_post("com.atproto.repo.createRecord", body, token=token)

    def get_record(
        self,
        repo: str,
        collection: str,
        rkey: str,
    ) -> dict:
        """Get a record. Returns the record value."""
        return self.xrpc_get(
            "com.atproto.repo.getRecord",
            {"repo": repo, "collection": collection, "rkey": rkey},
        )

    def delete_record(
        self,
        repo: str,
        collection: str,
        rkey: str,
        token: str,
    ) -> None:
        """Delete a record."""
        self.xrpc_post(
            "com.atproto.repo.deleteRecord",
            {"repo": repo, "collection": collection, "rkey": rkey},
            token=token,
        )

    def put_record(
        self,
        repo: str,
        collection: str,
        rkey: str,
        record: dict[str, Any],
        token: str,
    ) -> dict:
        """Put (replace) a record."""
        return self.xrpc_post(
            "com.atproto.repo.putRecord",
            {"repo": repo, "collection": collection, "rkey": rkey, "record": record},
            token=token,
        )

    def list_records(
        self,
        repo: str,
        collection: str,
        limit: int = 50,
        token: Optional[str] = None,
    ) -> dict:
        """List records in a collection."""
        return self.xrpc_get(
            "com.atproto.repo.listRecords",
            {"repo": repo, "collection": collection, "limit": limit},
            token=token,
        )

    def apply_writes(
        self,
        repo: str,
        writes: list[dict[str, Any]],
        token: str,
    ) -> dict:
        """Apply an ordered batch of repo writes to one actor repository.

        The write dictionaries are passed through exactly as supplied so tests
        can exercise create, update, and delete variants from the lexicon
        without this wrapper normalizing them.
        """
        return self.xrpc_post(
            "com.atproto.repo.applyWrites",
            {"repo": repo, "writes": writes},
            token=token,
        )

    # ── Blobs ────────────────────────────────────────────────────────

    def upload_blob(
        self,
        data: bytes,
        content_type: str,
        token: str,
    ) -> dict:
        """Upload a blob. Returns {blob: {ref, mimeType, size}}."""
        return self.xrpc_post_raw(
            "com.atproto.repo.uploadBlob", data, content_type, token=token
        )

    # ── Moderation ───────────────────────────────────────────────────

    def create_report(
        self,
        reason_type: str,
        subject: dict[str, Any],
        reason: str,
        token: str,
    ) -> dict:
        """Create a moderation report."""
        return self.xrpc_post(
            "com.atproto.moderation.createReport",
            {"reasonType": reason_type, "subject": subject, "reason": reason},
            token=token,
        )

    # ── Labels ───────────────────────────────────────────────────────

    def get_labels(
        self,
        uris: list[str],
        token: Optional[str] = None,
    ) -> dict:
        """Get moderation labels for a list of AT URIs.

        The label endpoint expects repeated ``uris[]`` query parameters rather
        than a JSON array, so this method bypasses xrpc_get's simple dict-based
        parameter path.
        """
        params = [("uris[]", u) for u in uris]
        url = f"{self.base_url}/xrpc/com.atproto.label.getLabels"
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        resp = self._session.get(url, params=params, headers=headers, timeout=_REQUEST_TIMEOUT)
        if resp.status_code == 200:
            return resp.json()
        raise XrpcError("com.atproto.label.getLabels", resp.status_code, _safe_json(resp))

    # ── Admin ───────────────────────────────────────────────────────

    def get_subject_status(
        self,
        did: str,
        token: str,
    ) -> dict:
        """Get admin subject status."""
        return self.xrpc_get(
            "com.atproto.admin.getSubjectStatus",
            {"did": did},
            token=token,
        )

    def update_subject_status(
        self,
        subject: dict[str, Any],
        takedown: Optional[dict[str, Any]] = None,
        token: Optional[str] = None,
    ) -> dict:
        """Update admin subject status."""
        body: dict[str, Any] = {"subject": subject}
        if takedown:
            body["takedown"] = takedown
        return self.xrpc_post(
            "com.atproto.admin.updateSubjectStatus", body, token=token
        )

    # ── AppView / bsky ───────────────────────────────────────────────

    def get_profile(self, actor: str, token: Optional[str] = None) -> dict:
        """Get an actor's profile."""
        return self.xrpc_get("app.bsky.actor.getProfile", {"actor": actor}, token=token)

    def get_timeline(self, token: str, limit: int = 50) -> dict:
        """Get authenticated user's timeline."""
        return self.xrpc_get("app.bsky.feed.getTimeline", {"limit": limit}, token=token)

    def get_author_feed(self, actor: str, token: Optional[str] = None, limit: int = 50) -> dict:
        """Get an actor's feed."""
        return self.xrpc_get(
            "app.bsky.feed.getAuthorFeed", {"actor": actor, "limit": limit}, token=token
        )

    def get_post_thread(self, uri: str, token: Optional[str] = None) -> dict:
        """Get a post thread."""
        return self.xrpc_get("app.bsky.feed.getPostThread", {"uri": uri}, token=token)

    def get_likes(self, uri: str, token: Optional[str] = None, limit: int = 50) -> dict:
        """Get likes for a post."""
        return self.xrpc_get("app.bsky.feed.getLikes", {"uri": uri, "limit": limit}, token=token)

    def get_follows(self, actor: str, token: Optional[str] = None, limit: int = 50) -> dict:
        """Get who an actor follows."""
        return self.xrpc_get("app.bsky.graph.getFollows", {"actor": actor, "limit": limit}, token=token)

    def get_followers(self, actor: str, token: Optional[str] = None, limit: int = 50) -> dict:
        """Get an actor's followers."""
        return self.xrpc_get("app.bsky.graph.getFollowers", {"actor": actor, "limit": limit}, token=token)

    def get_blocks(self, token: str, limit: int = 50) -> dict:
        """Get authenticated user's blocks."""
        return self.xrpc_get("app.bsky.graph.getBlocks", {"limit": limit}, token=token)

    def search_actors(self, query: str, token: Optional[str] = None, limit: int = 10) -> dict:
        """Search actors."""
        return self.xrpc_get("app.bsky.actor.searchActors", {"q": query, "limit": limit}, token=token)

    def list_notifications(self, token: str, limit: int = 50) -> dict:
        """List notifications."""
        return self.xrpc_get("app.bsky.notification.listNotifications", {"limit": limit}, token=token)

    # ── Health ───────────────────────────────────────────────────────

    def health_check(self) -> bool:
        """Return True when the service's generic /_health endpoint responds."""
        try:
            resp = self._session.get(f"{self.base_url}/_health", timeout=2)
            return resp.status_code == 200
        except requests.RequestException:
            return False

    def wait_for_healthy(self, timeout: int = 30) -> None:
        """Block until /_health responds or raise RuntimeError on timeout."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.health_check():
                return
            time.sleep(0.5)
        raise RuntimeError(f"Service at {self.base_url} not healthy after {timeout}s")


def _safe_json(resp: requests.Response) -> Any:
    """Decode a response body for diagnostics.

    XRPC error responses are normally JSON, but lower-level HTTP failures,
    proxies, and panic pages may be plain text. Returning text preserves the
    useful part of the failure without masking the original status code.
    """
    try:
        return resp.json()
    except (json.JSONDecodeError, ValueError):
        return resp.text
