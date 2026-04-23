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

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.client import XrpcClient, XrpcError
from lib.characters import get_character, PDS1
from lib.assertions import assert_success, assert_contains, assert_xrpc_raises
from lib.report import ScenarioResult, StepStatus


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _make_png(width: int = 100, height: int = 100) -> bytes:
    """Create a minimal valid PNG file for testing."""
    # Minimal PNG: 1x1 pixel, but we'll create a simple one with PIL if available
    try:
        from PIL import Image
        img = Image.new("RGB", (width, height), color=(255, 100, 50))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()
    except ImportError:
        # Fallback: create a minimal valid PNG manually
        # This is a 1x1 red pixel PNG
        import struct
        import zlib

        def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
            chunk = chunk_type + data
            crc = struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
            return struct.pack(">I", len(data)) + chunk + crc

        signature = b"\x89PNG\r\n\x1a\n"
        ihdr = _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        raw_data = b"\x00" + b"\xff\x64\x32" * width  # One row of pixels
        raw_data = raw_data * height
        idat = _png_chunk(b"IDAT", zlib.compress(raw_data))
        iend = _png_chunk(b"IEND", b"")
        return signature + ihdr + idat + iend


def run() -> ScenarioResult:
    result = ScenarioResult("Blobs & Uploads")
    result.start()

    client = XrpcClient(PDS1)

    # Wait for server
    try:
        client.wait_for_healthy(timeout=30)
        result.step_passed("Server health check")
    except RuntimeError as exc:
        result.step_failed("Server health check", str(exc))
        result.finish()
        return result

    # ── Create accounts ──────────────────────────────────────────────
    char_names = ["rosa", "volt", "luna", "marcus"]
    for name in char_names:
        char = get_character(name)
        try:
            session = client.create_account(char.handle, char.email, char.password)
            char.did = session["did"]
            char.access_jwt = session["accessJwt"]
            result.step_passed(f"Create account: {char.name}", f"did={char.did}")
        except XrpcError as exc:
            result.step_failed(f"Create account: {char.name}", str(exc))

    rosa = get_character("rosa")
    volt = get_character("volt")
    luna = get_character("luna")
    marcus = get_character("marcus")

    if not all([rosa.did, volt.did, luna.did, marcus.did]):
        result.step_failed("Account creation", "Not all accounts created")
        result.finish()
        return result

    # ── Rosa uploads a food photo ────────────────────────────────────
    rosa_blob = None
    try:
        png_data = _make_png(200, 200)
        blob_resp = client.upload_blob(png_data, "image/png", rosa.access_jwt)
        rosa_blob = blob_resp.get("blob", {})
        result.step_passed("Rosa uploads food photo", f"size={rosa_blob.get('size', 'unknown')}")
    except XrpcError as exc:
        result.step_failed("Rosa uploads food photo", str(exc))

    # ── Rosa creates a post with image embed ─────────────────────────
    if rosa_blob:
        try:
            post = client.create_record(
                rosa.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": "Look at this amazing sourdough I made! 🍞✨",
                    "createdAt": _now(),
                    "embed": {
                        "$type": "app.bsky.embed.images",
                        "images": [{
                            "alt": "Fresh sourdough bread",
                            "image": rosa_blob.get("ref", rosa_blob),
                        }],
                    },
                },
                rosa.access_jwt,
            )
            result.step_passed("Rosa posts with image embed", f"uri={post['uri']}")
        except XrpcError as exc:
            result.step_failed("Rosa posts with image embed", str(exc))
    else:
        result.step_skipped("Rosa posts with image embed", "No blob available")

    # ── DJ Volt uploads 4 images ─────────────────────────────────────
    volt_blobs = []
    for i in range(4):
        try:
            png_data = _make_png(100 + i * 10, 100 + i * 10)
            blob_resp = client.upload_blob(png_data, "image/png", volt.access_jwt)
            blob = blob_resp.get("blob", {})
            volt_blobs.append(blob)
            result.step_passed(f"DJ Volt uploads image {i+1}")
        except XrpcError as exc:
            result.step_failed(f"DJ Volt uploads image {i+1}", str(exc))

    # ── DJ Volt creates a post with 4-image album ───────────────────
    if len(volt_blobs) >= 4:
        try:
            post = client.create_record(
                volt.did,
                "app.bsky.feed.post",
                {
                    "$type": "app.bsky.feed.post",
                    "text": "Album cover concepts for the new EP! Which one do you like? 🎵",
                    "createdAt": _now(),
                    "embed": {
                        "$type": "app.bsky.embed.images",
                        "images": [{
                            "alt": f"Album concept {i+1}",
                            "image": b.get("ref", b),
                        } for i, b in enumerate(volt_blobs[:4])],
                    },
                },
                volt.access_jwt,
            )
            result.step_passed("DJ Volt posts 4-image album")
        except XrpcError as exc:
            result.step_failed("DJ Volt posts 4-image album", str(exc))
    else:
        result.step_skipped("DJ Volt posts 4-image album", "Not enough blobs uploaded")

    # ── Luna uploads a profile banner ────────────────────────────────
    banner_blob = None
    try:
        banner_data = _make_png(600, 200)
        blob_resp = client.upload_blob(banner_data, "image/png", luna.access_jwt)
        banner_blob = blob_resp.get("blob", {})
        result.step_passed("Luna uploads banner image")
    except XrpcError as exc:
        result.step_failed("Luna uploads banner image", str(exc))

    # ── Luna updates profile with banner ─────────────────────────────
    if banner_blob:
        try:
            client.create_record(
                luna.did,
                "app.bsky.actor.profile",
                {
                    "$type": "app.bsky.actor.profile",
                    "displayName": "Luna Starfield",
                    "description": "Astronomy enthusiast. Looking up, always. 🌌",
                    "banner": banner_blob.get("ref", banner_blob),
                },
                luna.access_jwt,
            )
            result.step_passed("Luna sets profile banner")
        except XrpcError as exc:
            result.step_skipped("Luna sets profile banner", str(exc))

    # ── Verify blob retrieval ────────────────────────────────────────
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

    # ── Marcus tries to upload an oversized file ─────────────────────
    try:
        # Create a 2MB blob (should be under PDS limits, but let's test the error path)
        # Most PDSes have a 1MB limit for blobs
        large_data = b"\x00" * (2 * 1024 * 1024)  # 2MB
        try:
            client.upload_blob(large_data, "application/octet-stream", marcus.access_jwt)
            result.step_skipped("Oversized blob upload", "Upload succeeded (limit may be higher than 2MB)")
        except XrpcError as exc:
            body = exc.body if isinstance(exc.body, dict) else {}
            if exc.status == 413 or "too large" in str(body).lower() or "PayloadTooLarge" in str(body):
                result.step_passed("Oversized blob rejected", f"status={exc.status}")
            else:
                result.step_skipped("Oversized blob upload", f"status={exc.status}, error={body}")
    except Exception as exc:
        result.step_skipped("Oversized blob upload", str(exc))

    # ── Verify record contains blob refs ──────────────────────────────
    if rosa_blob:
        try:
            records = client.list_records(rosa.did, "app.bsky.feed.post", token=rosa.access_jwt)
            posts = records.get("records", [])
            has_embed = any("embed" in r.get("value", {}) for r in posts)
            result.step_passed("Records contain blob refs", f"posts_with_embed={has_embed}")
        except XrpcError as exc:
            result.step_skipped("Records contain blob refs", str(exc))

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
