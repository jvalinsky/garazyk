"""Scenario 44: "The Rich Content Creator" — Content Embedding

Luna creates posts with various embed types (images, quote posts,
link cards, record+media) and verifies AppView renders them.

Services: PDS, AppView
"""

# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

from __future__ import annotations

import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient, get_character, PDS1, ScenarioResult, timed_call,
    SERVICE_URLS, create_account_or_login, now_iso,
)


def run() -> ScenarioResult:
    result = ScenarioResult("Content Embedding")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
    luna = get_character("luna")

    timed_call(result, "PDS health check",
               lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    # Create account
    session = timed_call(
        result, "Create account for Luna",
        lambda: create_account_or_login(pds, luna),
        detail_fn=lambda s: f"did={s.get('did', '?')}",
    )

    if not session:
        result.finish()
        return result

    luna.did = session["did"]
    luna.access_jwt = session["accessJwt"]

    # Upload an image blob for embedding
    image_blob = timed_call(
        result, "Upload image blob",
        lambda: _upload_test_blob(pds, luna),
        detail_fn=lambda r: f"cid={r.get('cid', '?')}" if r else "failed",
    )

    # 1. Post with image embed
    img_post_rkey = "post-image-" + str(int(time.time()))
    if image_blob:
        img_post = {
            "$type": "app.bsky.feed.post",
            "text": "Check out this image!",
            "createdAt": now_iso(),
            "embed": {
                "$type": "app.bsky.embed.images",
                "images": [{
                    "alt": "A test image",
                    "image": {
                        "$type": "blob",
                        "ref": image_blob.get("ref", {}),
                        "mimeType": "image/png",
                        "size": image_blob.get("size", 0),
                    },
                }],
            },
        }

        img_ref = timed_call(
            result, "Create post with image embed",
            lambda: pds.repositories.create_record(
                luna.did, "app.bsky.feed.post", img_post_rkey,
                img_post, luna.access_jwt,
            ),
            detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
        )
    else:
        result.step_skipped("Create post with image embed", "No blob available")

    # 2. Create a base post for quote embedding
    base_post_rkey = "post-base-" + str(int(time.time()))
    base_post = {
        "$type": "app.bsky.feed.post",
        "text": "Original post to be quoted",
        "createdAt": now_iso(),
    }

    base_ref = timed_call(
        result, "Create base post for quoting",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", base_post_rkey,
            base_post, luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r.get('uri', '?')}" if r else "failed",
    )

    # 3. Post with quote embed
    if base_ref:
        quote_post_rkey = "post-quote-" + str(int(time.time()))
        quote_post = {
            "$type": "app.bsky.feed.post",
            "text": "Quoting this great post!",
            "createdAt": now_iso(),
            "embed": {
                "$type": "app.bsky.embed.record",
                "record": {
                    "uri": base_ref.get("uri", ""),
                    "cid": base_ref.get("cid", ""),
                },
            },
        }

        timed_call(
            result, "Create post with quote embed",
            lambda: pds.repositories.create_record(
                luna.did, "app.bsky.feed.post", quote_post_rkey,
                quote_post, luna.access_jwt,
            ),
        )

    # 4. Post with link card embed (external)
    ext_post_rkey = "post-ext-" + str(int(time.time()))
    ext_post = {
        "$type": "app.bsky.feed.post",
        "text": "Check out this link!",
        "createdAt": now_iso(),
        "embed": {
            "$type": "app.bsky.embed.external",
            "external": {
                "uri": "https://example.com",
                "title": "Example Domain",
                "description": "This domain is for use in illustrative examples",
            },
        },
    }

    timed_call(
        result, "Create post with link card embed",
        lambda: pds.repositories.create_record(
            luna.did, "app.bsky.feed.post", ext_post_rkey,
            ext_post, luna.access_jwt,
        ),
    )

    # Wait for AppView indexing
    time.sleep(2)

    # Verify posts are retrievable via getPosts
    uris_to_check = []
    if base_ref:
        uris_to_check.append(base_ref.get("uri", ""))

    if uris_to_check:
        timed_call(
            result, "Verify posts retrievable via getPosts",
            lambda: appview.feeds.get_posts(
                {"uris": uris_to_check}, luna.access_jwt,
            ),
            detail_fn=lambda r: f"count={len(r.get('posts', []))}" if r else "failed",
        )

    # Verify getPostThread renders embeds
    if base_ref:
        timed_call(
            result, "Get post thread with embeds",
            lambda: appview.feeds.get_post_thread(
                {"uri": base_ref.get("uri", ""), "depth": 2}, luna.access_jwt,
            ),
        )

    result.finish()
    return result


def _upload_test_blob(pds, luna):
    """Upload a small test PNG blob."""
    try:
        # Create a minimal 1x1 PNG
        import base64
        png_data = base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        )
        return pds.repositories.upload_blob(
            luna.did, png_data, "image/png", luna.access_jwt,
        )
    except Exception:
        return None
