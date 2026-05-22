---
title: ATProtoMediaCore Framework
---

# ATProtoMediaCore Framework

The **ATProtoMediaCore** framework provides a reusable, configurable foundation
for building AT Protocol media CDN sidecar services. A new service (video,
audio, 3D splats, etc.) can be constructed in approximately 50 lines by
composing the framework's components.

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │        ATProtoMediaServiceRuntime    │
                    │  (orchestrates all subsystems)       │
                    └──────┬──────┬──────┬──────┬─────────┘
                           │      │      │      │
              ┌────────────┘  ┌───┘  ┌───┘  └────────────┐
              ▼               ▼      ▼                    ▼
     ┌────────────┐  ┌───────────┐ ┌──────┐  ┌───────────────┐
     │ HTTP Server │  │  Worker   │ │ DB   │  │  XRPC Routes  │
     │ (HttpServer)│  │(MediaWorker)│ │Store │  │ (MediaXrpcPack)│
     └────────────┘  └───────────┘ └──────┘  └───────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
     ┌────────────────┐     ┌──────────────────────┐
     │ Blob Provider   │     │ Media Processor      │
     │ (PDSBlobProvider)│    │ (ATProtoMediaProcessor)│
     └────────────────┘     └──────────────────────┘
```

## Core Components

### ATProtoMediaServiceRuntime

The main orchestrator class. It bootstraps all subsystems in `startWithError:`
and tears them down in `stop`.

```objc
ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
ATProtoVideoProcessor *processor = [[ATProtoVideoProcessor alloc] init];

ATProtoMediaServiceRuntime *runtime = [[ATProtoMediaServiceRuntime alloc] initWithConfiguration:config
                                                                                      processor:processor];
NSError *error = nil;
[runtime startWithError:&error];
```

**Subsystems started automatically:**
- SQLite database (`media.db` in `config.dataDirectory`)
- Blob provider (disk or S3, based on config)
- Background worker (polls for pending processing jobs)
- XRPC dispatcher (wired to the processor's `mediaTypeIdentifier`)
- HTTP server (health endpoint, admin endpoints, XRPC routes)

### ATProtoMediaProcessor Protocol

The domain-specific interface. Implement this protocol to define how your
media type is transcoded, thumbnailed, and packaged.

| Method | Purpose |
|--------|---------|
| `mediaTypeIdentifier` | Unique NSID, e.g. `app.bsky.video` |
| `canProcessMimeType:` | Route incoming uploads to the correct processor |
| `processMediaAtURL:outputDirectory:progressBlock:completion:` | Asynchronous processing pipeline |
| `validateContentSignature:declaredMimeType:` (optional) | Container signature validation |

### ATProtoMediaJobStore

Persistence layer protocol. The default implementation is `ATProtoMediaSQLiteStore`,
which uses a `media_jobs` table with WAL mode and a `results_json` column for
domain-specific metadata.

### ATProtoMediaWorker

Concurrent background job processor. Polls the job store on a configurable
interval, respects `maxConcurrentJobs`, handles retry loops, and transitions
jobs through `PENDING → PROCESSING → COMPLETED | FAILED`.

### ATProtoMediaXrpcPack

Parameterized XRPC route registration. Maps generic upload/job-status/limits
endpoints to the correct NSID based on the processor's media type.

## Adding a New Media Service

1. Create a new `ATProto<Media>Processor` implementing `<ATProtoMediaProcessor>`
2. Create a `main.m` that:
   - Reads config from env vars (prefix convention)
   - Instantiates `ATProtoMediaServiceRuntime` with the processor
   - Calls `startWithError:` and runs the runloop
   - Registered HLS-style serving routes (optional)
3. Add CMake target linking `ATProtoMediaCore` and domain-specific libraries

## Configuration

### Environment Variables (prefix convention)

| Variable | Default | Description |
|----------|---------|-------------|
| `<PREFIX>_PORT` | `2586` | HTTP port |
| `<PREFIX>_DATA_DIR` | `./data/media` | Data directory |
| `<PREFIX>_BLOB_DIR` | `./data/media/blobs` | Blob storage |
| `<PREFIX>_PDS_URL` | `http://localhost:2583` | Upstream PDS |
| `<PREFIX>_DID` | `did:web:localhost` | Service DID |
| `<PREFIX>_MAX_CONCURRENT_JOBS` | `2` | Parallelism limit |
| `<PREFIX>_POLL_INTERVAL` | `5.0` | Worker poll interval |
| `<PREFIX>_MAX_UPLOAD_BYTES` | `104857600` | Upload size limit |
| `<PREFIX>_MAX_DURATION` | `180` | Max duration (seconds) |
| `<PREFIX>_OUTPUT_DIR` | *(none)* | HLS/output directory |
| `<PREFIX>_OUTPUT_BASE_URL` | *(none)* | Public base URL |
| `<PREFIX>_HIGH_QUALITY` | `0` | Include high-quality variants |
| `<PREFIX>_S3_BUCKET` | *(none)* | S3 bucket (cloud storage) |
| `<PREFIX>_S3_REGION` | `us-east-1` | AWS region |
| `<PREFIX>_S3_ENDPOINT` | *(none)* | Custom S3 endpoint |
| `<PREFIX>_S3_ACCESS_KEY` | *(none)* | S3 access key |
| `<PREFIX>_S3_SECRET_KEY` | *(none)* | S3 secret key |

### CLI Flag Overrides

CLI flags override environment variables at runtime. Supported flags mirror
the environment variables (e.g. `--port`, `--pds-url`, `--hls-dir`, `--hls-1080p`).

## Example: Jelcz (Video Processing Service)

`Garazyk/Binaries/jelcz/main.m` is the reference implementation, providing:

- **serve** — Boots the runtime, registers ATProto video XRPC endpoints,
  configures HLS serving routes
- **status** — Queries `/_health` on a running instance
- **version** — Prints version info
- **help** — Prints usage with all CLI flags

Crash handlers are installed for SIGSEGV, SIGABRT, SIGBUS, SIGFPE, and SIGTRAP
with backtrace logging to `/tmp/jelcz-crash.log`.

## Testing

### Unit Tests

| Test File | Coverage |
|-----------|----------|
| `Tests/Media/ATProtoMediaCoreTests.m` | SQLite store CRUD, state transitions, worker mock, concurrency |
| `Tests/Media/JelczCLITests.m` | CLI flag parsing, command routing, usage output |
| `Tests/Media/ATProtoMediaServiceRuntimeTests.m` | Health/admin endpoints, job lifecycle |

### Running

```bash
# Build and run all MediaCore tests
cd build && cmake --build . --target AllTests
./tests/AllTests -f "ATProtoMedia*" -f "JelczCLI*"

# Runtime tests require socket access
./tests/AllTests --gated=run -f "ATProtoMediaServiceRuntime*"
```

## References

- `Garazyk/Sources/MediaCore/` — framework source
- `Garazyk/Binaries/jelcz/main.m` — example service binary
- `docs/20-explanation/guides/DEPLOYMENT.md` — deployment guide
