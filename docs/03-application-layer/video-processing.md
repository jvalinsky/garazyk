---
title: Video Processing Pipeline
---

# Video Processing Pipeline

Garazyk supports two video processing modes: **internal** (in-process within the PDS) and **external** (delegated to the jelcz side-car service). The mode is controlled by the `PDS_VIDEO_MODE` environment variable.

## Architecture

### Internal Mode (`PDS_VIDEO_MODE=internal`, default)

Video processing runs in-process within the kaszlak PDS binary. The `ATProtoVideoXrpcPack` handles upload, the `ATProtoVideoWorker` polls for pending jobs, and transcoding/thumbnail generation happen on background queues.

**Key classes:**
- `ATProtoVideoXrpcPack` — XRPC endpoint handler (`uploadVideo`, `getJobStatus`, `getUploadLimits`)
- `ATProtoVideoWorker` — Background job processor (polls DB, dispatches transcode + thumbnail)
- `ATProtoVideoTranscoder` — Delegates to platform-specific backend
- `AVFoundationTranscoder` — macOS backend using `AVAssetExportSession`
- `FFmpegTranscoder` — Linux/GNUstep backend using `ffmpeg`/`ffprobe` subprocesses
- `ATProtoVideoThumbnailGenerator` — Thumbnail extraction (AVAssetImageGenerator on macOS, ffmpeg on Linux)
- `PDSLocalVideoJobStore` — `VideoJobStore` adapter wrapping `PDSDatabase`

**Source location:** `Garazyk/Sources/Video/`

### External Mode (`PDS_VIDEO_MODE=external`)

Video processing is delegated to the **jelcz** side-car service. The PDS does not process video at all; it returns `JOB_STATE_PENDING` immediately and the client polls jelcz directly for job status.

See [Video Side-Car (jelcz)](./video-sidecar) for details.

## Pipeline Stages

### 1. Ingestion (`ATProtoVideoXrpcPack`)

When a user uploads a video via `app.bsky.video.uploadVideo`:

1. **Content type validation** — `validateVideoContentType:declaredMimeType:` checks for MP4 ftyp box or Matroska header bytes
2. **Size check** — Rejects uploads exceeding 100MB
3. **Blob storage** — Raw blob stored via `PDSBlobProvider`
4. **Job creation** — `video_jobs` record created with state `PENDING`
5. **Service auth token** — Bearer token from Authorization header stored with job for later blob upload (external mode)

### 2. Metadata Extraction (`ATProtoVideoWorker`)

After blob storage, the worker extracts video metadata:

- **Dimensions** — Width/height via `AVAssetTrack.naturalSize` (macOS) or `ffprobe -show_entries stream=width,height` (Linux)
- **Duration** — Via `AVAsset.duration` (macOS) or `ffprobe -show_entries format=duration` (Linux)
- **Duration validation** — Rejects videos shorter than 1s or longer than 180s
- **Framerate** — Preserved at source rate when <= 30 FPS; capped at 30 FPS otherwise

### 3. Transcoding (`ATProtoVideoTranscoder`)

The transcoder delegates to a platform-specific backend via the `VideoTranscoderBackend` protocol:

**macOS (`AVFoundationTranscoder`):**
- Uses `AVAssetExportSession` with quality presets
- Preserves source framerate via `AVMutableVideoComposition.frameDuration`
- Output: MP4 (H.264), optimized for network streaming

**Linux/GNUstep (`FFmpegTranscoder`):**
- Spawns `ffmpeg` subprocess with `-c:v libx264 -preset medium -crf 23`
- Framerate controlled via `-r` flag
- Output size limit: 50MB

Quality presets:

| Preset | Resolution | macOS Constant |
|--------|-----------|----------------|
| 480p | 640x480 | `AVAssetExportPreset640x480` |
| 720p | 1280x720 | `AVAssetExportPreset1280x720` |
| 1080p | 1920x1080 | `AVAssetExportPreset1920x1080` |
| HEVC | Variable | `AVAssetExportPresetHEVCHighestQuality` |

### 4. Thumbnail Generation (`ATProtoVideoThumbnailGenerator`)

**macOS:** `AVAssetImageGenerator` extracts a frame at 0.5s, encoded as JPEG via `CGImageDestination`.

**Linux:** `ffmpeg -ss 0.5 -i <input> -frames:v 1 -f image2 -q:v 2 <output>` extracts a JPEG frame.

