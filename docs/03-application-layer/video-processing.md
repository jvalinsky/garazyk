---
title: Video Processing Pipeline
---

# Video Processing Pipeline

Garazyk includes a complete asynchronous pipeline for processing video uploads, generating thumbnails, and transcoding content for optimized delivery.

## Pipeline Architecture

The video pipeline is decoupled from the main XRPC request thread using a background worker pattern.

### 1. Ingestion (`PDSVideoWorker`)
**Location:** `Garazyk/Sources/Media/PDSVideoWorker.m`

When a user uploads a video blob, a `video_job` is created in the database. The `PDSVideoWorker` periodically scans for `PENDING` jobs and transitions them to `PROCESSING`.

### 2. Transcoding (`PDSVideoTranscoder`)
**Location:** `Garazyk/Sources/Media/PDSVideoTranscoder.m`

The transcoder utilizes FFmpeg (via platform-specific wrappers) to:
*   Normalize video containers to MP4.
*   Ensure consistent bitrates and resolutions for mobile playback.
*   Sanitize metadata to protect user privacy.

### 3. Thumbnail Generation (`PDSVideoThumbnailGenerator`)
**Location:** `Garazyk/Sources/Media/PDSVideoThumbnailGenerator.m`

Automatically extracts a keyframe from the uploaded video to be used as the preview image in feeds. The resulting image is stored as a separate blob and linked to the video record.

## Job Lifecycle

Jobs progress through the following states in the `video_jobs` table:

1.  **PENDING**: Job created, waiting for worker pick-up.
2.  **PROCESSING**: Transcoding or thumbnail generation in progress.
3.  **COMPLETED**: All assets generated and stored as blobs.
4.  **FAILED**: Error encountered (error details stored in `error_message`).

## Resource Management

*   **Concurrency**: The number of simultaneous transcoding jobs can be limited in `PDSConfiguration` to prevent CPU exhaustion.
*   **Quotas**: Video uploads are subject to the same PDS blob quotas as images, but often with higher per-file limits.

---

## Related
- [Blob Service](./blob-service)
- [Reference: Config](../11-reference/config-reference)
- [Reference: Metrics](../11-reference/metrics-collection)
