---
title: Video Processing Pipeline
---

# Video Processing Pipeline

Garazyk includes a complete asynchronous pipeline for processing video uploads, generating thumbnails, and transcoding content for optimized delivery.

## Pipeline Architecture

The video pipeline is decoupled from the main XRPC request thread using a background worker pattern. The worker polls the database for pending jobs and dispatches them through a multi-stage processing chain.

### 1. Ingestion (`XrpcAppBskyVideoPack` → `PDSVideoWorker`)
**Location:** `Garazyk/Sources/Network/XrpcAppBskyVideoPack.m`, `Garazyk/Sources/Media/PDSVideoWorker.m`

When a user uploads a video blob via `app.bsky.video.uploadVideo`, the endpoint stores the raw blob and creates a `video_job` record in the service database with state `PENDING`. The `PDSVideoWorker` singleton periodically scans for `PENDING` jobs and transitions them to `PROCESSING`.

The worker is started automatically during `PDSApplication` launch and stopped on shutdown. It is configured with `maxConcurrentJobs` (default: 2) and `pollInterval` (default: 5 seconds).

### 2. Transcoding (`PDSVideoTranscoder`)
**Location:** `Garazyk/Sources/Media/PDSVideoTranscoder.m`

The transcoder uses AVFoundation (`AVAssetExportSession`) to convert uploaded videos. This is a macOS-native approach that avoids external FFmpeg dependencies.

Quality presets map to AVFoundation export presets:

| Preset | AVFoundation Constant | Resolution |
|--------|----------------------|------------|
| 480p | `AVAssetExportPreset640x480` | 640x480 |
| 720p | `AVAssetExportPreset1280x720` | 1280x720 |
| 1080p | `AVAssetExportPreset1920x1080` | 1920x1080 |
| HEVC | `AVAssetExportPresetHEVCHighestQuality` | Variable |
| Default | `AVAssetExportPresetHighestQuality` | Variable |

The transcoder supports both synchronous and asynchronous interfaces. Active exports are tracked in an `@synchronized` set for cancellation and concurrency management.

### 3. Thumbnail Generation (`PDSVideoThumbnailGenerator`)
**Location:** `Garazyk/Sources/Media/PDSVideoThumbnailGenerator.m`

Extracts a keyframe from the uploaded video using `AVAssetImageGenerator` and encodes it as JPEG. The thumbnail is stored as a separate blob via the `PDSBlobProvider` protocol and linked to the video job through the `thumbnail_blob_cid` column.

## Job Lifecycle

Jobs progress through the following states in the `video_jobs` table:

1. **PENDING**: Job created, waiting for worker pick-up.
2. **PROCESSING**: Worker has claimed the job.
3. **TRANSCODING**: Video transcoding in progress.
4. **GENERATING_THUMBNAIL**: Thumbnail extraction in progress.
5. **COMPLETED**: All assets generated and stored as blobs.
6. **FAILED**: Error encountered (error details stored in `error_message`).

### Retry Logic

Failed jobs are retried up to 3 times. On each failure, `incrementVideoJobRetry:` increments the `retry_count` and resets the state to `PENDING`. After 3 retries, the job remains in `FAILED` state permanently.

### State Transitions

```
PENDING → PROCESSING → TRANSCODING → GENERATING_THUMBNAIL → COMPLETED
   ↑         │              │                │
   └─────────┘              └────────────────┘
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
| `app.bsky.video.getUploadLimits` | GET | Optional | Return daily upload quotas (canUpload, remainingDailyVideos, remainingDailyBytes) |

## Resource Management

- **Concurrency**: `maxConcurrentJobs` limits simultaneous processing (default: 2). `maxConcurrentExports` on the transcoder caps parallel AVAssetExportSession operations (default: 2).
- **Quotas**: Video uploads are subject to daily limits queried from the `video_jobs` table (today's count per DID).
- **Temp files**: The worker creates temporary files for transcoding input/output and cleans them up after processing completes or fails.

## Test Coverage

The video pipeline has dedicated unit and integration tests:

| Test File | Type | Count | Coverage |
|-----------|------|-------|----------|
| `PDSVideoJobsTests.m` | Unit (DB) | 8 | Job CRUD, state transitions, retry logic |
| `PDSVideoTranscoderTests.m` | Unit | 9 | Presets, singleton, config, cancel |
| `PDSVideoThumbnailGeneratorTests.m` | Unit | 5 | Blob storage, JPEG encoding |
| `PDSVideoWorkerTests.m` | Unit | 12 | Lifecycle, retry, concurrency gating |
| `XrpcAppBskyVideoTests.m` | Integration | 15 | XRPC endpoints, job status, upload limits |
| `PDSVideoTranscoderIntegrationTests.m` | Integration | 4 | AVFoundation transcoding with real MP4 |
| `PDSVideoThumbnailGeneratorIntegrationTests.m` | Integration | 4 | Thumbnail extraction with real MP4 |
| `PDSVideoWorkerIntegrationTests.m` | Integration | 1 | End-to-end pipeline |

Integration tests use `VideoIntegrationTestBase` which generates a 1-second black MP4 via `AVAssetWriter`, with `XCTSkip` fallback for headless CI environments.

---

## Related
- [Blob Service](./blob-service)
- [Service Databases](../05-database-layer/service-databases)
- [Reference: Config](../11-reference/config-reference)
- [Reference: Test Coverage Goals](../11-reference/test-coverage-goals)
