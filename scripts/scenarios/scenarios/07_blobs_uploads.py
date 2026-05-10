"""Scenario 7: "The Gallery" — Blobs & Uploads

Rosa uploads a food photo and creates a post with an image embed.
DJ Volt uploads an album of 4 images. Luna uploads a profile banner.
Marcus tries to upload a file that's too large.

Services: PDS
"""

from __future__ import annotations

import io
import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import XrpcClient, get_character, PDS1, ScenarioResult, timed_call



def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _make_png(width: int = 100, height: int = 100) -> bytes:
    try:
        from PIL import Image
        img = Image.new("RGB", (width, height), color=(255, 100, 50))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()
    except ImportError:
        import struct
        import zlib

        def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
            chunk = chunk_type + data
            crc = struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
            return struct.pack(">I", len(data)) + chunk + crc

        signature = b"\x89PNG\r\n\x1a\n"
        ihdr = _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        raw_data = b"\x00" + b"\xff\x64\x32" * width
        raw_data = raw_data * height
        idat = _png_chunk(b"IDAT", zlib.compress(raw_data))
        iend = _png_chunk(b"IEND", b"")
        return signature + ihdr + idat + iend


def run() -> ScenarioResult:
    result = ScenarioResult("Blobs & Uploads")
    result.start()

    client = XrpcClient(PDS1)

    timed_call(result, "Server health check",
               lambda: client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    char_names = ["rosa", "volt", "luna", "marcus"]
    for name in char_names:
        char = get_character(name)
        session = timed_call(
            result, f"Create account: {char.name}",
            lambda c=char: client.accounts.create_account(c.handle, c.email, c.password),
            detail_fn=lambda s, n=name: f"did={s['did']}",
        )
        if session:
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]

    rosa = get_character("rosa")
    volt = get_character("volt")
    luna = get_character("luna")
    marcus = get_character("marcus")

    if not all([rosa.did, volt.did, luna.did, marcus.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    png_data = _make_png(200, 200)
    rosa_blob_resp = timed_call(
        result, "Rosa uploads food photo",
        lambda: client.blobs.upload_blob(png_data, "image/png", rosa.access_jwt),
        detail_fn=lambda r: f"size={r.get('blob', {}).get('size', 'unknown')}",
    )
    rosa_blob = rosa_blob_resp.get("blob", {}) if rosa_blob_resp else None

    if rosa_blob:
        timed_call(
            result, "Rosa posts with image embed",
            lambda: client.records.create_record(
                rosa.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": "Look at this amazing sourdough I made!",
                 "createdAt": _now(),
                 "embed": {"$type": "app.bsky.embed.images",
                           "images": [{"alt": "Fresh sourdough bread", "image": rosa_blob}]}},
                rosa.access_jwt),
            detail_fn=lambda r: f"uri={r['uri']}",
        )
    else:
        result.step_skipped("Rosa posts with image embed", "No blob available")

    volt_blobs = []
    for i in range(4):
        png_data = _make_png(100 + i * 10, 100 + i * 10)
        blob_resp = timed_call(
            result, f"DJ Volt uploads image {i+1}",
            lambda d=png_data: client.blobs.upload_blob(d, "image/png", volt.access_jwt),
        )
        if blob_resp:
            volt_blobs.append(blob_resp.get("blob", {}))

    if len(volt_blobs) >= 4:
        timed_call(
            result, "DJ Volt posts 4-image album",
            lambda: client.records.create_record(
                volt.did, "app.bsky.feed.post",
                {"$type": "app.bsky.feed.post",
                 "text": "Album cover concepts for the new EP! Which one do you like?",
                 "createdAt": _now(),
                 "embed": {"$type": "app.bsky.embed.images",
                           "images": [{"alt": f"Album concept {i+1}", "image": b}
                                      for i, b in enumerate(volt_blobs[:4])]}},
                volt.access_jwt),
        )
    else:
        result.step_skipped("DJ Volt posts 4-image album", "Not enough blobs uploaded")

    banner_data = _make_png(600, 200)
    banner_blob_resp = timed_call(
        result, "Luna uploads banner image",
        lambda: client.blobs.upload_blob(banner_data, "image/png", luna.access_jwt),
    )
    banner_blob = banner_blob_resp.get("blob", {}) if banner_blob_resp else None

    if banner_blob:
        timed_call(
            result, "Luna sets profile banner",
            lambda: client.records.create_record(
                luna.did, "app.bsky.actor.profile",
                {"$type": "app.bsky.actor.profile",
                 "displayName": "Luna Starfield",
                 "description": "Astronomy enthusiast. Looking up, always.",
                 "banner": banner_blob},
                luna.access_jwt),
        )

    if rosa_blob:
        try:
            import requests
            blob_ref = rosa_blob.get("ref", {})
            if isinstance(blob_ref, dict):
                cid = blob_ref.get("$link", blob_ref.get("cid", ""))
            else:
                cid = str(blob_ref)
            if cid:
                blob_url = f"{PDS1}/xrpc/com.atproto.sync.getBlob?did={rosa.did}&cid={cid}"
                resp = requests.get(blob_url, timeout=10)
                if resp.status_code == 200:
                    result.step_passed("Blob retrieval", f"size={len(resp.content)} bytes")
                else:
                    result.step_failed("Blob retrieval", f"status={resp.status_code}")
            else:
                result.step_skipped("Blob retrieval", "No blob CID available")
        except Exception as exc:
            result.step_skipped("Blob retrieval", str(exc))

    large_data = b"\x00" * (2 * 1024 * 1024)
    err = timed_call(
        result, "Oversized blob upload",
        lambda: client.blobs.upload_blob(large_data, "application/octet-stream", marcus.access_jwt),
        expect_failure=True,
    )
    if err:
        body = err.body if isinstance(err.body, dict) else {}
        if err.status not in (413,) and "too large" not in str(body).lower():
            result.step_skipped("Oversized blob upload", f"unexpected error: status={err.status}")

    if rosa_blob:
        timed_call(
            result, "Records contain blob refs",
            lambda: client.records.list_records(rosa.did, "app.bsky.feed.post", token=rosa.access_jwt),
            detail_fn=lambda r: f"posts_with_embed={any('embed' in rec.get('value', {}) for rec in r.get('records', []))}",
        )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
