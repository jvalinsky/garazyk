"""Seeding helpers for Garazyk ATProto demo and scenario scripts.

These functions encode the conventions shared by demo seeders: UTC timestamp
formatting, server readiness polling, account creation with login fallback,
idempotent record creation, chat conversation helpers, and admin-token lookup.
They are intentionally thin wrappers over XrpcClient so seed scripts remain
easy to compare against the lexicon methods they exercise.
"""

from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Any, Optional

import requests

from .transport import XrpcError
from .client import XrpcClient


# ── Timestamp ───────────────────────────────────────────────────────────────

def now_iso() -> str:
    """Return the current UTC time in the ATProto timestamp format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── Server health ──────────────────────────────────────────────────────────

def wait_for_server(base_url: str, timeout: int = 30) -> None:
    """Wait for a PDS to be healthy by polling /_health.

    Raises RuntimeError if the server is not healthy within the timeout.
    """
    deadline = time.time() + timeout
    last_error: str | None = None
    while time.time() < deadline:
        try:
            r = requests.get(f"{base_url}/_health", timeout=2)
            if r.status_code == 200:
                return
            last_error = f"HTTP {r.status_code}"
        except requests.RequestException as e:
            last_error = str(e)
        time.sleep(0.5)
    raise RuntimeError(f"PDS not ready at {base_url} (last: {last_error})")


def wait_for_http(url: str, timeout: int = 30, label: str = "") -> bool:
    """Wait for an HTTP endpoint to return a non-5xx response.

    Returns True if the endpoint is reachable before timeout, False otherwise.
    This looser condition is useful for endpoints that require authentication
    but still prove the service is listening once they stop returning 5xx.
    """
    label = label or url
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            r = requests.get(url, timeout=2)
            if r.status_code < 500:
                return True
        except requests.ConnectionError:
            pass
        time.sleep(0.5)
    return False


# ── Account creation with login fallback ────────────────────────────────────

def create_account_or_login(
    client: XrpcClient,
    handle: str,
    email: str,
    password: str,
) -> dict[str, Any]:
    """Create an account, or fall back to login if it already exists.

    Returns a session dict with did, handle, accessJwt, and refreshJwt. The
    fallback keeps local seeding repeatable when test data from a previous run
    has not been removed.
    """
    try:
        return client.accounts.create_account(handle, email, password)
    except XrpcError:
        # Account might already exist -- try login
        pass
    return client.accounts.create_session(handle, password)


# ── Record creation with idempotency ───────────────────────────────────────

def create_record_idempotent(
    client: XrpcClient,
    repo: str,
    collection: str,
    record: dict[str, Any],
    token: str,
) -> dict[str, Any]:
    """Create a record, ignoring "already exists" errors.

    Returns the createRecord response on success, or an empty dict when the
    server reports an idempotent duplicate. Other XRPC failures still propagate
    so callers notice schema, auth, and storage errors.
    """
    try:
        return client.create_record(repo, collection, record, token)
    except XrpcError as exc:
        if exc.status == 400 and "already exists" in str(exc.body).lower():
            return {}
        raise


# ── Chat helpers ────────────────────────────────────────────────────────────

def get_convo_for_members(
    client: XrpcClient,
    jwt: str,
    member_dids: list[str],
) -> dict[str, Any]:
    """Get or create a conversation for the given member DIDs.

    Returns the raw response dict, which usually contains ``convo.id``. The
    chat service creates the conversation if an exact membership match does not
    already exist.
    """
    return client.xrpc_post(
        "chat.bsky.convo.getConvoForMembers",
        {"members": member_dids},
        token=jwt,
    )


def send_message(
    client: XrpcClient,
    jwt: str,
    convo_id: str,
    text: str,
) -> dict[str, Any]:
    """Send a text message in a conversation.

    Returns the sendMessage response. The helper stamps messages at send time
    so scenario scripts can describe conversation content without repeating
    timestamp boilerplate.
    """
    return client.xrpc_post(
        "chat.bsky.convo.sendMessage",
        {
            "convoId": convo_id,
            "message": {
                "$type": "chat.bsky.convo.def#messageRef",
                "text": text,
                "createdAt": now_iso(),
            },
        },
        token=jwt,
    )


def list_convos(
    client: XrpcClient,
    jwt: str,
    limit: int = 20,
) -> dict[str, Any]:
    """List conversations for the authenticated user."""
    return client.xrpc_get(
        "chat.bsky.convo.listConvos",
        {"limit": limit},
        token=jwt,
    )


def get_messages(
    client: XrpcClient,
    jwt: str,
    convo_id: str,
    limit: int = 50,
) -> dict[str, Any]:
    """Get messages for a conversation."""
    return client.xrpc_get(
        "chat.bsky.convo.getMessages",
        {"convoId": convo_id, "limit": limit},
        token=jwt,
    )


# ── Admin helpers ───────────────────────────────────────────────────────────

def get_pds_admin_token(base_url: str, password: str) -> str:
    """Get a PDS admin JWT via POST /admin/login.

    Returns the bearer token string. Raises RuntimeError instead of XrpcError
    because /admin/login is an admin HTTP route rather than an XRPC method.
    """
    r = requests.post(
        f"{base_url}/admin/login",
        json={"password": password},
        timeout=10,
    )
    if r.status_code != 200:
        raise RuntimeError(f"PDS admin login failed: {r.status_code}")
    return r.json()["token"]
