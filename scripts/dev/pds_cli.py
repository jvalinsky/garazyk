#!/usr/bin/env python3
"""PDS dev helper: thin wrapper around the native kaszlak binary plus a few HTTP flows.

Environment:
  NO_COLOR                 Disable ANSI colors (also implied when stdout is not a TTY).
  PDS_CLI_JSON=1           JSON status lines instead of ANSI formatting.
  PDS_CREATE_ACCOUNT_PASSWORD / PDS_POST_PASSWORD — optional alternatives to ``--password``.
  PDS_URL, PDS_DATA_DIR, PDS_BIN — see defaults below.

Leading ``--json`` / ``-j`` / ``--no-color`` are stripped before argparse so invocations like
``pds_cli.py --json account create ...`` work. The kaszlak binary requires ``kaszlak <command> [flags]``;
this script builds argv in that order.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys

import requests

# --- Configuration ---
PDS_URL = os.environ.get("PDS_URL", "http://localhost:2583")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.environ.get("PDS_DATA_DIR", os.path.join(REPO_ROOT, "data"))
BIN_PATH = os.environ.get("PDS_BIN", os.path.join(REPO_ROOT, "build/bin/kaszlak"))

PDS_CLI_JSON = os.environ.get("PDS_CLI_JSON", "").lower() in ("1", "true", "yes")
PDS_CLI_NO_COLOR = False
USE_COLOR = False


def _strip_wrapper_prefix_flags() -> None:
    """Remove leading --json / -j / --no-color from sys.argv (in place)."""
    global PDS_CLI_JSON, PDS_CLI_NO_COLOR
    i = 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a in ("--json", "-j"):
            PDS_CLI_JSON = True
            sys.argv.pop(i)
            continue
        if a == "--no-color":
            PDS_CLI_NO_COLOR = True
            sys.argv.pop(i)
            continue
        if a.startswith("-"):
            break
        break


def _configure_output() -> None:
    global USE_COLOR
    if os.environ.get("NO_COLOR"):
        USE_COLOR = False
    elif PDS_CLI_NO_COLOR:
        USE_COLOR = False
    elif PDS_CLI_JSON:
        USE_COLOR = False
    else:
        USE_COLOR = sys.stdout.isatty()


class Colors:
    HEADER = "\033[95m"
    OKBLUE = "\033[94m"
    OKCYAN = "\033[96m"
    OKGREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"


def print_success(msg: str) -> None:
    if PDS_CLI_JSON:
        print(json.dumps({"kind": "ok", "message": msg}))
        return
    if USE_COLOR:
        print(f"{Colors.OKGREEN}OK: {msg}{Colors.ENDC}")
    else:
        print(f"OK: {msg}")


def print_info(msg: str) -> None:
    if PDS_CLI_JSON:
        print(json.dumps({"kind": "info", "message": msg}))
        return
    if USE_COLOR:
        print(f"{Colors.OKBLUE}{msg}{Colors.ENDC}")
    else:
        print(msg)


def print_error(msg: str, **extra: object) -> None:
    if PDS_CLI_JSON:
        payload: dict[str, object] = {"kind": "error", "message": msg}
        for k, v in extra.items():
            if v is not None and v != "":
                payload[k] = v
        print(json.dumps(payload))
        return
    if USE_COLOR:
        print(f"{Colors.FAIL}Error: {msg}{Colors.ENDC}", file=sys.stderr)
    else:
        print(f"Error: {msg}", file=sys.stderr)


def run_kaszlak_cli(args: list[str]) -> int:
    """Run kaszlak; ``args`` must start with the subcommand, e.g. ``['account', 'create', ...]``."""
    if not args:
        print_error("Internal error: empty kaszlak argv")
        return 1
    if not os.path.exists(BIN_PATH):
        print_error(f"Binary not found at: {BIN_PATH}")
        print_info("Build the project first or set PDS_BIN.")
        return 1

    subcommand = args[0]
    tail = args[1:]
    cmd = [
        BIN_PATH,
        subcommand,
        "--verbose",
        "--data-dir",
        DATA_DIR,
        "--config",
        "/tmp/missing_cli_config.json",
    ] + tail

    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print_error(
                "kaszlak command failed",
                command=" ".join(cmd),
                stderr=(result.stderr or "").strip(),
                exit_code=result.returncode,
            )
            if not PDS_CLI_JSON and result.stdout:
                sys.stdout.write(result.stdout)
            return result.returncode
        if result.stdout:
            sys.stdout.write(result.stdout)
        return 0
    except OSError as e:
        print_error(f"Failed to run binary: {e}")
        return 1


def login(handle: str, password: str):
    print_info(f"Logging in as {handle}...")
    try:
        resp = requests.post(
            f"{PDS_URL}/xrpc/com.atproto.server.createSession",
            json={"identifier": handle, "password": password},
            timeout=10,
        )
        if resp.status_code != 200:
            print_error(f"Login failed: {resp.text}", status_code=resp.status_code)
            return None
        return resp.json()
    except requests.exceptions.ConnectionError:
        print_error(f"Could not connect to PDS at {PDS_URL}")
        return None


def create_record(session: dict, collection: str, record: dict):
    try:
        resp = requests.post(
            f"{PDS_URL}/xrpc/com.atproto.repo.createRecord",
            headers={"Authorization": f"Bearer {session['accessJwt']}"},
            json={"repo": session["did"], "collection": collection, "record": record},
            timeout=10,
        )
        if resp.status_code != 200:
            print_error(f"Failed to create record: {resp.text}", status_code=resp.status_code)
            return None
        return resp.json()
    except OSError as e:
        print_error(f"Exception during record creation: {e}")
        return None


def handle_account_create(args: argparse.Namespace) -> int:
    print_info(f"Creating account for {args.handle}...")
    password = args.password or os.environ.get("PDS_CREATE_ACCOUNT_PASSWORD")
    if not password:
        print_error(
            "Missing password: use --password or set PDS_CREATE_ACCOUNT_PASSWORD in the environment."
        )
        return 2
    rc = run_kaszlak_cli(
        [
            "account",
            "create",
            "--email",
            args.email,
            "--handle",
            args.handle,
            "--password",
            password,
        ]
    )
    if rc == 0:
        print_success(f"Account {args.handle} created successfully.")
    else:
        print_error("Failed to create account.", exit_code=rc)
    return rc


def handle_post_create(args: argparse.Namespace) -> int:
    password = args.password or os.environ.get("PDS_POST_PASSWORD")
    if not password:
        print_error(
            "Missing password: use --password or set PDS_POST_PASSWORD in the environment."
        )
        return 2
    session = login(args.handle, password)
    if not session:
        return 1

    print_info("Creating post...")
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    record = {"$type": "app.bsky.feed.post", "text": args.text, "createdAt": now}

    res = create_record(session, "app.bsky.feed.post", record)
    if res:
        print_success(f"Post created! URI: {res.get('uri')}")
        if PDS_CLI_JSON:
            print(json.dumps({"kind": "result", "uri": res.get("uri"), "cid": res.get("cid")}))
        else:
            print(f"CID: {res.get('cid')}")
        return 0
    return 1


def handle_profile_update(args: argparse.Namespace) -> int:
    password = args.password or os.environ.get("PDS_POST_PASSWORD")
    if not password:
        print_error(
            "Missing password: use --password or set PDS_POST_PASSWORD in the environment."
        )
        return 2
    session = login(args.handle, password)
    if not session:
        return 1

    print_info("Updating profile...")
    record = {
        "$type": "app.bsky.actor.profile",
        "displayName": args.name,
        "description": args.description,
    }

    res = create_record(session, "app.bsky.actor.profile", record)
    if res:
        print_success("Profile updated!")
        return 0
    return 1


def main() -> int:
    _strip_wrapper_prefix_flags()
    _configure_output()

    parser = argparse.ArgumentParser(
        description="PDS CLI Tool — dev wrapper around kaszlak and local XRPC.",
        epilog="Machine output: PDS_CLI_JSON=1 or leading --json. "
        "Passwords: --password or PDS_CREATE_ACCOUNT_PASSWORD / PDS_POST_PASSWORD.",
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    parser_account = subparsers.add_parser("account", help="Account management")
    account_subparsers = parser_account.add_subparsers(dest="subcommand", help="Account actions")

    create_account_parser = account_subparsers.add_parser("create", help="Create a new account")
    create_account_parser.add_argument("handle", help="User handle (e.g. alice.test)")
    create_account_parser.add_argument("email", help="User email")
    create_account_parser.add_argument(
        "--password",
        default=None,
        help="Account password (default: PDS_CREATE_ACCOUNT_PASSWORD env)",
    )

    parser_post = subparsers.add_parser("post", help="Post management")
    post_subparsers = parser_post.add_subparsers(dest="subcommand", help="Post actions")

    create_post_parser = post_subparsers.add_parser("create", help="Create a text post")
    create_post_parser.add_argument("handle", help="User handle")
    create_post_parser.add_argument("text", help="Post content")
    create_post_parser.add_argument(
        "--password",
        default=None,
        help="Session password (default: PDS_POST_PASSWORD env)",
    )

    parser_profile = subparsers.add_parser("profile", help="Profile management")
    profile_subparsers = parser_profile.add_subparsers(dest="subcommand", help="Profile actions")

    update_profile_parser = profile_subparsers.add_parser("update", help="Update profile")
    update_profile_parser.add_argument("handle", help="User handle")
    update_profile_parser.add_argument("--name", required=True, help="Display Name")
    update_profile_parser.add_argument("--description", required=True, help="Description")
    update_profile_parser.add_argument(
        "--password",
        default=None,
        help="Session password (default: PDS_POST_PASSWORD env)",
    )

    args = parser.parse_args()

    if args.command == "account" and args.subcommand == "create":
        return handle_account_create(args)
    if args.command == "post" and args.subcommand == "create":
        return handle_post_create(args)
    if args.command == "profile" and args.subcommand == "update":
        return handle_profile_update(args)

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
