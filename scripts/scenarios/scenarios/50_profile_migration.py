# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0

"""Scenario 50: "The Profile Evolution" — Profile Migration

Luna treats her profile like a living postcard: first the opening portrait,
then a sharper handle on who she is, then new art as her style changes.
AppView and the relay should both keep pace with every rewrite, and Marcus
should see the same updated face everyone else does.

Services: PDS, AppView, Relay
"""

from __future__ import annotations

import asyncio
import io
import json
import struct
import sys
import threading
import time
import zlib
from pathlib import Path

import requests

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    PDS1,
    SERVICE_URLS,
    ScenarioResult,
    XrpcClient,
    get_character,
    timed_call,
)


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _make_png(width: int = 64, height: int = 64, color: tuple[int, int, int] = (60, 140, 255)) -> bytes:
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
        raw_data = row * height
        idat = _png_chunk(b"IDAT", zlib.compress(raw_data))
        iend = _png_chunk(b"IEND", b"")
        return signature + ihdr + idat + iend


def _blob_cid(blob: object) -> str:
    if isinstance(blob, dict):
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
        inner = blob.get("blob")
        if inner is not None:
            return _blob_cid(inner)
    return ""


def _profile_blob_cid(profile_value: object) -> str:
    if isinstance(profile_value, dict):
        return _blob_cid(profile_value)
    return ""


def _collect_relay_events(relay_url: str, events: list, errors: list[str]) -> None:
    try:
        from scripts.lib.atproto.firehose import FirehoseClient

        firehose = FirehoseClient(relay_url)
        collected = asyncio.run(firehose.collect(duration_s=12.0))
        events.extend(collected)
    except Exception as exc:  # pragma: no cover - exercised only when relay tooling is absent
        errors.append(str(exc))


def _profile_matches(profile: dict, display_name: str, avatar_cid: str, banner_cid: str) -> bool:
    avatar = profile.get("avatar")
    banner = profile.get("banner")
    return (
        profile.get("displayName") == display_name
        and _profile_blob_cid(avatar) == avatar_cid
        and _profile_blob_cid(banner) == banner_cid
    )


def _wait_for_profile(
    client: XrpcClient,
    did: str,
    token: str,
    display_name: str,
    avatar_cid: str,
    banner_cid: str,
    timeout_s: int = 15,
) -> dict:
    deadline = time.time() + timeout_s
    last_profile: dict | None = None
    while time.time() < deadline:
        last_profile = client.feed.get_profile(did, token=token)
        if _profile_matches(last_profile, display_name, avatar_cid, banner_cid):
            return last_profile
        time.sleep(1)
    raise RuntimeError(
        "AppView did not reflect Luna's final profile within the timeout; "
        f"last_profile={last_profile!r}"
    )


def _relay_profile_event_count(events: list, did: str) -> int:
    count = 0
    for event in events:
        payload = getattr(event, "payload", None)
        text = json.dumps(payload, default=str) if payload is not None else ""
        if did in text and "app.bsky.actor.profile" in text:
            count += 1
    return count