Thumbnails are stored as blobs via `PDSBlobProvider` and linked to the job via `thumbnail_blob_cid`.

## Job Lifecycle

Jobs progress through these states in the `video_jobs` table:

1. **PENDING** — Job created, waiting for worker pick-up
2. **PROCESSING** — Worker claimed the job, extracting metadata
3. **TRANSCODING** — Video transcoding in progress
4. **GENERATING_THUMBNAIL** — Thumbnail extraction in progress
5. **COMPLETED** — All assets generated and stored as blobs
6. **FAILED** — Error encountered (details in `error_message`)

### Retry Logic

Failed jobs retry up to 3 times. On each failure, `retry_count` increments and state resets to `PENDING`. After 3 retries, the job stays `FAILED` permanently.

### State Transitions

```
PENDING -> PROCESSING -> TRANSCODING -> GENERATING_THUMBNAIL -> COMPLETED
   ^         |              |                |
   +---------+              +----------------+
     (retry < 3)              (permanent failure)
```

## Database Schema

The `video_jobs` table lives in the service database:

```sql
CREATE TABLE video_jobs (
    job_id TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    blob_cid TEXT NOT NULL,
    original_filename TEXT,
    mime_type TEXT,
    file_size INTEGER,
    duration_seconds INTEGER,
    width INTEGER,
    height INTEGER,
    service_auth_token TEXT,
    state TEXT NOT NULL DEFAULT 'PENDING',
    progress INTEGER DEFAULT 0,
    message TEXT,
    error_code TEXT,
    error_message TEXT,
    thumbnail_blob_cid TEXT,
    processed_blob_cid TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    completed_at TEXT,
    expires_at TEXT,
    retry_count INTEGER DEFAULT 0
);

CREATE INDEX idx_video_jobs_did ON video_jobs(did);
CREATE INDEX idx_video_jobs_state ON video_jobs(state);
CREATE INDEX idx_video_jobs_created ON video_jobs(created_at);
```

## XRPC Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `app.bsky.video.uploadVideo` | POST | Required | Upload video blob, create processing job |
| `app.bsky.video.getJobStatus` | GET | Optional | Query job state by `jobId` parameter |
| `app.bsky.video.getUploadLimits` | GET | Optional | Return daily upload quotas |

### Job Status Response

The `getJobStatus` response includes:

- `jobId` — Unique job identifier
- `did` — Account DID
- `state` — `JOB_STATE_PENDING`, `JOB_STATE_COMPLETED`, or `JOB_STATE_FAILED`
- `progress` — 0-100 integer
- `blob` — Processed blob reference (when completed)
- `error` — Error message (when failed)
- `message` — Status message
- `aspectRatio` — `{width, height}` object (when available)

## Resource Management

- **Concurrency**: `maxConcurrentJobs` limits simultaneous processing (default: 2)
- **Size limits**: 100MB input, 50MB output
- **Duration limits**: 1-180 seconds
- **Temp files**: Created for transcoding, cleaned up after completion or failure

## Test Coverage

| Test File | Type | Coverage |
|-----------|------|----------|
| `PDSVideoJobsTests.m` | Unit (DB) | Job CRUD, state transitions, retry logic |
| `ATProtoVideoTranscoderTests.m` | Unit | Singleton, config, cancel |
| `ATProtoVideoThumbnailGeneratorTests.m` | Unit | Blob storage, JPEG encoding |
| `ATProtoVideoWorkerTests.m` | Unit | Lifecycle, retry, concurrency gating |
| `ATProtoVideoXrpcPackTests.m` | Integration | XRPC endpoints, content type validation |
| `ATProtoVideoTranscoderIntegrationTests.m` | Integration | AVFoundation transcoding with real MP4 |
| `ATProtoVideoThumbnailGeneratorIntegrationTests.m` | Integration | Thumbnail extraction with real MP4 |
| `ATProtoVideoWorkerIntegrationTests.m` | Integration | End-to-end pipeline |

Integration tests use `VideoIntegrationTestBase` which generates a 1-second black MP4 via `AVAssetWriter`, with `XCTSkip` fallback for headless CI.

---

## Related
- [Video Side-Car (jelcz)](./video-sidecar)
- [Blob Service](./blob-service)
- [Service Databases](../05-database-layer/service-databases)
- [Reference: Config](../11-reference/config-reference)
