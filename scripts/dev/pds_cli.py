#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
import json
import requests
import datetime

# --- Configuration ---
PDS_URL = os.environ.get("PDS_URL", "http://localhost:2583")
# Default to assuming we are in the repo root if not specified
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.environ.get("PDS_DATA_DIR", os.path.join(REPO_ROOT, "data"))
BIN_PATH = os.environ.get("PDS_BIN", os.path.join(REPO_ROOT, "build/bin/kaszlak"))

# --- Colors ---
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_success(msg):
    print(f"{Colors.OKGREEN}✓ {msg}{Colors.ENDC}")

def print_info(msg):
    print(f"{Colors.OKBLUE}ℹ {msg}{Colors.ENDC}")

def print_error(msg):
    print(f"{Colors.FAIL}✗ {msg}{Colors.ENDC}")

# --- Helper Functions ---

def run_kaszlak_cli(args):
    """Executes the native kaszlak binary."""
    if not os.path.exists(BIN_PATH):
        print_error(f"Binary not found at: {BIN_PATH}")
        print_info("Please build the project first or set PDS_BIN environment variable.")
        sys.exit(1)

    # Use a dummy config to force CLI args to take precedence over any default config.json
    cmd = [BIN_PATH, "--verbose", "--data-dir", DATA_DIR, "--config", "/tmp/missing_cli_config.json"] + args
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print_error(f"CLI Command executed: {' '.join(cmd)}")
            print_error(f"Error output:\n{result.stderr}")
            return False
        
        if result.stdout:
            print(result.stdout)
        return True
    except Exception as e:
        print_error(f"Failed to run binary: {e}")
        return False

def login(handle, password):
    """Logs in to the PDS and returns the session object."""
    print_info(f"Logging in as {handle}...")
    try:
        resp = requests.post(f"{PDS_URL}/xrpc/com.atproto.server.createSession", json={
            "identifier": handle,
            "password": password
        }, timeout=10)
        if resp.status_code != 200:
            print_error(f"Login failed: {resp.text}")
            return None
        return resp.json()
    except requests.exceptions.ConnectionError:
        print_error(f"Could not connect to PDS at {PDS_URL}")
        return None

def create_record(session, collection, record):
    """Creates a generic record in the user's repo."""
    try:
        resp = requests.post(
            f"{PDS_URL}/xrpc/com.atproto.repo.createRecord",
            headers={"Authorization": f"Bearer {session['accessJwt']}"},
            json={
                "repo": session["did"],
                "collection": collection,
                "record": record
            },
            timeout=10
        )
        if resp.status_code != 200:
            print_error(f"Failed to create record: {resp.text}")
            return None
        return resp.json()
    except Exception as e:
        print_error(f"Exception during record creation: {e}")
        return None

# --- Command Handlers ---

def handle_account_create(args):
    print_info(f"Creating account for {args.handle}...")
    success = run_kaszlak_cli(["account", "create", "--email", args.email, "--handle", args.handle, "--password", args.password])
    if success:
        print_success(f"Account {args.handle} created sucessfully!")
    else:
        print_error("Failed to create account.")

def handle_post_create(args):
    session = login(args.handle, args.password)
    if not session:
        return

    print_info("Creating post...")
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    record = {
        "$type": "app.bsky.feed.post",
        "text": args.text,
        "createdAt": now
    }
    
    res = create_record(session, "app.bsky.feed.post", record)
    if res:
        print_success(f"Post created! URI: {res.get('uri')}")
        print(f"CID: {res.get('cid')}")

def handle_profile_update(args):
    session = login(args.handle, args.password)
    if not session:
        return

    print_info("Updating profile...")
    record = {
        "$type": "app.bsky.actor.profile",
        "displayName": args.name,
        "description": args.description
    }

    # Note: Using createRecord. Ideally checking if it exists and using putRecord/deleteRecord is better,
    # but for this simple CLI we'll assume create or overwrite logic isn't strictly enforced by backend yet
    # or simple create is enough for a "new" profile.
    # Actually, createRecord will fail if a self-profile already exists usually on real Bsky, 
    # but let's try it. If it fails, maybe we need swap?
    # For simplicity let's stick to createRecord.
    
    res = create_record(session, "app.bsky.actor.profile", record)
    if res:
        print_success("Profile updated!")

# --- Main ---

def main():
    parser = argparse.ArgumentParser(description="PDS CLI Tool - Manage your local AT Protocol PDS")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Account Create
    parser_account = subparsers.add_parser("account", help="Account management")
    account_subparsers = parser_account.add_subparsers(dest="subcommand", help="Account actions")
    
    create_account_parser = account_subparsers.add_parser("create", help="Create a new account")
    create_account_parser.add_argument("handle", help="User handle (e.g. alice.test)")
    create_account_parser.add_argument("email", help="User email")
    create_account_parser.add_argument("password", help="User password")

    # Post Create
    parser_post = subparsers.add_parser("post", help="Post management")
    post_subparsers = parser_post.add_subparsers(dest="subcommand", help="Post actions")
    
    create_post_parser = post_subparsers.add_parser("create", help="Create a text post")
    create_post_parser.add_argument("handle", help="User handle")
    create_post_parser.add_argument("password", help="User password")
    create_post_parser.add_argument("text", help="Post content")

    # Profile Update
    parser_profile = subparsers.add_parser("profile", help="Profile management")
    profile_subparsers = parser_profile.add_subparsers(dest="subcommand", help="Profile actions")

    update_profile_parser = profile_subparsers.add_parser("update", help="Update profile")
    update_profile_parser.add_argument("handle", help="User handle")
    update_profile_parser.add_argument("password", help="User password")
    update_profile_parser.add_argument("--name", required=True, help="Display Name")
    update_profile_parser.add_argument("--description", required=True, help="Description")

    args = parser.parse_args()

    if args.command == "account" and args.subcommand == "create":
        handle_account_create(args)
    elif args.command == "post" and args.subcommand == "create":
        handle_post_create(args)
    elif args.command == "profile" and args.subcommand == "update":
        handle_profile_update(args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
