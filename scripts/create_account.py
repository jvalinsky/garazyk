#!/usr/bin/env python3
"""Create a new account on a Garazyk PDS instance.

Uses SSH only for invite code generation (insert into SQLite).
All other operations (createAccount, updateProfile, createRecord)
go through XRPC over HTTPS.

Configurable via CLI flags or environment variables.
"""

import argparse
import json
import os
import secrets
import string
import subprocess
import sys
import urllib.request
import urllib.error
import urllib.parse
import uuid
from datetime import datetime, timezone
from typing import Optional


# ── Invite code generation ──────────────────────────────────────────

INVITE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"


def generate_invite_code(groups: int = 4, length: int = 5) -> str:
    """Generate an invite code matching the Garazyk format: XXXXX-XXXXX-XXXXX-XXXXX"""
    parts = []
    for _ in range(groups):
        part = "".join(secrets.choice(INVITE_ALPHABET) for _ in range(length))
        parts.append(part)
    return "-".join(parts)


def insert_invite_code_via_ssh(
    ssh_host: str, db_path: str, code: str, account_did: str, max_uses: int = 1
) -> None:
    """Insert an invite code into the PDS SQLite database via SSH.

    Uses sqlite3's .read stdin mode to avoid shell quoting issues.
    """
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    code_id = str(uuid.uuid4())
    sql = (
        "INSERT INTO invite_codes "
        "(id, code, account_did, created_at, uses, max_uses, disabled) "
        "VALUES ('{code_id}', '{code}', '{account_did}', '{now}', 0, {max_uses}, 0);"
    ).format(
        code_id=code_id, code=code, account_did=account_did, now=now, max_uses=max_uses
    )
    # Pass SQL via stdin to avoid shell quoting issues with parentheses
    # ssh -T disables pseudo-terminal allocation
    cmd = ["ssh", "-T", ssh_host, "sqlite3", db_path]
    result = subprocess.run(cmd, input=sql, capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: Failed to insert invite code via SSH: " + result.stderr.strip())
        sys.exit(1)


def get_existing_invite_code_via_ssh(ssh_host: str, db_path: str) -> Optional[str]:
    """Find an unused invite code in the PDS database via SSH."""
    sql = (
        "SELECT code FROM invite_codes "
        "WHERE disabled = 0 AND uses < max_uses "
        "LIMIT 1;"
    )
    cmd = ["ssh", "-T", ssh_host, "sqlite3", db_path]
    result = subprocess.run(cmd, input=sql, capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: Failed to query invite codes via SSH: " + result.stderr.strip())
        sys.exit(1)
    code = result.stdout.strip()
    return code if code else None


# ── XRPC helpers ────────────────────────────────────────────────────


def xrpc_url(pds_url: str, method: str) -> str:
    return f"{pds_url}/xrpc/{method}"


def xrpc_post(
    pds_url: str,
    method: str,
    body: dict,
    auth_token: Optional[str] = None,
) -> Optional[dict]:
    """POST an XRPC request and return the JSON response (or None for empty)."""
    url = xrpc_url(pds_url, method)
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    if auth_token:
        req.add_header("Authorization", "Bearer " + auth_token)
    try:
        with urllib.request.urlopen(req) as resp:
            resp_body = resp.read().decode("utf-8")
            if resp_body:
                return json.loads(resp_body)
            return None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print("ERROR: XRPC " + method + " returned " + str(e.code) + ": " + err_body)
        sys.exit(1)


def xrpc_get(
    pds_url: str,
    method: str,
    params: Optional[dict] = None,
    auth_token: Optional[str] = None,
) -> dict:
    """GET an XRPC request and return the JSON response."""
    url = xrpc_url(pds_url, method)
    if params:
        qs = urllib.parse.urlencode(params)
        url = f"{url}?{qs}"
    req = urllib.request.Request(url)
    if auth_token:
        req.add_header("Authorization", f"Bearer {auth_token}")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"ERROR: XRPC {method} returned {e.code}: {body}")
        sys.exit(1)


# ── Account creation flow ──────────────────────────────────────────


def create_account(
    pds_url: str,
    email: str,
    handle: str,
    password: str,
    invite_code: str,
) -> dict:
    """Create an account via com.atproto.server.createAccount."""
    body = {
        "email": email,
        "handle": handle,
        "password": password,
        "inviteCode": invite_code,
    }
    return xrpc_post(pds_url, "com.atproto.server.createAccount", body)


def create_session(
    pds_url: str, identifier: str, password: str
) -> dict:
    """Create a session via com.atproto.server.createSession."""
    body = {
        "identifier": identifier,
        "password": password,
    }
    return xrpc_post(pds_url, "com.atproto.server.createSession", body)


def update_profile(
    pds_url: str,
    access_jwt: str,
    did: str,
    display_name: Optional[str] = None,
    description: Optional[str] = None,
) -> dict:
    """Set the profile record via com.atproto.repo.createRecord.

    Uses createRecord (not putRecord) because the profile record
    doesn't exist yet for a new account.
    """
    record = {"$type": "app.bsky.actor.profile"}
    if display_name:
        record["displayName"] = display_name
    if description:
        record["description"] = description
    record["createdAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    body = {
        "repo": did,
        "collection": "app.bsky.actor.profile",
        "rkey": "self",
        "record": record,
    }
    return xrpc_post(pds_url, "com.atproto.repo.createRecord", body, auth_token=access_jwt)


def create_post(
    pds_url: str,
    access_jwt: str,
    did: str,
    text: str,
) -> dict:
    """Create a post via com.atproto.repo.createRecord."""
    record = {
        "$type": "app.bsky.feed.post",
        "text": text,
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
    }
    body = {
        "repo": did,
        "collection": "app.bsky.feed.post",
        "record": record,
    }
    return xrpc_post(pds_url, "com.atproto.repo.createRecord", body, auth_token=access_jwt)


def request_crawl(relay_url: str, hostname: str) -> None:
    """Request a crawl from a relay via com.atproto.sync.requestCrawl."""
    body = {"hostname": hostname}
    try:
        xrpc_post(relay_url, "com.atproto.sync.requestCrawl", body)
        print("  Crawl requested from " + relay_url)
    except SystemExit:
        # Don't fail the whole script if crawl request fails
        print("  WARNING: Crawl request failed (non-fatal)")
    except Exception:
        print("  WARNING: Crawl request failed (non-fatal)")


# ── Main ───────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Create a new account on a Garazyk PDS instance"
    )
    parser.add_argument(
        "--pds-url",
        default=os.getenv("PDS_URL", "https://pds.garazyk.xyz"),
        help="PDS base URL (default: https://pds.garazyk.xyz)",
    )
    parser.add_argument(
        "--ssh-host",
        default=os.getenv("SSH_HOST", "DEPLOY_HOST"),
        help="SSH hostname for invite code DB access (default: DEPLOY_HOST)",
    )
    parser.add_argument(
        "--db-path",
        default=os.getenv("PDS_DB_PATH", "~/pds-data/service/service.db"),
        help="Path to PDS service.db on the remote host (default: ~/pds-data/service/service.db)",
    )
    parser.add_argument(
        "--handle",
        required=True,
        help="Handle for the new account (e.g. example.garazyk.xyz)",
    )
    parser.add_argument(
        "--email",
        default=None,
        help="Email for the new account (default: <handle>@garazyk.xyz)",
    )
    parser.add_argument(
        "--password",
        default=None,
        help="Password (default: auto-generated 24-char random string)",
    )
    parser.add_argument(
        "--display-name",
        default=None,
        help="Display name for profile (default: capitalized handle prefix)",
    )
    parser.add_argument(
        "--description",
        default=None,
        help="Profile description/bio",
    )
    parser.add_argument(
        "--post",
        action="append",
        default=[],
        help="Post text to create (can be repeated for multiple posts)",
    )
    parser.add_argument(
        "--request-crawl",
        action="store_true",
        default=False,
        help="Request a crawl from bsky.network relay after account creation",
    )
    parser.add_argument(
        "--relay-url",
        default=os.getenv("RELAY_URL", "https://bsky.network"),
        help="Relay URL for crawl request (default: https://bsky.network)",
    )
    parser.add_argument(
        "--invite-code-did",
        default="did:plc:system",
        help="DID to associate with the generated invite code (default: did:plc:system)",
    )
    parser.add_argument(
        "--reuse-invite-code",
        action="store_true",
        default=False,
        help="Reuse an existing unused invite code instead of generating a new one",
    )

    args = parser.parse_args()

    # Defaults
    handle_prefix = args.handle.split(".")[0]
    email = args.email or f"{handle_prefix}@garazyk.xyz"
    password = args.password or "".join(
        secrets.choice(string.ascii_letters + string.digits) for _ in range(24)
    )
    display_name = args.display_name or handle_prefix.capitalize()

    print(f"═══ Garazyk Account Creator ═══")
    print(f"  PDS:        {args.pds_url}")
    print(f"  SSH host:   {args.ssh_host}")
    print(f"  Handle:     {args.handle}")
    print(f"  Email:      {email}")
    print(f"  Display:    {display_name}")
    print()

    # ── Step 1: Get or create invite code ──────────────────────────
    print("[1/5] Invite code")
    invite_code = None
    if args.reuse_invite_code:
        invite_code = get_existing_invite_code_via_ssh(args.ssh_host, args.db_path)
        if invite_code:
            print(f"  Reusing existing invite code: {invite_code}")
        else:
            print("  No unused invite codes found, generating a new one")

    if not invite_code:
        invite_code = generate_invite_code()
        insert_invite_code_via_ssh(
            args.ssh_host, args.db_path, invite_code, args.invite_code_did
        )
        print(f"  Generated invite code: {invite_code}")

    # ── Step 2: Create account ─────────────────────────────────────
    print(f"\n[2/5] Creating account")
    result = create_account(args.pds_url, email, args.handle, password, invite_code)
    did = result.get("did")
    access_jwt = result.get("accessJwt")
    refresh_jwt = result.get("refreshJwt")

    if not did:
        print(f"  ERROR: No DID returned from createAccount: {result}")
        sys.exit(1)

    print(f"  DID:  {did}")
    print(f"  Handle: {args.handle}")
    print(f"  Access JWT: {access_jwt[:40]}..." if access_jwt else "  No access JWT")

    # ── Step 3: Create session (if no JWT from createAccount) ───────
    if not access_jwt:
        print(f"\n[2.5/5] Creating session (no JWT from createAccount)")
        session = create_session(args.pds_url, args.handle, password)
        access_jwt = session.get("accessJwt")
        refresh_jwt = session.get("refreshJwt")
        if not access_jwt:
            print(f"  ERROR: No access JWT from createSession")
            sys.exit(1)
        print(f"  Access JWT: {access_jwt[:40]}...")

    # ── Step 4: Set profile ─────────────────────────────────────────
    print(f"\n[3/5] Setting profile")
    profile_result = update_profile(
        args.pds_url, access_jwt, did, display_name, args.description
    )
    print(f"  Profile set: {display_name}")
    if args.description:
        print(f"  Bio: {args.description[:60]}...")

    # ── Step 5: Create posts ────────────────────────────────────────
    if args.post:
        print(f"\n[4/5] Creating {len(args.post)} post(s)")
        for i, text in enumerate(args.post, 1):
            post_result = create_post(args.pds_url, access_jwt, did, text)
            uri = post_result.get("uri", "unknown")
            print(f"  Post {i}: {text[:50]}{'...' if len(text) > 50 else ''}")
            print(f"    URI: {uri}")
    else:
        print(f"\n[4/5] No posts to create (use --post to add posts)")

    # ── Step 6: Request crawl ───────────────────────────────────────
    if args.request_crawl:
        print(f"\n[5/5] Requesting relay crawl")
        hostname = urllib.parse.urlparse(args.pds_url).hostname
        request_crawl(args.relay_url, hostname)
    else:
        print(f"\n[5/5] Skipping relay crawl (use --request-crawl to enable)")

    # ── Summary ──────────────────────────────────────────────────────
    print(f"\n{'═' * 40}")
    print(f"  Account created successfully!")
    print(f"  Handle:   {args.handle}")
    print(f"  DID:      {did}")
    print(f"  Email:    {email}")
    print(f"  Password: {password}")
    print(f"{'═' * 40}")


if __name__ == "__main__":
    main()
