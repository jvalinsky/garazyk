import requests
import datetime
import sys

handle = "bober.garazyk.xyz"
password = "bobertime987!"
pds_url = "https://pds.garazyk.xyz"

try:
    # Login
    identifier = "jack.valinsky+bober@gmail.com"
    print(f"Logging in to {pds_url} as {identifier}...")
    auth_resp = requests.post(
        f"{pds_url}/xrpc/com.atproto.server.createSession",
        json={"identifier": identifier, "password": password},
    )

    if auth_resp.status_code != 200:
        print(f"Login failed: {auth_resp.status_code} {auth_resp.text}")
        sys.exit(1)

    session = auth_resp.json()
    jwt = session["accessJwt"]
    did = session["did"]

    print(f"Logged in as {did}")

    # Create Post
    now = datetime.datetime.utcnow().isoformat() + "Z"
    print("Creating post...")
    post_resp = requests.post(
        f"{pds_url}/xrpc/com.atproto.repo.createRecord",
        headers={"Authorization": f"Bearer {jwt}"},
        json={
            "repo": did,
            "collection": "app.bsky.feed.post",
            "record": {
                "$type": "app.bsky.feed.post",
                "text": "Hello from kaszlak!",
                "createdAt": now,
            },
        },
    )

    if post_resp.status_code != 200:
        print(f"Post failed: {post_resp.status_code} {post_resp.text}")
        sys.exit(1)

    print("Posted successfully!")
    print(post_resp.json())

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
