import os
import random
import time

import requests


BASE_URL = os.environ.get("PDS_URL", "http://localhost:2583").rstrip("/")


def env_bool(key: str, default: bool) -> bool:
    raw = os.environ.get(key)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


def env_int(key: str, default: int) -> int:
    raw = os.environ.get(key)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw)
    except ValueError as e:
        raise ValueError(f"{key} must be an integer (got {raw!r})") from e


def normalize_domain(domain: str) -> str:
    d = (domain or "").strip()
    while d.startswith("."):
        d = d[1:]
    while d.endswith("."):
        d = d[:-1]
    if not d:
        raise ValueError("DEMO_HANDLE_DOMAIN must not be empty")
    return d


def wait_for_server(timeout_seconds: int = 20) -> None:
    deadline = time.time() + timeout_seconds
    last_error = None

    while time.time() < deadline:
        try:
            r = requests.get(f"{BASE_URL}/_health", timeout=1)
            if r.status_code == 200:
                return
            last_error = f"HTTP {r.status_code}"
        except Exception as e:  # noqa: BLE001
            last_error = str(e)
        time.sleep(0.25)

    raise RuntimeError(f"PDS not ready at {BASE_URL} (last error: {last_error})")


def create_account(handle: str, email: str, password: str) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.server.createAccount",
        json={"email": email, "handle": handle, "password": password},
        timeout=20,
    )
    if r.status_code != 200:
        raise RuntimeError(f"createAccount failed ({r.status_code}): {r.text}")
    return r.json()


def create_session(identifier: str, password: str) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.server.createSession",
        json={"identifier": identifier, "password": password},
        timeout=20,
    )
    if r.status_code != 200:
        raise RuntimeError(f"createSession failed ({r.status_code}): {r.text}")
    return r.json()


def create_record(access_jwt: str, repo_did: str, collection: str, record: dict) -> dict:
    r = requests.post(
        f"{BASE_URL}/xrpc/com.atproto.repo.createRecord",
        headers={"Authorization": f"Bearer {access_jwt}"},
        json={"repo": repo_did, "collection": collection, "record": record},
        timeout=20,
    )
    if r.status_code != 200:
        raise RuntimeError(f"createRecord failed ({r.status_code}): {r.text}")
    return r.json()


def main() -> None:
    seed_mode = (os.environ.get("DEMO_SEED_MODE", "create") or "create").strip().lower()
    handle_domain = normalize_domain(os.environ.get("DEMO_HANDLE_DOMAIN", "test"))
    email_domain = (os.environ.get("DEMO_EMAIL_DOMAIN", "test.invalid") or "test.invalid").strip().lstrip("@")
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
    wait_for_server(timeout_seconds=30)
    print("Server is up!")

    print("Demo config:")
    print(f"  mode={seed_mode}")
    print(f"  suffix={suffix}")
    print(f"  handle_domain={handle_domain}")
    print(f"  prefixes={','.join(prefixes)}")
    print(f"  posts_per_account={posts_per_account}")
    print(f"  create_profiles={create_profiles}")

    sessions: list[dict] = []
    for prefix in prefixes:
        handle = f"{prefix}{suffix}.{handle_domain}"
        email = f"{prefix}{suffix}@{email_domain}"

        if seed_mode == "create":
            print(f"Creating account {handle} (this may write to the configured PLC directory)...")
            session = create_account(handle, email, password)
        else:
            print(f"Logging in as {handle} ...")
            session = create_session(handle, password)

        sessions.append(session)

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    for session in sessions:
        handle = session.get("handle", "<unknown>")
        did = session.get("did", "<unknown>")
        access_jwt = session.get("accessJwt")
        if not access_jwt:
            raise RuntimeError(f"Missing accessJwt for {handle} ({did})")

        print(f"Seeding records for {handle} ({did})...")

        if create_profiles:
            create_record(
                access_jwt,
                did,
                "app.bsky.actor.profile",
                {
                    "$type": "app.bsky.actor.profile",
                    "displayName": handle.split(".")[0].capitalize(),
                    "description": "Seeded demo profile",
                },
            )

        for i in range(posts_per_account):
            create_record(
                access_jwt,
                did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": f"Demo post #{i+1} from {handle} (Run {suffix})",
                    "createdAt": now,
                },
            )

    print("")
    print("Demo accounts:")
    for session in sessions:
        print(f"  - {session.get('handle')}  password={password}  did={session.get('did')}")


if __name__ == "__main__":
    main()
