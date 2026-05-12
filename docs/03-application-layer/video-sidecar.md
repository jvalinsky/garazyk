---
title: Video Side-Car (jelcz)
---

# Video Side-Car Service (jelcz)

Jelcz is a microservice that handles video processing outside the PDS process. It runs an HTTP server, SQLite database, and transcoding pipeline, communicating with the PDS via Service Auth tokens.

## When to Use

- **Large deployments** — Offload CPU-intensive transcoding from the PDS
- **Horizontal scaling** — Run multiple jelcz instances behind a load balancer
- **GPU/FFmpeg clusters** — Deploy jelcz on machines with different hardware

Set `PDS_VIDEO_MODE=external` on the PDS to delegate video processing to jelcz.

## Architecture

```
Client --> PDS (kaszlak) --uploadVideo--> Jelcz
                                        |
                                    [Job Queue]
                                        |
                                    [Transcode]
                                        |
                                    [Thumbnail]
                                        |
                                    [Upload Blob] --> PDS (com.atproto.repo.uploadBlob)
                                        |
                                    [Complete]
```

### Components

| Component | Protocol | Implementation |
|-----------|----------|----------------|
| Job store | `VideoJobStore` | `JelczDatabase` (own SQLite) |
| Blob upload | `VideoBlobUploader` | `VideoRemoteBlobUploader` (HTTP to PDS) |
| Auth | `VideoAuthProvider` | `VideoJWTAuthProvider` (Service Auth JWT) |
| Transcoder | `VideoTranscoderBackend` | `AVFoundationTranscoder` (macOS) or `FFmpegTranscoder` (Linux) |
| Thumbnail | Built-in | `ATProtoVideoThumbnailGenerator` |

### Inter-Service Auth

Jelcz validates Service Auth JWTs on `uploadVideo` requests:

1. Client calls `com.atproto.server.getServiceAuth` on the PDS with `aud=jelcz_did` and `lxm=com.atproto.repo.uploadBlob`
2. Client sends the token to jelcz via `Authorization: Bearer <token>`
3. Jelcz validates the JWT signature, `aud` claim, and expiration
4. After transcoding, jelcz uses the stored token to upload the processed blob to the PDS

### Database

Jelcz uses its own SQLite database (separate from the PDS service database). Schema is identical to the PDS `video_jobs` table with an additional `service_auth_token` column.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JELCZ_PORT` | 2586 | HTTP port |
| `JELCZ_DATA_DIR` | `./data/jelcz` | Database directory |
| `JELCZ_BLOB_DIR` | `./data/jelcz/blobs` | Blob storage directory |
| `JELCZ_PDS_URL` | `http://localhost:2583` | PDS endpoint for blob upload |
| `JELCZ_DID` | `did:web:localhost` | Jelcz's DID for Service Auth |
| `JELCZ_S3_BUCKET` | (none) | S3 bucket for blob storage |
| `JELCZ_S3_REGION` | `us-east-1` | S3 region |
| `JELCZ_S3_ENDPOINT` | (none) | S3-compatible endpoint |
| `JELCZ_S3_ACCESS_KEY` | (none) | S3 access key |
| `JELCZ_S3_SECRET_KEY` | (none) | S3 secret key |
| `JELCZ_MAX_CONCURRENT_JOBS` | 2 | Max parallel transcoding jobs |
| `JELCZ_POLL_INTERVAL` | 5.0 | Job poll interval (seconds) |
| `JELCZ_MAX_UPLOAD_BYTES` | 104857600 | Max upload size (100MB) |
| `JELCZ_MAX_OUTPUT_BYTES` | 52428800 | Max transcoded output size (50MB) |
| `JELCZ_MAX_DURATION` | 180 | Max video duration (seconds) |

### PDS Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PDS_VIDEO_MODE` | `internal` | `internal` (in-process) or `external` (use jelcz) |

When `PDS_VIDEO_MODE=external`, the PDS does not start the `ATProtoVideoWorker` and video XRPC endpoints return `JOB_STATE_PENDING` immediately.

## XRPC Endpoints

Jelcz serves the same video XRPC endpoints as the PDS:

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `app.bsky.video.uploadVideo` | POST | Service Auth | Upload video blob, create processing job |
| `app.bsky.video.getJobStatus` | GET | Optional | Query job state by `jobId` |
| `app.bsky.video.getUploadLimits` | GET | Optional | Return daily upload quotas |

## CMake Target

Jelcz is built as the `jelcz` binary target, linked against `ATProtoVideoService` (plus `ATProtoCore`, `ATProtoStorage`, `ATProtoTransport`).

## Source Files

| File | Description |
|------|-------------|
| `Garazyk/Sources/Video/VideoJobStore.h` | Job store protocol |
| `Garazyk/Sources/Video/VideoBlobUploader.h` | Blob uploader protocol |
| `Garazyk/Sources/Video/VideoAuthProvider.h` | Auth provider protocol |
| `Garazyk/Sources/Video/VideoTranscoderBackend.h` | Transcoder backend protocol + quality enum |
| `Garazyk/Sources/Video/VideoTranscoder.h/.m` | Transcoder (delegates to backend) |
| `Garazyk/Sources/Video/AVFoundationTranscoder.h/.m` | macOS AVFoundation backend |
| `Garazyk/Sources/Video/FFmpegTranscoder.h/.m` | Linux/GNUstep FFmpeg backend |
| `Garazyk/Sources/Video/VideoThumbnailGenerator.h/.m` | Thumbnail extraction |
| `Garazyk/Sources/Video/VideoWorker.h/.m` | Background job processor |
| `Garazyk/Sources/Video/VideoXrpcPack.h/.m` | XRPC endpoint handler |
| `Garazyk/Sources/Video/PDSLocalVideoJobStore.h/.m` | PDS database adapter |
| `Garazyk/Sources/Video/JelczDatabase.h/.m` | Jelcz SQLite database |
| `Garazyk/Sources/Video/VideoRemoteBlobUploader.h/.m` | HTTP blob upload to PDS |
| `Garazyk/Sources/Video/VideoJWTAuthProvider.h/.m` | JWT validation |
| `Garazyk/Sources/Video/VideoPDSAuthProvider.h/.m` | PDS-internal auth |
| `Garazyk/Sources/Video/VideoLocalBlobUploader.h/.m` | PDS-internal blob upload |

---

## Related
- [Video Processing Pipeline](./video-processing)
- [Blob Service](./blob-service)
- [Authentication: Service Auth](../06-authentication/session-and-jwt-lifecycle)
