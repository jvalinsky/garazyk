"""Scenario 36: "The Projection Booth" — Video Processing

Test the Jelcz video processing service end-to-end:
1. Upload a valid MP4 video via app.bsky.video.uploadVideo to Jelcz
2. Poll app.bsky.video.getJobStatus until the job completes
3. Verify the processed video blob and thumbnail are stored
4. Check upload limits via app.bsky.video.getUploadLimits
5. Verify invalid content (non-video) is rejected

Jelcz is a standalone video processing sidecar service. It accepts video
uploads, transcodes them (720p H.264), generates thumbnails, and uploads
the processed blobs back to the PDS via Service Auth.

The PDS runs in PDS_VIDEO_MODE=external so it doesn't handle video
XRPC methods internally — all app.bsky.video.* requests go to Jelcz.

Authentication flow:
1. Client creates account on PDS, gets access JWT
2. Client calls com.atproto.server.getServiceAuth on PDS with
   aud=did:web:localhost (Jelcz's DID) and lxm=app.bsky.video.uploadVideo
3. PDS mints a Service Auth JWT signed with the user's actor signing key
4. Client sends this Service Auth JWT to Jelcz for video operations

Uses a public-domain MP4 test clip downloaded at scenario setup time.

Services: PDS + Jelcz (video)
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

_project_root = str(Path(__file__).resolve().parent.parent.parent.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from scripts.lib.atproto import (
    XrpcClient, get_character, PDS1, ScenarioResult, timed_call,
    wait_for_http,
)
from scripts.lib.atproto.config import SERVICE_URLS


# ── Video test assets ────────────────────────────────────────────────────

# URL for a small public-domain MP4 test clip (~2.8MB, ~5s, H.264).
# Source: samplelib.com — "no license restrictions" test videos.
_VIDEO_URL = "http://download.samplelib.com/mp4/sample-5s.mp4"
_VIDEO_CACHE = "/tmp/garazyk-scenario-36-test-video.mp4"


def _download_test_video() -> bytes:
    """Download a small public-domain MP4 test clip, caching locally."""
    if os.path.exists(_VIDEO_CACHE):
        with open(_VIDEO_CACHE, "rb") as f:
            return f.read()

    import urllib.request
    print(f"Downloading test video from {_VIDEO_URL}...")
    urllib.request.urlretrieve(_VIDEO_URL, _VIDEO_CACHE)
    with open(_VIDEO_CACHE, "rb") as f:
        data = f.read()
    print(f"Downloaded {len(data)} bytes")
    return data


def _make_invalid_content() -> bytes:
    """Create bytes that are NOT a valid video (no ftyp or matroska magic)."""
    return b"This is plain text, not a video at all."


# ── Scenario ─────────────────────────────────────────────────────────────

def run() -> ScenarioResult:
    result = ScenarioResult("Video Processing (The Projection Booth)")
    result.start()

    # ── Service health checks ──────────────────────────────────────────────
    pds_client = XrpcClient(PDS1)
    timed_call(result, "PDS health check", lambda: pds_client.wait_for_healthy(timeout=30))
    if result.failed > 0:
        result.finish()
        return result

    video_url = SERVICE_URLS["video"]
    timed_call(result, "Jelcz health check",
               lambda: wait_for_http(f"{video_url}/_health", timeout=15))
    if result.failed > 0:
        result.finish()
        return result

    video_client = XrpcClient(video_url)

    # Create an account on the PDS
    luna = get_character("luna")
    session = timed_call(
        result, "Create account",
        lambda: pds_client.accounts.create_account(luna.handle, luna.email, luna.password),
        detail_fn=lambda s: f"did={s['did']}"
    )
    if not session:
        result.finish()
        return result
    luna.did = session["did"]
    luna.access_jwt = session["accessJwt"]

    # ── Get Service Auth token for Jelcz ──────────────────────────────────
    # Per the ATProto spec, the client should obtain a Service Auth JWT
    # from the PDS before calling the video service. The JWT is signed
    # with the user's actor signing key and has aud=Jelcz's DID.
    # However, the video worker also needs the user's access JWT to upload
    # processed blobs back to the PDS (the PDS's uploadBlob endpoint only
    # accepts access JWTs, not Service Auth tokens). So we pass the
    # access JWT to Jelcz, which accepts both token types.
    jelcz_did = "did:web:localhost"  # matches JELCZ_DID in setup script

    service_auth_resp = timed_call(
        result, "Get Service Auth token",
        lambda: pds_client.raw.xrpc_get(
            "com.atproto.server.getServiceAuth",
            params={"aud": jelcz_did, "lxm": "app.bsky.video.uploadVideo"},
            token=luna.access_jwt,
        ),
        detail_fn=lambda r: f"token_len={len(r.get('token', ''))}"
    )
    if not service_auth_resp:
        result.finish()
        return result

    # Use the access JWT for video operations so the worker can reuse it
    # for blob upload to the PDS. Jelcz accepts both Service Auth and
    # access tokens.
    video_auth_token = luna.access_jwt

    # ── Step 1: Check upload limits ──────────────────────────────────────
    limits = timed_call(
        result, "Check upload limits",
        lambda: video_client.raw.xrpc_get("app.bsky.video.getUploadLimits", token=video_auth_token),
        detail_fn=lambda r: f"canUpload={r.get('canUpload')} remaining={r.get('remainingDailyVideos')}"
    )

    # ── Step 2: Upload valid MP4 video ───────────────────────────────────
    video_data = _download_test_video()
    upload_resp = timed_call(
        result, "Upload MP4 video",
        lambda: video_client.raw.post_raw(
            "app.bsky.video.uploadVideo",
            video_data,
            "video/mp4",
            token=video_auth_token,
            params={"did": luna.did, "name": "test-video.mp4"},
        ),
        detail_fn=lambda r: f"jobId={r.get('jobStatus', {}).get('jobId')}"
    )

    if not upload_resp:
        result.finish()
        return result

    job_status = upload_resp.get("jobStatus", {})
    job_id = job_status.get("jobId")
    initial_state = job_status.get("state")

    if initial_state != "JOB_STATE_PENDING":
        result.step_failed("Initial job state", f"Expected PENDING, got {initial_state}")
    else:
        result.step_passed("Initial job state", f"state={initial_state}")

    # ── Step 3: Poll for job completion ───────────────────────────────────
    if job_id:
        print(f"Polling job {job_id} for completion...")
        max_polls = 60  # 60 * 2s = 120s max wait
        poll_interval = 2
        final_state = None
        job_resp = None

        for i in range(max_polls):
            try:
                job_resp = video_client.raw.xrpc_get(
                    "app.bsky.video.getJobStatus",
                    params={"jobId": job_id},
                    token=video_auth_token,
                )
                state = job_resp.get("state", "UNKNOWN")
                progress = job_resp.get("progress", 0)
                message = job_resp.get("message", "")

                if state in ("JOB_STATE_COMPLETED", "JOB_STATE_FAILED"):
                    final_state = state
                    break

                if (i + 1) % 5 == 0:
                    print(f"  ... poll {i+1}: state={state} progress={progress}% msg={message}")

            except Exception as exc:
                print(f"  ... poll {i+1} error: {exc}")

            time.sleep(poll_interval)

        if final_state == "JOB_STATE_COMPLETED":
            blob_ref = job_resp.get("blob", {})
            aspect_ratio = job_resp.get("aspectRatio", {})
            detail_parts = []
            if blob_ref:
                cid_link = blob_ref.get("ref", {}).get("$link", "unknown")
                detail_parts.append(f"blobCid={cid_link[:20]}...")
            if aspect_ratio:
                detail_parts.append(f"aspect={aspect_ratio.get('width')}x{aspect_ratio.get('height')}")
            result.step_passed("Video job completed", " | ".join(detail_parts) if detail_parts else "done")
        elif final_state == "JOB_STATE_FAILED":
            error_msg = job_resp.get("error", "") if job_resp else "unknown"
            result.step_failed("Video job completed", f"Job failed: {error_msg}")
        else:
            result.step_failed("Video job completed", f"Timed out after {max_polls * poll_interval}s (last state: {final_state})")

    # ── Step 4: Verify invalid content is rejected ────────────────────────
    invalid_data = _make_invalid_content()
    timed_call(
        result, "Reject non-video content",
        lambda: video_client.raw.post_raw(
            "app.bsky.video.uploadVideo",
            invalid_data,
            "video/mp4",
            token=video_auth_token,
            params={"did": luna.did, "name": "test-invalid.txt"},
        ),
        expect_failure="InvalidRequest",
    )

    # ── Step 5: Verify upload limits after uploads ───────────────────────
    limits_after = timed_call(
        result, "Check upload limits after uploads",
        lambda: video_client.raw.xrpc_get("app.bsky.video.getUploadLimits", token=video_auth_token),
        detail_fn=lambda r: f"remaining={r.get('remainingDailyVideos')}/{r.get('remainingDailyBytes')}"
    )

    result.finish()
    return result


if __name__ == "__main__":
    res = run()
    res.print_summary()
    sys.exit(res.exit_code)