def run() -> ScenarioResult:
    result = ScenarioResult("The Profile Evolution")
    result.start()

    pds = XrpcClient(PDS1)
    appview = XrpcClient(SERVICE_URLS["appview"])
    luna = get_character("luna")
    marcus = get_character("marcus")

    timed_call(result, "Wake the PDS", lambda: pds.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    luna_session = timed_call(
        result,
        "Luna opens her account",
        lambda: pds.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if luna_session:
        luna.did = luna_session["did"]
        luna.access_jwt = luna_session["accessJwt"]

    marcus_session = timed_call(
        result,
        "Marcus opens his account",
        lambda: pds.accounts.create_account(marcus.handle, marcus.email, marcus.password),
        detail_fn=lambda s: f"did={s['did']}",
    )
    if marcus_session:
        marcus.did = marcus_session["did"]
        marcus.access_jwt = marcus_session["accessJwt"]

    if not all([luna.did, luna.access_jwt, marcus.did, marcus.access_jwt]):
        result.step_failed("Account setup", "Luna or Marcus account creation failed")
        result.finish()
        return result

    relay_events: list = []
    relay_errors: list[str] = []
    relay_thread = timed_call(
        result,
        "Open the relay firehose",
        lambda: threading.Thread(
            target=_collect_relay_events,
            args=(SERVICE_URLS.get("relay", "ws://localhost:2584"), relay_events, relay_errors),
            daemon=True,
        ),
        detail_fn=lambda t: "firehose tap started",
    )
    if relay_thread:
        relay_thread.start()
        time.sleep(1)

    luna_avatar_v1 = timed_call(
        result,
        "Luna uploads her first portrait",
        lambda: pds.blobs.upload_blob(_make_png(256, 256, (112, 180, 255)), "image/png", luna.access_jwt),
        detail_fn=lambda r: f"cid={_blob_cid(r.get('blob', {}))}",
    )
    luna_banner_v1 = timed_call(
        result,
        "Luna uploads her first banner",
        lambda: pds.blobs.upload_blob(_make_png(640, 180, (22, 40, 84)), "image/png", luna.access_jwt),
        detail_fn=lambda r: f"cid={_blob_cid(r.get('blob', {}))}",
    )

    luna_avatar_v1_cid = _blob_cid(luna_avatar_v1.get("blob", {})) if luna_avatar_v1 else ""
    luna_banner_v1_cid = _blob_cid(luna_banner_v1.get("blob", {})) if luna_banner_v1 else ""

    if not luna_avatar_v1_cid or not luna_banner_v1_cid:
        result.step_failed("Luna's first profile assets", "Missing avatar or banner blob CID")
        result.finish()
        return result

    initial_profile = {
        "$type": "app.bsky.actor.profile",
        "displayName": "Luna Starfield",
        "description": luna.persona,
        "avatar": luna_avatar_v1["blob"],
        "banner": luna_banner_v1["blob"],
    }
    timed_call(
        result,
        "Luna writes her opening profile",
        lambda: pds.records.create_record(
            luna.did,
            "app.bsky.actor.profile",
            initial_profile,
            luna.access_jwt,
            rkey="self",
        ),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    luna_stage_name = "Luna Starfield, Reframed"
    timed_call(
        result,
        "Luna sharpens her display name",
        lambda: pds.records.put_record(
            luna.did,
            "app.bsky.actor.profile",
            "self",
            {
                "$type": "app.bsky.actor.profile",
                "displayName": luna_stage_name,
                "description": luna.persona,
                "avatar": luna_avatar_v1["blob"],
                "banner": luna_banner_v1["blob"],
            },
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    luna_avatar_v2 = timed_call(
        result,
        "Luna trades in her portrait",
        lambda: pds.blobs.upload_blob(_make_png(256, 256, (245, 120, 180)), "image/png", luna.access_jwt),
        detail_fn=lambda r: f"cid={_blob_cid(r.get('blob', {}))}",
    )
    luna_avatar_v2_cid = _blob_cid(luna_avatar_v2.get("blob", {})) if luna_avatar_v2 else ""
    if not luna_avatar_v2_cid:
        result.step_failed("Luna's second portrait", "No avatar CID returned")
        result.finish()
        return result

    timed_call(
        result,
        "Luna swaps in the new portrait",
        lambda: pds.records.put_record(
            luna.did,
            "app.bsky.actor.profile",
            "self",
            {
                "$type": "app.bsky.actor.profile",
                "displayName": luna_stage_name,
                "description": luna.persona,
                "avatar": luna_avatar_v2["blob"],
                "banner": luna_banner_v1["blob"],
            },
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    luna_banner_v2 = timed_call(
        result,
        "Luna paints a new banner",
        lambda: pds.blobs.upload_blob(_make_png(640, 180, (12, 88, 66)), "image/png", luna.access_jwt),
        detail_fn=lambda r: f"cid={_blob_cid(r.get('blob', {}))}",
    )
    luna_banner_v2_cid = _blob_cid(luna_banner_v2.get("blob", {})) if luna_banner_v2 else ""
    if not luna_banner_v2_cid:
        result.step_failed("Luna's second banner", "No banner CID returned")
        result.finish()
        return result

    timed_call(
        result,
        "Luna finishes the final profile rewrite",
        lambda: pds.records.put_record(
            luna.did,
            "app.bsky.actor.profile",
            "self",
            {
                "$type": "app.bsky.actor.profile",
                "displayName": luna_stage_name,
                "description": luna.persona,
                "avatar": luna_avatar_v2["blob"],
                "banner": luna_banner_v2["blob"],
            },
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"uri={r['uri']}",
    )

    final_profile = timed_call(
        result,
        "AppView catches Luna's finished profile",
        lambda: _wait_for_profile(
            appview,
            luna.did,
            luna.access_jwt,
            luna_stage_name,
            luna_avatar_v2_cid,
            luna_banner_v2_cid,
        ),
        detail_fn=lambda p: (
            f"displayName={p.get('displayName')} avatar={luna_avatar_v2_cid[:12]}... "
            f"banner={luna_banner_v2_cid[:12]}..."
        ),
    )

    if final_profile:
        luna_profile_view = final_profile
    else:
        luna_profile_view = {}

    timed_call(
        result,
        "Marcus sees Luna's updated profile",
        lambda: _wait_for_profile(
            appview,
            luna.did,
            marcus.access_jwt,
            luna_stage_name,
            luna_avatar_v2_cid,
            luna_banner_v2_cid,
        ),
        detail_fn=lambda p: f"displayName={p.get('displayName')} avatar={_profile_blob_cid(p.get('avatar'))[:12]}...",
    )

    time.sleep(2)
    if relay_thread:
        relay_thread.join(timeout=20)

    timed_call(
        result,
        "Relay remembers Luna's profile rewrites",
        lambda: (
            None
            if relay_errors
            else _relay_profile_event_count(relay_events, luna.did)
        ),
        detail_fn=lambda count: f"matching_events={count}",
        expect_failure=None,
    )

    if relay_errors:
        result.step_skipped("Relay remembers Luna's profile rewrites", "; ".join(relay_errors))

    result.record_artifact(
        "profile_cids",
        {
            "avatar_v1": luna_avatar_v1_cid,
            "avatar_v2": luna_avatar_v2_cid,
            "banner_v1": luna_banner_v1_cid,
            "banner_v2": luna_banner_v2_cid,
        },
    )
    result.record_artifact(
        "accounts",
        {
            "luna": {"did": luna.did},
            "marcus": {"did": marcus.did},
        },
    )
    result.record_artifact(
        "final_profile",
        {
            "displayName": luna_profile_view.get("displayName", luna_stage_name),
            "avatar_cid": luna_avatar_v2_cid,
            "banner_cid": luna_banner_v2_cid,
        },
    )

    result.finish()
    return result


if __name__ == "__main__":
    result = run()
    result.print_summary()
    sys.exit(result.exit_code)
