#!/usr/bin/env python3
"""Launch and seed a complete local Garazyk ATProto network.

The launcher starts PLC, PDS, Relay, AppView, and the Admin UI from BUILD_DIR,
waits for each service to pass its readiness check, creates a small social
graph, configures the Admin UI with a PDS admin token, and optionally delegates
chat setup to seed_chat.py.

The script is designed for local demos and integration debugging. It owns the
processes it starts and tears them down on Ctrl+C; --stop is a best-effort
cleanup path for processes left behind by an interrupted run.

Usage:
    # Full stack with all seeding:
    python3 scripts/seed_network.py

    # Skip chat seeding:
    python3 scripts/seed_network.py --skip-chat

    # Skip seeding entirely (just start services):
    python3 scripts/seed_network.py --skip-seed

    # Custom build directory:
    BUILD_DIR=./build/bin python3 scripts/seed_network.py

    # Stop all services:
    python3 scripts/seed_network.py --stop

Environment variables:
    BUILD_DIR           - Binary directory (default: ./build/bin)
    PLC_PORT            - PLC port (default: 2582)
    PDS_PORT            - PDS port (default: 2583)
    RELAY_PORT          - Relay port (default: 2584)
    APPVIEW_PORT        - AppView port (default: 3200)
    UI_PORT             - UI server port (default: 2590)
    PDS_ADMIN_PASSWORD  - PDS admin password (default: admin123)
    UI_ADMIN_PASSWORD   - UI admin password (default: localdev)
    PDS_MASTER_SECRET   - PDS master secret (default: test-master-secret-123)
    APPVIEW_ADMIN_SECRET - AppView admin secret (default: appview-admin-secret)
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

# Add scripts/ to sys.path so this file can be run directly from the repo root
# without requiring the shared helpers to be installed as a package.
_scripts_dir = str(Path(__file__).resolve().parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from lib.atproto import (
    XrpcClient,
    XrpcError,
    create_account_or_login,
    now_iso,
    wait_for_http,
    get_pds_admin_token,
    SERVICE_PORTS,
    SERVICE_URLS,
    PDS_ADMIN_PASSWORD,
    PDS_MASTER_SECRET,
    APPVIEW_ADMIN_SECRET,
    UI_ADMIN_PASSWORD,
)

# ── Configuration ────────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BUILD_DIR = Path(os.environ.get("BUILD_DIR", PROJECT_ROOT / "build" / "bin"))

PLC_URL = SERVICE_URLS["plc"]
PDS_URL = SERVICE_URLS["pds"]
RELAY_URL = SERVICE_URLS["relay"]
APPVIEW_URL = SERVICE_URLS["appview"]
UI_URL = SERVICE_URLS["ui"]

LOG_DIR = PROJECT_ROOT / "logs"

# Accounts to seed
SEED_ACCOUNTS = [
    {"handle": "alice.garazyk.xyz", "email": "alice@garazyk.xyz", "password": "alicepass123"},
    {"handle": "bob.garazyk.xyz", "email": "bob@garazyk.xyz", "password": "bobpass123"},
    {"handle": "carol.garazyk.xyz", "email": "carol@garazyk.xyz", "password": "carolpass123"},
]

# Posts per account
SEED_POSTS = {
    "alice.garazyk.xyz": [
        "Hello from Alice!",
        "Beautiful day in the ATmosphere!",
        "Just set up my ATProto node!",
    ],
    "bob.garazyk.xyz": [
        "Hey everyone, Bob here!",
        "Working on relay code today",
    ],
    "carol.garazyk.xyz": [
        "Carol checking in!",
        "Love this decentralized web!",
    ],
}

# Follow graph: follower -> [followees]
SEED_FOLLOWS = {
    "bob.garazyk.xyz": ["alice.garazyk.xyz"],
    "carol.garazyk.xyz": ["alice.garazyk.xyz", "bob.garazyk.xyz"],
    "alice.garazyk.xyz": ["carol.garazyk.xyz"],
}

# ── Helpers ──────────────────────────────────────────────────────────────────

processes: list[subprocess.Popen] = []


def log(tag: str, msg: str) -> None:
    """Print a tagged status line for the local launcher."""
    print(f"  [{tag}] {msg}")


def start_service(
    name: str,
    args: list[str],
    env: dict[str, str] | None = None,
    log_file: str | None = None,
) -> subprocess.Popen:
    """Start a managed background service and redirect output to logs.

    The returned Popen is stored in the global process list so stop_all can
    terminate services in reverse startup order.
    """
    full_env = {**os.environ, **(env or {})}
    log_path = LOG_DIR / (log_file or f"{name}.log")
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    fh = open(log_path, "w")
    proc = subprocess.Popen(args, env=full_env, stdout=fh, stderr=fh)
    processes.append(proc)
    log(name, f"Started PID {proc.pid}, log: {log_path}")
    return proc


def stop_all() -> None:
    """Stop managed and stray local service processes.

    Managed Popen objects are terminated first. The final pkill pass catches
    service processes from previous runs, which is helpful when a launcher was
    interrupted before it could record every child PID.
    """
    log("STOP", "Stopping all services...")
    for proc in reversed(processes):
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
    processes.clear()

    # Also kill any stray processes by name
    for name in ["campagnola", "kaszlak", "zuk", "syrena", "garazyk-ui"]:
        subprocess.run(["pkill", "-f", name], capture_output=True, timeout=5)
    log("STOP", "All services stopped.")


# ── Service Starters ─────────────────────────────────────────────────────────

def start_plc() -> subprocess.Popen:
    """Start the PLC directory service and require its health endpoint."""
    proc = start_service(
        "PLC",
        [str(BUILD_DIR / "campagnola"), "serve", "--port", str(SERVICE_PORTS["plc"])],
        log_file="plc.log",
    )
    if not wait_for_http(f"{PLC_URL}/_health", label="PLC"):
        log("PLC", "FAILED health check")
        sys.exit(1)
    log("PLC", f"Healthy at {PLC_URL}")
    return proc


def start_pds() -> subprocess.Popen:
    """Start the PDS with local PLC and demo secrets configured."""
    proc = start_service(
        "PDS",
        [str(BUILD_DIR / "kaszlak"), "serve"],
        env={
            "PDS_PLC_URL": PLC_URL,
            "PDS_MASTER_SECRET": PDS_MASTER_SECRET,
            "PDS_ADMIN_PASSWORD": PDS_ADMIN_PASSWORD,
        },
        log_file="pds.log",
    )
    if not wait_for_http(f"{PDS_URL}/_health", label="PDS"):
        log("PDS", "FAILED health check")
        sys.exit(1)
    log("PDS", f"Healthy at {PDS_URL}")
    return proc


def start_relay() -> subprocess.Popen:
    """Start the relay without upstreams; scenarios wire it explicitly later."""
    proc = start_service(
        "Relay",
        [str(BUILD_DIR / "zuk"), "serve", "--port", str(SERVICE_PORTS["relay"]), "--no-upstream"],
        log_file="relay.log",
    )
    if not wait_for_http(f"{RELAY_URL}/api/relay/health", label="Relay"):
        log("Relay", "FAILED health check")
        sys.exit(1)
    log("Relay", f"Healthy at {RELAY_URL}")
    return proc


def start_appview() -> subprocess.Popen:
    """Start AppView pointed at the local relay firehose."""
    proc = start_service(
        "AppView",
        [str(BUILD_DIR / "syrena"), "serve", "--port", str(SERVICE_PORTS["appview"])],
        env={
            "APPVIEW_RELAY_URLS": f"ws://127.0.0.1:{SERVICE_PORTS['relay']}/xrpc/com.atproto.sync.subscribeRepos",
            "APPVIEW_ADMIN_SECRET": APPVIEW_ADMIN_SECRET,
        },
        log_file="appview.log",
    )
    # AppView doesn't have /_health, check root
    if not wait_for_http(f"{APPVIEW_URL}/", label="AppView"):
        log("AppView", "FAILED health check")
        sys.exit(1)
    log("AppView", f"Healthy at {APPVIEW_URL}")
    return proc


def start_ui() -> subprocess.Popen:
    """Start the Admin UI with URLs for all local backend services."""
    proc = start_service(
        "UI",
        [str(BUILD_DIR / "garazyk-ui"), "serve"],
        env={
            "GARAZYK_UI_PDS_URL": PDS_URL,
            "GARAZYK_UI_PLC_URL": PLC_URL,
            "GARAZYK_UI_RELAY_URL": RELAY_URL,
            "GARAZYK_UI_APPVIEW_URL": APPVIEW_URL,
            "GARAZYK_UI_CHAT_URL": PDS_URL,  # chat endpoints are on PDS
            "GARAZYK_UI_ADMIN_PASSWORD": UI_ADMIN_PASSWORD,
        },
        log_file="ui.log",
    )
    if not wait_for_http(f"{UI_URL}/admin", label="UI"):
        log("UI", "FAILED health check")
        sys.exit(1)
    log("UI", f"Healthy at {UI_URL}")
    return proc


# ── UI Connection Helpers ───────────────────────────────────────────────────

def set_ui_connections(pds_token: str) -> None:
    """Set the PDS admin token in the UI server via the connections endpoint.

    Failure is logged and ignored because the network is still useful for API
    testing even if the UI cannot persist its admin connection settings.
    """
    import requests
    # Login to UI
    s = requests.Session()
    r = s.post(f"{UI_URL}/admin/login", json={"password": UI_ADMIN_PASSWORD}, timeout=10)
    if r.status_code != 200:
        log("UI", f"Login failed: {r.status_code}")
        return
    # Set connections
    r = s.post(
        f"{UI_URL}/admin/actions/update-connections",
        json={"pdsToken": pds_token},
        timeout=10,
    )
    if r.status_code == 200:
        log("UI", "PDS admin token configured")
    else:
        log("UI", f"Failed to set connections: {r.status_code}")


# ── Seeding ──────────────────────────────────────────────────────────────────

def seed_accounts_and_data() -> dict[str, dict]:
    """Create demo accounts, posts, and follow relationships.

    Returns a mapping of handle to session dict for accounts that were created
    or logged in successfully. Individual seed failures are logged so one bad
    record does not prevent the rest of the demo graph from being populated.
    """
    client = XrpcClient(PDS_URL)
    now = now_iso()
    sessions: dict[str, dict] = {}

    # Create accounts
    log("SEED", "Creating accounts...")
    for acct in SEED_ACCOUNTS:
        try:
            session = create_account_or_login(
                client, acct["handle"], acct["email"], acct["password"]
            )
            sessions[acct["handle"]] = session
            log("SEED", f"  {acct['handle']}: {session.get('did', '?')}")
        except XrpcError as e:
            log("SEED", f"  FAILED {acct['handle']}: {e}")

    # Create posts
    log("SEED", "Creating posts...")
    for handle, posts in SEED_POSTS.items():
        if handle not in sessions:
            continue
        jwt = sessions[handle]["accessJwt"]
        did = sessions[handle]["did"]
        for text in posts:
            try:
                client.create_record(did, "app.bsky.feed.post", {
                    "$type": "app.bsky.feed.post",
                    "text": text,
                    "createdAt": now,
                }, jwt)
                log("SEED", f"  [{handle}]: {text[:40]}")
            except XrpcError as e:
                log("SEED", f"  Post failed: {e}")

    # Create follows
    log("SEED", "Creating follow graph...")
    for follower_handle, followee_handles in SEED_FOLLOWS.items():
        if follower_handle not in sessions:
            continue
        jwt = sessions[follower_handle]["accessJwt"]
        did = sessions[follower_handle]["did"]
        for followee_handle in followee_handles:
            if followee_handle not in sessions:
                continue
            try:
                client.create_record(did, "app.bsky.graph.follow", {
                    "$type": "app.bsky.graph.follow",
                    "subject": sessions[followee_handle]["did"],
                    "createdAt": now,
                }, jwt)
                log("SEED", f"  {follower_handle.split('.')[0]} -> {followee_handle.split('.')[0]}")
            except XrpcError as e:
                log("SEED", f"  Follow failed: {e}")

    return sessions


def seed_chat() -> None:
    """Run seed_chat.py against the PDS URL used by this launcher."""
    chat_script = PROJECT_ROOT / "scripts" / "seed_chat.py"
    if not chat_script.exists():
        log("CHAT", f"seed_chat.py not found at {chat_script}")
        return
    log("CHAT", "Running seed_chat.py...")
    env = {**os.environ, "PDS_URL": PDS_URL}
    result = subprocess.run(
        [sys.executable, str(chat_script)],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.stdout:
        for line in result.stdout.strip().split("\n"):
            print(f"  {line}")
    if result.returncode != 0 and result.stderr:
        for line in result.stderr.strip().split("\n"):
            print(f"  [ERR] {line}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Launch and seed the full Garazyk ATProto network")
    parser.add_argument("--stop", action="store_true", help="Stop all running services")
    parser.add_argument("--skip-seed", action="store_true", help="Skip data seeding (just start services)")
    parser.add_argument("--skip-chat", action="store_true", help="Skip chat seeding")
    parser.add_argument("--skip-appview", action="store_true", help="Skip AppView startup")
    parser.add_argument("--skip-relay", action="store_true", help="Skip Relay startup")
    parser.add_argument("--skip-ui", action="store_true", help="Skip UI server startup")
    args = parser.parse_args()

    if args.stop:
        stop_all()
        return

    # Register signal handler for graceful shutdown
    def handle_signal(sig, frame):
        log("SIGNAL", f"Received signal {sig}, shutting down...")
        stop_all()
        sys.exit(130)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    print()
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║     Garazyk ATProto Network Launcher         ║")
    print("  ╚══════════════════════════════════════════════╝")
    print()

    # Check binaries exist
    for name, binary in [
        ("PLC", "campagnola"),
        ("PDS", "kaszlak"),
        ("Relay", "zuk"),
        ("AppView", "syrena"),
        ("UI", "garazyk-ui"),
    ]:
        path = BUILD_DIR / binary
        if not path.exists():
            skip_flag = {
                "AppView": args.skip_appview,
                "Relay": args.skip_relay,
                "UI": args.skip_ui,
            }.get(name, False)
            if skip_flag:
                continue
            print(f"  [ERROR] Binary not found: {path}")
            print(f"          Build with: cmake --build build --target {binary}")
            sys.exit(1)

    # Kill any existing instances
    log("INIT", "Stopping any existing services...")
    for name in ["campagnola", "kaszlak", "zuk", "syrena", "garazyk-ui"]:
        subprocess.run(["pkill", "-f", name], capture_output=True, timeout=5)
    time.sleep(1)

    # Start services in dependency order
    log("INIT", "Starting services...")

    start_plc()
    time.sleep(1)

    start_pds()
    time.sleep(1)

    if not args.skip_relay:
        start_relay()
        time.sleep(1)

    if not args.skip_appview:
        start_appview()
        time.sleep(1)

    if not args.skip_ui:
        start_ui()
        time.sleep(1)

    # Seed data
    if not args.skip_seed:
        sessions = seed_accounts_and_data()

        # Configure UI with PDS admin token
        if not args.skip_ui:
            try:
                token = get_pds_admin_token(PDS_URL, PDS_ADMIN_PASSWORD)
                set_ui_connections(token)
            except RuntimeError as e:
                log("UI", f"Failed to configure PDS token: {e}")

        # Seed chat
        if not args.skip_chat:
            seed_chat()

    # Print summary
    print()
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║     All Services Running                     ║")
    print("  ╚══════════════════════════════════════════════╝")
    print()
    print(f"  PLC:      {PLC_URL}")
    print(f"  PDS:      {PDS_URL}")
    if not args.skip_relay:
        print(f"  Relay:    {RELAY_URL}")
    if not args.skip_appview:
        print(f"  AppView:  {APPVIEW_URL}")
    if not args.skip_ui:
        print(f"  UI:       {UI_URL}/admin")
    print()
    print(f"  Logs:  {LOG_DIR}/")
    print("  Stop:  python3 scripts/seed_network.py --stop")
    print("         (or Ctrl+C)")
    print()

    # Wait for processes
    try:
        for proc in processes:
            proc.wait()
    except KeyboardInterrupt:
        pass
    finally:
        stop_all()


if __name__ == "__main__":
    main()
