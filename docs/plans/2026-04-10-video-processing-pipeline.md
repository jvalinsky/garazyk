---
title: "Phase 2: Video Processing Pipeline Plan"
---

# Phase 2: Video Processing Pipeline

> **Status:** 50% Complete (upload exists, processing stubbed)
> **Priority:** P1 (High)
> **Generated:** 2026-04-10

## Executive Summary

The video upload endpoint exists (`app.bsky.video.uploadVideo`) but processing is stubbed - returns "Processing not implemented" at line 2740 of XrpcAppBskyMethods.m. This plan covers implementing the full video processing pipeline.

---

## Current Implementation Status

| Endpoint | Status | Location |
|----------|--------|----------|
| `app.bsky.video.uploadVideo` | ✅ Upload works | `XrpcAppBskyMethods.m:2708-2743` |
| `app.bsky.video.getJobStatus` | ⚠️ Stub (404) | `XrpcAppBskyMethods.m:2697-2706` |
| `app.bsky.video.getUploadLimits` | ⚠️ Hardcoded values | `XrpcAppBskyMethods.m:2745-2754` |

### Current Stub Behavior (Line 2740)
```objc
"message": @"Video stored. Processing not implemented."
```

---

## Tasks

### Task 2.1: Implement Video Job Status Tracking

**Goal:** Move from 404 to actual state tracking

**Files:**
- Implementation: `ATProtoPDS/Sources/Network/XrpcAppBskyMethods.m:2697-2706`
- Database: Add video_jobs table to schema

**Steps:**
1. Create database schema for video jobs:
   ```sql
   CREATE TABLE video_jobs (
     job_id TEXT PRIMARY KEY,
     did TEXT NOT NULL,
     blob_cid TEXT NOT NULL,
     state TEXT NOT NULL, -- PENDING, PROCESSING, COMPLETED, FAILED
     progress INTEGER DEFAULT 0,
     message TEXT,
     created_at TEXT NOT NULL,
     updated_at TEXT NOT NULL,
     expires_at TEXT
   );
   ```
2. Modify `getJobStatus` to query job from database
3. Return actual state/progress from stored job record

**Citations:**
- Lexicon: `app.bsky.video.getJobStatus` output schema
- Similar pattern: `ATProtoPDS/Sources/Database/PDSDatabase.m` (existing job tracking)

---

### Task 2.2: Integrate FFmpeg for Video Transcoding

**Goal:** Convert uploaded videos to H.264/H.265 for web compatibility

**Files:**
- New: `ATProtoPDS/Sources/Media/PDSVideoTranscoder.m`
- Config: `ATProtoPDS/Sources/App/PDSConfiguration.m`

**Steps:**
1. Add FFmpeg path configuration to PDSConfiguration:
   ```objc
   @property (nonatomic, copy) NSString *ffmpegPath; // default: "/usr/local/bin/ffmpeg"
   ```
2. Create PDSVideoTranscoder class:
   ```objc
   - (void)transcodeVideoAtPath:(NSString *)inputPath 
                    outputPath:(NSString *)outputPath
                    completion:(void (^)(BOOL success, NSError *error))completion;
   ```
3. Implement H.264 baseline encoding for maximum compatibility
4. Implement H.265/HEVC for quality/bandwidth optimization
5. Add resolution limiting (max 1920x1080 for standard tier)

**Tech Stack:**
- FFmpeg (via NSTask/Process)
- Target codecs: H.264 (libx264), H.265 (libx265)
- Container: MP4

**References:**
- ATProto video specs (blob accepted formats)
- Bluesky video processing requirements

---

### Task 2.3: Implement Thumbnail Generation

**Goal:** Generate video thumbnails for preview

**Files:**
- Implementation: `ATProtoPDS/Sources/Media/PDSVideoThumbnailGenerator.m`

**Steps:**
1. Extract frame at 1 second mark (or user-specified time)
2. Generate JPEG at 640x360 (16:9 aspect)
3. Store as separate blob, link to video job
4. Support custom time offset parameter

