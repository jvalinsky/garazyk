# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

"""Scenario 51: "The Blob Janitor" — Blob Garbage Collection

Luna uploads two small snapshots, publishes one post that should survive and
one post that should not, then runs the cleanup path that Garazyk actually
ships today: explicit blob deletion after the record is gone. The point is to
prove that unreferenced media stops downloading while the still-referenced blob
remains reachable.

Services: PDS
"""

from __future__ import annotations

import io
import struct
import sys
import time
import zlib
from pathlib import Path

import requests

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import PDS1, ScenarioResult, XrpcClient, get_character, timed_call


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _make_png(width: int, height: int, color: tuple[int, int, int]) -> bytes:
    try:
        from PIL import Image

        img = Image.new("RGB", (width, height), color=color)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()
    except ImportError:
        def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
            chunk = chunk_type + data
            crc = struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
            return struct.pack(">I", len(data)) + chunk + crc

        signature = b"\x89PNG\r\n\x1a\n"
        ihdr = _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        row = bytes([0]) + bytes(color) * width
        raw = row * height
        idat = _png_chunk(b"IDAT", zlib.compress(raw))
        iend = _png_chunk(b"IEND", b"")
        return signature + ihdr + idat + iend


def _blob_cid(response: dict | None) -> str:
    if not isinstance(response, dict):
        return ""
    blob = response.get("blob")
    if not isinstance(blob, dict):
        return ""
    for key in ("cid", "$link"):
        value = blob.get(key)
        if isinstance(value, str) and value:
            return value
    ref = blob.get("ref")
    if isinstance(ref, dict):
        for key in ("$link", "cid"):
            value = ref.get(key)
            if isinstance(value, str) and value:
                return value
    return ""


def _blob_url(did: str, cid: str) -> str:
    return f"{PDS1}/xrpc/com.atproto.sync.getBlob?did={did}&cid={cid}"


def _wait_for_blob_status(url: str, expected_status: int, timeout_s: int = 15) -> requests.Response:
    deadline = time.time() + timeout_s
    last_response: requests.Response | None = None
    while time.time() < deadline:
        last_response = requests.get(url, timeout=10)
        if last_response.status_code == expected_status:
            return last_response
        time.sleep(1)
    raise RuntimeError(
        f"Blob never reached HTTP {expected_status}; last_status={getattr(last_response, 'status_code', 'n/a')}"
    )


def run() -> ScenarioResult:
    result = ScenarioResult("The Blob Janitor")
    result.start()

    pds = XrpcClient(PDS1)
    luna = get_character("luna")

    timed_call(result, "Wake the PDS", lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    luna_session = timed_call(
        result,
        "Luna opens a workbench account",
        lambda: pds.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if luna_session:
        luna.did = luna_session["did"]
        luna.access_jwt = luna_session["accessJwt"]

    if not luna.did or not luna.access_jwt:
        result.step_failed("Account setup", "Luna account creation failed")
        result.finish()
        return result

    keep_blob = timed_call(
        result,
        "Luna uploads the keep-alive snapshot",
        lambda: pds.blobs.upload_blob(_make_png(128, 128, (80, 180, 120)), "image/png", luna.access_jwt),
        detail_fn=lambda r: f"cid={_blob_cid(r)}",
    )
    doomed_blob = timed_call(
        result,
        "Luna uploads the doomed snapshot",
        lambda: pds.blobs.upload_blob(_make_png(128, 128, (210, 80, 90)), "image/png", luna.access_jwt),
        detail_fn=lambda r: f"cid={_blob_cid(r)}",
    )

    keep_cid = _blob_cid(keep_blob)
    doomed_cid = _blob_cid(doomed_blob)
    if not keep_cid or not doomed_cid:
        result.step_failed("Blob upload", "Missing blob CID for keep or doomed snapshot")
        result.finish()
        return result

    keep_post = timed_call(
        result,
        "Luna writes the post that stays",
        lambda: pds.records.create_record(
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "A small sign that this blob is meant to live on.",
                "createdAt": _now(),
                "embed": {
                    "$type": "app.bsky.embed.images",
                    "images": [
                        {"alt": "A calm green snapshot", "image": keep_blob["blob"]},
                    ],
                },
            },
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r['uri']}",
    )
    doomed_post = timed_call(
        result,
        "Luna writes the post that will be cleaned up",
        lambda: pds.records.create_record(
            luna.did,
            "app.bsky.feed.post",
            {
                "$type": "app.bsky.feed.post",
                "text": "This one gets deleted to free its blob.",
                "createdAt": _now(),
                "embed": {
                    "$type": "app.bsky.embed.images",
                    "images": [
                        {"alt": "A red snapshot destined for deletion", "image": doomed_blob["blob"]},
                    ],
                },
            },
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    if not keep_post or not doomed_post:
        result.step_failed("Post creation", "Could not create the keep or doomed post")
        result.finish()
        return result

    doomed_rkey = doomed_post["uri"].rsplit("/", 1)[-1]
    timed_call(
        result,
        "Luna deletes the doomed post",
        lambda: pds.records.delete_record(
            luna.did,
            "app.bsky.feed.post",
            doomed_rkey,
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"deleted={r.get('success', True)}",
    )

    timed_call(
        result,
        "Luna runs the blob janitor on the orphan",
        lambda: pds.raw.xrpc_post(
            "com.atproto.repo.deleteBlob",
            {"blob": doomed_cid},
            token=luna.access_jwt,
        ),
        detail_fn=lambda r: f"success={r.get('success', False)}",
    )

    doomed_url = _blob_url(luna.did, doomed_cid)
    keep_url = _blob_url(luna.did, keep_cid)

    doomed_fetch = timed_call(
        result,
        "The doomed blob now returns 404",
        lambda: _wait_for_blob_status(doomed_url, 404),
        detail_fn=lambda r: f"status={r.status_code}",
    )
    if doomed_fetch and doomed_fetch.status_code != 404:
        result.step_failed("The doomed blob now returns 404", f"status={doomed_fetch.status_code}")

    keep_fetch = timed_call(
        result,
        "The keep-alive blob still downloads",
        lambda: _wait_for_blob_status(keep_url, 200),
        detail_fn=lambda r: f"status={r.status_code} bytes={len(r.content)}",
    )
    if keep_fetch and keep_fetch.status_code != 200:
        result.step_failed("The keep-alive blob still downloads", f"status={keep_fetch.status_code}")

    result.record_artifact(
        "blob_cids",
        {
            "keep": keep_cid,
            "doomed": doomed_cid,
        },
    )
    result.record_artifact(
        "posts",
        {
            "keep_uri": keep_post["uri"],
            "doomed_uri": doomed_post["uri"],
        },
    )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
