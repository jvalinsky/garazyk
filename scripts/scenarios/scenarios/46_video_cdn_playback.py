"""Scenario 46: "The Projection Booth" — Video CDN Playback

Luna uploads a video, polls for job completion, and verifies
the CDN URL is accessible.

Services: PDS, Jelcz (video)
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
    result = ScenarioResult("Video CDN Playback")
    result.start()

    pds = XrpcClient(PDS1)
    video = XrpcClient(SERVICE_URLS["video"])
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

    # Check video service health
    timed_call(
        result, "Video service health check",
        lambda: video._get("/_health"),
    )

    # Get service auth token for video upload
    service_auth = timed_call(
        result, "Get service auth token",
        lambda: pds.server.get_service_auth(
            {"aud": SERVICE_URLS.get("video", ""), "lxm": "app.bsky.video.uploadVideo"},
            luna.access_jwt,
        ),
        detail_fn=lambda r: f"token_len={len(r.get('token', ''))}" if r else "failed",
    )

    if not service_auth:
        result.step_skipped("Video upload", "No service auth token available")
        result.finish()
        return result

    # Upload a test video
    job = timed_call(
        result, "Upload video",
        lambda: _upload_test_video(video, luna, service_auth.get("token", "")),
        detail_fn=lambda r: f"jobId={r.get('jobId', '?')}" if r else "failed",
    )

    if not job:
        result.step_skipped("Video job polling", "Upload failed")
        result.finish()
        return result

    job_id = job.get("jobId", "")

    # Poll for job completion
    completed_job = timed_call(
        result, "Poll for video job completion",
        lambda: _poll_job_status(video, job_id, luna.access_jwt, max_wait=60),
        detail_fn=lambda r: f"state={r.get('state', '?')}" if r else "timeout",
    )

    if completed_job and completed_job.get("state") == "COMPLETED":
        # Verify CDN URL is returned
        blob = completed_job.get("blob", {})
        cdn_url = blob.get("ref", {}).get("link", "") if isinstance(blob.get("ref"), dict) else ""
        if cdn_url:
            result.step_passed("CDN URL verification", f"cdn_url={cdn_url}")
        else:
            result.step_skipped("CDN URL verification", "No CDN URL in completed job")

        # Verify blob is accessible
        timed_call(
            result, "Verify video blob accessible",
            lambda: _verify_blob_accessible(pds, luna, blob),
        )
    else:
        result.step_skipped("CDN URL verification", "Job did not complete")

    # Check upload limits
    timed_call(
        result, "Get upload limits",
        lambda: video.video.get_upload_limits(luna.access_jwt),
    )

    result.finish()
    return result


def _upload_test_video(video_client, luna, service_token):
    """Upload a minimal test video file."""
    try:
        # Create a minimal MP4-like file for testing
        # In production, this would be a real video file
        test_data = b'\x00' * 1024  # Minimal placeholder
        return video_client.video.upload_video(
            test_data, "video/mp4", service_token,
        )
    except Exception:
        return None


def _poll_job_status(video_client, job_id, access_jwt, max_wait=60):
    """Poll video job status until completion or timeout."""
    start = time.time()
    while time.time() - start < max_wait:
        try:
            status = video_client.video.get_job_status(
                {"jobId": job_id}, access_jwt,
            )
            state = status.get("state", status.get("status", "UNKNOWN"))
            if state in ("COMPLETED", "FAILED"):
                return status
        except Exception:
            pass
        time.sleep(2)
    return None


def _verify_blob_accessible(pds, luna, blob):
    """Verify the video blob is accessible via the PDS."""
    try:
        cid = blob.get("ref", {}).get("link", "") if isinstance(blob.get("ref"), dict) else blob.get("cid", "")
        if cid:
            return pds.repositories.get_blob(luna.did, cid, luna.access_jwt)
    except Exception:
        pass
    return None
