#!/usr/bin/env python3
"""Seed configurable demo accounts and records through XRPC.

The script supports two workflows:
  - create mode: create new accounts with a generated or supplied suffix.
  - login mode: reuse existing accounts and add more records.

All behavior is controlled through environment variables so CI jobs and manual
demo sessions can share the same entrypoint without adding a large argument
parser.

Usage:
    python3 scripts/dev/seed_demo_via_xrpc.py

    # Custom PDS URL:
    PDS_URL=http://localhost:2583 python3 scripts/dev/seed_demo_via_xrpc.py

    # Login mode (accounts already exist):
    DEMO_SEED_MODE=login python3 scripts/dev/seed_demo_via_xrpc.py

Environment variables:
    PDS_URL              - PDS base URL (default: http://localhost:2583)
    DEMO_SEED_MODE       - "create" or "login" (default: create)
    DEMO_HANDLE_DOMAIN   - Handle domain suffix (default: test)
    DEMO_EMAIL_DOMAIN    - Email domain (default: test.invalid)
    DEMO_SUFFIX           - Unique suffix for handles (default: random 4-digit)
    DEMO_PASSWORD         - Account password (default: hunter{suffix})
    DEMO_ACCOUNT_PREFIXES - Comma-separated account prefixes (default: alice,bob)
    DEMO_POSTS_PER_ACCOUNT - Posts per account (default: 3)
    DEMO_CREATE_PROFILES  - Create profile records (default: true)
"""

from __future__ import annotations

import os
import random
import sys
import time
from pathlib import Path

# Add scripts/ to sys.path so direct execution can import the shared atproto
# helpers from the repository checkout.
_scripts_dir = str(Path(__file__).resolve().parent.parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from lib.atproto import (
    XrpcClient,
    XrpcError,
    create_account_or_login,
    now_iso,
    wait_for_server,
)

# ── Configuration ──────────────────────────────────────────────────────────

BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583").rstrip("/")


def env_bool(key: str, default: bool) -> bool:
    """Read a boolean environment variable using common shell truthy values."""
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


def env_int(key: str, default: int) -> int:
    """Read an integer environment variable and report invalid values clearly."""
    raw = os.environ.get(key)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw)
    except ValueError as e:
        raise ValueError(f"{key} must be an integer (got {raw!r})") from e


def normalize_domain(domain: str) -> str:
    """Normalize a handle-domain suffix and reject empty values."""
    d = (domain or "").strip()
    while d.startswith("."):
        d = d[1:]
    while d.endswith("."):
        d = d[:-1]
    if not d:
        raise ValueError("DEMO_HANDLE_DOMAIN must not be empty")
    return d


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    """Create or log in demo accounts and write profile/post records."""
    seed_mode = (os.environ.get("DEMO_SEED_MODE", "create") or "create").strip().lower()
    handle_domain = normalize_domain(os.environ.get("DEMO_HANDLE_DOMAIN", "test"))
    email_domain = (os.environ.get("DEMO_EMAIL_DOMAIN", "test.invalid") or "test.invalid").strip().lstrip("@")
    # The suffix keeps create-mode reruns from colliding with handles left in a
    # persistent local PLC directory.
    suffix = (os.environ.get("DEMO_SUFFIX") or "").strip() or str(random.randint(1000, 9999))
    password = (os.environ.get("DEMO_PASSWORD") or "").strip() or f"hunter{suffix}"
    prefixes_raw = os.environ.get("DEMO_ACCOUNT_PREFIXES", "alice,bob") or "alice,bob"
    prefixes = [p.strip() for p in prefixes_raw.split(",") if p.strip()]
    posts_per_account = max(0, env_int("DEMO_POSTS_PER_ACCOUNT", 3))
    create_profiles = env_bool("DEMO_CREATE_PROFILES", True)

    if not prefixes:
        raise ValueError("DEMO_ACCOUNT_PREFIXES must include at least one prefix")

    if seed_mode not in {"create", "login"}:
        raise ValueError("DEMO_SEED_MODE must be 'create' or 'login'")

    print(f"Waiting for server at {BASE_URL} ...")
    wait_for_server(BASE_URL, timeout=30)
    print("Server is up!")

    print("Demo config:")
    print(f"  mode={seed_mode}")
    print(f"  suffix={suffix}")
    print(f"  handle_domain={handle_domain}")
    print(f"  prefixes={','.join(prefixes)}")
    print(f"  posts_per_account={posts_per_account}")
    print(f"  create_profiles={create_profiles}")

    client = XrpcClient(BASE_URL)
    now = now_iso()

    sessions: list[dict] = []
    for prefix in prefixes:
        handle = f"{prefix}{suffix}.{handle_domain}"
        email = f"{prefix}{suffix}@{email_domain}"

        if seed_mode == "create":
            print(f"Creating account {handle} (this may write to the configured PLC directory)...")
            try:
                session = client.create_account(handle, email, password)
            except XrpcError as e:
                raise RuntimeError(f"createAccount failed: {e}") from e
        else:
            print(f"Logging in as {handle} ...")
            try:
                session = client.create_session(handle, password)
            except XrpcError as e:
                raise RuntimeError(f"createSession failed: {e}") from e

        sessions.append(session)

    for session in sessions:
        handle = session.get("handle", "<unknown>")
        did = session.get("did", "<unknown>")
        access_jwt = session.get("accessJwt")
        if not access_jwt:
            raise RuntimeError(f"Missing accessJwt for {handle} ({did})")

        print(f"Seeding records for {handle} ({did})...")

        if create_profiles:
            try:
                client.create_record(did, "app.bsky.actor.profile", {
                    "$type": "app.bsky.actor.profile",
                    "displayName": handle.split(".")[0].capitalize(),
                    "description": "Seeded demo profile",
                }, access_jwt)
            except XrpcError as e:
                print(f"  Profile creation failed: {e}")

        for i in range(posts_per_account):
            try:
                client.create_record(did, "app.bsky.feed.post", {
                    "$type": "app.bsky.feed.post",
                    "text": f"Demo post #{i+1} from {handle} (Run {suffix})",
                    "createdAt": now,
                }, access_jwt)
            except XrpcError as e:
                print(f"  Post #{i+1} failed: {e}")

    print("")
    print("Demo accounts:")
    for session in sessions:
        print(f"  - {session.get('handle')}  password={password}  did={session.get('did')}")


if __name__ == "__main__":
    main()