**FFmpeg command:**
```bash
ffmpeg -i input.mp4 -ss 00:00:01 -vframes 1 -s 640x360 thumbnail.jpg
```

---

### Task 2.4: Implement Video Moderation/Blur Processing

**Goal:** Process videos for content moderation (NSFW blur, etc.)

**Files:**
- Implementation: `ATProtoPDS/Sources/Moderation/PDSVideoModerationProcessor.m`
- Config: Moderation settings in PDSConfiguration

**Steps:**
1. Integrate with existing moderation service
2. Apply blur to flagged content regions
3. Queue videos for human review if confidence < threshold
4. Generate "safe" version alongside original

---

### Task 2.5: Implement Async Job Updates (WebSocket/EventStream)

**Goal:** Notify clients of job progress in real-time

**Files:**
- New: `ATProtoPDS/Sources/Sync/PDSVideoJobEventStream.m`
- Reference: `ATProtoPDS/Sources/Sync/SubscribeReposHandler.m`

**Steps:**
1. Add WebSocket endpoint for video job updates
2. Emit events: `VideoJobProgress`, `VideoJobCompleted`, `VideoJobFailed`
3. Allow clients to subscribe to specific job IDs
4. Implement fallback polling for non-WebSocket clients

**Event Schema:**
```json
{
  "event": "progress",
  "jobId": "...",
  "did": "...",
  "progress": 50,
  "message": "Transcoding..."
}
```

---

### Task 2.6: Make getUploadLimits Dynamic

**Goal:** Return limits based on user tier and storage

**Files:**
- Implementation: `ATProtoPDS/Sources/Network/XrpcAppBskyMethods.m:2745-2754`
- Config: Tier-based limits in PDSConfiguration

**Steps:**
1. Add tier configuration:
   ```objc
   @property (nonatomic, assign) NSInteger videoUploadLimitDaily;
   @property (nonatomic, assign) NSUInteger videoMaxFileSizeBytes;
   @property (nonatomic, assign) NSInteger videoMaxDurationSeconds;
   ```
2. Query user's tier from account record
3. Calculate remaining quota from today's uploads (query video_jobs for date)
4. Return dynamic limits

**Current hardcoded values (needs fixing):**
```objc
@"remainingDailyVideos": @25,
@"remainingDailyBytes": @(50 * 1024 * 1024),  // 50MB
```

---

### Task 2.7: Create Video Processing Worker/Queue

**Goal:** Background processing for video jobs

**Files:**
- New: `ATProtoPDS/Sources/Workers/PDSVideoWorker.m`
- Config: Queue settings in PDSConfiguration

**Steps:**
1. Create background queue for video processing
2. Poll database for pending jobs (state = PENDING)
3. Process jobs sequentially (avoid memory overload)
4. Update job state at each stage:
   - PENDING → PROCESSING → COMPLETED/FAILED
5. Implement retry logic for transient failures (max 3 retries)
6. Implement dead-letter queue for permanent failures

---

## Database Schema Additions

```sql
-- Video jobs table
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
    retry_count INTEGER DEFAULT 0,
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE INDEX idx_video_jobs_did ON video_jobs(did);
CREATE INDEX idx_video_jobs_state ON video_jobs(state);
CREATE INDEX idx_video_jobs_created ON video_jobs(created_at);
```

---

## Dependencies

- `ATProtoPDS/Sources/Network/XrpcAppBskyMethods.m` - Endpoint registration
- `ATProtoPDS/Sources/Database/PDSDatabase.m` - Job storage
- `ATProtoPDS/Sources/App/PDSConfiguration.m` - Configuration
- FFmpeg (system dependency)

---

## Related Plans

- [Phase 1: OAuth 2.0/DPoP Compliance](2026-04-10-oauth-dpop-compliance.md)
- [Phase 3: Chat/Conversation Support](2026-04-10-chat-conversation-support.md)

---

## Next Steps

After Phase 1 (OAuth) verification:
1. Begin Task 2.1 - Implement job status tracking
2. Add FFmpeg to system dependencies
3. Create video processing worker
4. Test full pipeline end-to-end