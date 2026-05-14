// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @brief Entry point for the Jelcz video processing service.

 @discussion A standalone AT Protocol video processing side-car service.
 Accepts video uploads via app.bsky.video.* XRPC endpoints,
 processes them asynchronously (transcode + thumbnail), and
 uploads the completed blobs to the user's PDS via Service Auth.

 Named after Jelcz, a Polish vehicle manufacturer known for
 buses and trucks produced 1952–2008.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <execinfo.h>
#import "Video/JelczConfiguration.h"
#import "Video/JelczDatabase.h"
#import "Video/VideoWorker.h"
#import "Video/VideoXrpcPack.h"
#import "Video/VideoRemoteBlobUploader.h"
#import "Video/VideoJWTAuthProvider.h"
#import "Video/VideoTranscoder.h"
#import "Video/VideoThumbnailGenerator.h"
#import "Video/VideoHLSGenerator.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Blob/PDSCloudStorageBlobProvider.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Debug/GZLogger.h"

static HttpServer *gServer = nil;
static ATProtoVideoWorker *gWorker = nil;

static void setJelczCORSHeaders(HttpRequest *request, HttpResponse *response) {
    NSString *origin = [request headerForKey:@"Origin"];
    if (origin.length > 0) {
        [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
        [response setHeader:@"true" forKey:@"Access-Control-Allow-Credentials"];
        [response setHeader:@"Origin" forKey:@"Vary"];
    } else {
        [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    }
    [response setHeader:@"GET, POST, OPTIONS, HEAD" forKey:@"Access-Control-Allow-Methods"];
    [response setHeader:@"Authorization, Content-Type, Accept, Range, If-None-Match, If-Modified-Since, DPoP, DPoP-Nonce, X-Garazyk-Access-JWT, X-Garazyk-Access-Token, *" forKey:@"Access-Control-Allow-Headers"];
    [response setHeader:@"Content-Length, Content-Range, Accept-Ranges, DPoP-Nonce, WWW-Authenticate" forKey:@"Access-Control-Expose-Headers"];
    [response setHeader:@"true" forKey:@"Access-Control-Allow-Private-Network"];
    [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
}

#pragma mark - Crash Diagnostics

static void crash_signal_handler(int sig) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  :
                          (sig == SIGTRAP) ? "SIGTRAP" : "UNKNOWN";

    char buf[256];
    int len = snprintf(buf, sizeof(buf),
        "\n=== FATAL SIGNAL %s (%d) in jelcz ===\n", signame, sig);
    write(STDERR_FILENO, buf, (size_t)len);

    int fd = open("/tmp/jelcz-crash.log",
                  O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        write(fd, buf, (size_t)len);
        void *frames[32];
        int frame_count = (int)backtrace(frames, 32);
        for (int i = 0; i < frame_count; i++) {
            char frame_buf[64];
            int flen = snprintf(frame_buf, sizeof(frame_buf),
                                "  #%d %p\n", i, frames[i]);
            write(fd, frame_buf, (size_t)flen);
        }
        char **symbols = backtrace_symbols(frames, frame_count);
        if (symbols) {
            for (int i = 0; i < frame_count; i++) {
                char sym_buf[256];
                int slen = snprintf(sym_buf, sizeof(sym_buf),
                                    "  #%d %s\n", i, symbols[i] ?: "?");
                write(fd, sym_buf, (size_t)slen);
            }
            free(symbols);
        }
        close(fd);
    }

    signal(sig, SIG_DFL);
    raise(sig);
}

static void uncaught_exception_handler(NSException *exception) {
    fprintf(stderr, "\n=== UNCAUGHT EXCEPTION ===\n");
    fprintf(stderr, "Name: %s\n", exception.name.UTF8String ?: "?");
    fprintf(stderr, "Reason: %s\n", exception.reason.UTF8String ?: "?");

    int fd = open("/tmp/jelcz-crash.log",
                  O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char buf[1024];
        int len = snprintf(buf, sizeof(buf),
            "=== UNCAUGHT EXCEPTION ===\nName: %s\nReason: %s\n",
            exception.name.UTF8String ?: "?",
            exception.reason.UTF8String ?: "?");
        write(fd, buf, (size_t)len);
        close(fd);
    }
    fflush(stderr);
}

static void install_crash_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = crash_signal_handler;
    sa.sa_flags = SA_RESETHAND;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
    NSSetUncaughtExceptionHandler(&uncaught_exception_handler);
}

void handleSignal(int sig) {
    GZ_LOG_INFO(@"Received signal %d, shutting down...", sig);
    [gWorker stop];
    [gServer stop];
    exit(0);
}

void print_usage(void) {
    printf("Usage: jelcz <command> [options]\n\n");
    printf("Jelcz - Standalone AT Protocol Video Processing Service\n\n");
    printf("Commands:\n");
    printf("  serve        Start video processing service\n");
    printf("  status       Query service status\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 2586)\n");
    printf("  --pds-url <url>       PDS URL for blob upload (default: http://localhost:2583)\n");
    printf("  --data-dir <path>     Data directory for database\n");
    printf("  --blob-dir <path>     Blob storage directory\n");
    printf("  --did <did>           Service DID for Service Auth\n");
    printf("  --s3-bucket <name>    S3 bucket for blob storage\n");
    printf("  --s3-region <region>  S3 region (default: us-east-1)\n");
    printf("  --s3-endpoint <url>   S3-compatible endpoint URL\n");
    printf("  --hls-dir <path>      HLS output directory\n");
    printf("  --hls-base-url <url>  Base URL for HLS playlist URLs\n");
    printf("  --hls-1080p           Include 1080p HLS variant\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
    printf("Environment variables:\n");
    printf("  JELCZ_PORT            HTTP port (default: 2586)\n");
    printf("  JELCZ_PDS_URL         PDS endpoint URL\n");
    printf("  JELCZ_DATA_DIR        Database directory\n");
    printf("  JELCZ_BLOB_DIR        Blob storage directory\n");
    printf("  JELCZ_DID             Service DID\n");
    printf("  JELCZ_S3_BUCKET       S3 bucket name\n");
    printf("  JELCZ_MAX_CONCURRENT_JOBS  Max parallel jobs (default: 2)\n");
    printf("  JELCZ_HLS_DIR              HLS output directory\n");
    printf("  JELCZ_HLS_BASE_URL         Base URL for HLS playlist URLs\n");
    printf("  JELCZ_HLS_1080P            Include 1080p HLS variant (default: false)\n");
    printf("\nExamples:\n");
    printf("  jelcz serve --port 2586\n");
    printf("  jelcz status --port 2586\n");
}

/// Queries `/_health` on a running Jelcz instance (same port resolution as `serve`).
static int run_status(int argc, const char *argv[]) {
    JelczConfiguration *config = [JelczConfiguration configurationFromEnvironment];

    for (int i = 2; i < argc; i++) {
        NSString *arg = [NSString stringWithUTF8String:argv[i]];
        if ([arg isEqualToString:@"--port"] && i + 1 < argc) {
            config.port = [[NSString stringWithUTF8String:argv[++i]] integerValue];
        } else if ([arg hasPrefix:@"-"]) {
            fprintf(stderr, "Error: unknown option for status: %s\n", argv[i]);
            print_usage();
            return 2;
        } else {
            fprintf(stderr, "Error: unexpected argument for status: %s\n", argv[i]);
            print_usage();
            return 2;
        }
    }

    NSString *urlString =
        [NSString stringWithFormat:@"http://127.0.0.1:%lu/_health", (unsigned long)config.port];
    NSURL *url = [NSURL URLWithString:urlString];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];

    if (!data || error) {
        printf("Jelcz status: NOT RUNNING (port %lu)\n", (unsigned long)config.port);
        if (error) {
            printf("  Error: %s\n", error.localizedDescription.UTF8String);
        }
        return 1;
    }

    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    printf("Jelcz status: RUNNING\n");
    printf("  Port: %lu\n", (unsigned long)config.port);
    if (body && [body isKindOfClass:[NSDictionary class]]) {
        id st = body[@"status"];
        if (st && [st isKindOfClass:[NSString class]]) {
            printf("  Health: %s\n", [st UTF8String]);
        }
    }
    return 0;
}

int run_serve(int argc, const char *argv[]) {
    install_crash_handlers();
    signal(SIGINT, handleSignal);
    signal(SIGTERM, handleSignal);

    JelczConfiguration *config = [JelczConfiguration configurationFromEnvironment];

    // Parse CLI args (override env vars)
    for (int i = 2; i < argc; i++) {
        NSString *arg = [NSString stringWithUTF8String:argv[i]];
        if ([arg isEqualToString:@"--port"] && i + 1 < argc) {
            config.port = [[NSString stringWithUTF8String:argv[++i]] integerValue];
        } else if ([arg isEqualToString:@"--pds-url"] && i + 1 < argc) {
            config.pdsURL = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--data-dir"] && i + 1 < argc) {
            config.dataDirectory = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--blob-dir"] && i + 1 < argc) {
            config.blobDirectory = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--did"] && i + 1 < argc) {
            config.serviceDID = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--s3-bucket"] && i + 1 < argc) {
            config.s3Bucket = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--s3-region"] && i + 1 < argc) {
            config.s3Region = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--s3-endpoint"] && i + 1 < argc) {
            config.s3Endpoint = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--hls-dir"] && i + 1 < argc) {
            config.hlsOutputDirectory = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--hls-base-url"] && i + 1 < argc) {
            config.hlsBaseUrl = [NSString stringWithUTF8String:argv[++i]];
        } else if ([arg isEqualToString:@"--hls-1080p"]) {
            config.hlsInclude1080p = YES;
        } else if ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]) {
            // Enable debug logging
        }
    }

    GZ_LOG_INFO(@"Jelcz video processing service starting");
    GZ_LOG_INFO(@"  Port: %lu", (unsigned long)config.port);
    GZ_LOG_INFO(@"  PDS URL: %@", config.pdsURL);
    GZ_LOG_INFO(@"  Service DID: %@", config.serviceDID);
    GZ_LOG_INFO(@"  Data dir: %@", config.dataDirectory);
    GZ_LOG_INFO(@"  Blob dir: %@", config.blobDirectory);

    // Initialize database
    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"jelcz.db"];
    NSError *error = nil;
    JelczDatabase *database = [[JelczDatabase alloc] initWithDatabasePath:dbPath error:&error];
    if (!database) {
        GZ_LOG_ERROR(@"Failed to open database: %@", error);
        return 1;
    }

    // Initialize blob provider
    id<PDSBlobProvider> blobProvider = nil;
    if (config.s3Bucket) {
        blobProvider = [[PDSCloudStorageBlobProvider alloc] initWithBucket:config.s3Bucket
                                                                    region:config.s3Region
                                                                  endpoint:config.s3Endpoint
                                                                 keyPrefix:@"blobs/"
                                                             accessKeyId:config.s3AccessKey ?: @""
                                                          secretAccessKey:config.s3SecretKey ?: @""];
        GZ_LOG_INFO(@"  Blob storage: S3 (%@)", config.s3Bucket);
    } else {
        NSURL *blobURL = [NSURL fileURLWithPath:config.blobDirectory];
        blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
        GZ_LOG_INFO(@"  Blob storage: disk (%@)", config.blobDirectory);
    }

    // Initialize blob uploader (remote to PDS)
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:config.pdsURL];

    // Initialize auth provider
    VideoJWTAuthProvider *authProvider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:config.serviceDID
                                                                                       pdsURL:config.pdsURL
                                                                                       plcURL:config.plcURL];

    // Initialize HLS generator
    ATProtoVideoHLSGenerator *hlsGenerator = [ATProtoVideoHLSGenerator sharedGenerator];
    if (config.hlsOutputDirectory) {
        hlsGenerator.outputBaseDirectory = config.hlsOutputDirectory;
    } else {
        // Default: store HLS files alongside the data directory
        hlsGenerator.outputBaseDirectory = [config.dataDirectory stringByAppendingPathComponent:@"hls"];
    }
    hlsGenerator.include1080p = config.hlsInclude1080p;

    NSString *hlsBaseUrl = config.hlsBaseUrl;
    if (!hlsBaseUrl) {
        // Default: serve HLS from this Jelcz instance
        hlsBaseUrl = [NSString stringWithFormat:@"http://localhost:%lu", (unsigned long)config.port];
    }

    GZ_LOG_INFO(@"  HLS output: %@", hlsGenerator.outputBaseDirectory);
    GZ_LOG_INFO(@"  HLS base URL: %@", hlsBaseUrl);

    // Initialize video worker
    gWorker = [ATProtoVideoWorker sharedWorker];
    gWorker.jobStore = database;
    gWorker.blobUploader = uploader;
    gWorker.blobProvider = blobProvider;
    gWorker.authProvider = authProvider;
    gWorker.maxConcurrentJobs = config.maxConcurrentJobs;
    gWorker.pollInterval = config.pollInterval;
    [gWorker setBlobProvider:blobProvider];
    gWorker.hlsGenerator = hlsGenerator;
    [gWorker start];

    // Initialize HTTP server
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
    [ATProtoVideoXrpcPack registerWithDispatcher:dispatcher
                                         jobStore:database
                                     authProvider:authProvider
                                    blobProvider:blobProvider];

    gServer = [HttpServer serverWithPort:config.port];

    // Register XRPC route handler
    void (^xrpcHandler)(HttpRequest *, HttpResponse *) = ^(HttpRequest *request, HttpResponse *response) {
        setJelczCORSHeaders(request, response);
        [dispatcher handleRequest:request response:response];
    };

    [gServer addRoute:@"OPTIONS" path:@"/xrpc" handler:xrpcHandler];
    [gServer addRoute:@"OPTIONS" path:@"/xrpc/*" handler:xrpcHandler];
    [gServer addRoute:@"POST" path:@"/xrpc" handler:xrpcHandler];
    [gServer addRoute:@"POST" path:@"/xrpc/*" handler:xrpcHandler];
    [gServer addRoute:@"GET" path:@"/xrpc" handler:xrpcHandler];
    [gServer addRoute:@"GET" path:@"/xrpc/*" handler:xrpcHandler];
    [gServer addHandlerForPath:@"/xrpc" handler:xrpcHandler];

    // Health endpoint
    [gServer addRoute:@"GET" path:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:@{@"status": @"ok"}];
    }];

    // HLS serving routes — serve generated HLS segments and playlists
    // Master playlist: /watch/{did}/{cid}/playlist.m3u8
    void (^watchHandler)(HttpRequest *, HttpResponse *) = ^(HttpRequest *request, HttpResponse *response) {
        setJelczCORSHeaders(request, response);
        if (request.method == HttpMethodOPTIONS) {
            response.statusCode = HttpStatusNoContent;
            [response setBodyData:[NSData data]];
            return;
        }

        NSString *path = request.path ?: @"";
        // Expect /watch/{did}/{cid}/... or /watch/{did}/{cid}/playlist.m3u8
        NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
        // parts: ["", "watch", did, cid, ...]
        if (parts.count < 5) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Invalid HLS path"}];
            return;
        }

        NSString *did = parts[2];
        NSString *cid = parts[3];
        NSString *remainder = [path substringFromIndex:[NSString stringWithFormat:@"/watch/%@/%@/", did, cid].length];
        if ([remainder containsString:@".."] || [remainder hasPrefix:@"/"]) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid HLS path"}];
            return;
        }

        NSString *filePath = nil;
        NSString *contentType = @"application/octet-stream";

        if ([remainder isEqualToString:@"playlist.m3u8"]) {
            // Master playlist
            filePath = [hlsGenerator masterPlaylistPathForDID:did cid:cid];
            contentType = @"application/vnd.apple.mpegurl";
        } else if ([remainder hasSuffix:@"/video.m3u8"] || [remainder hasSuffix:@".m3u8"]) {
            // Variant playlist
            filePath = [[hlsGenerator hlsDirectoryForDID:did cid:cid] stringByAppendingPathComponent:remainder];
            contentType = @"application/vnd.apple.mpegurl";
        } else if ([remainder hasSuffix:@".ts"]) {
            // Segment file
            filePath = [[hlsGenerator hlsDirectoryForDID:did cid:cid] stringByAppendingPathComponent:remainder];
            contentType = @"video/mp2t";
        } else if ([remainder isEqualToString:@"thumbnail.jpg"]) {
            // Thumbnail
            filePath = [hlsGenerator thumbnailPathForDID:did cid:cid];
            contentType = @"image/jpeg";
        }

        if (!filePath) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"HLS file not found"}];
            return;
        }

        NSData *fileData = [NSData dataWithContentsOfFile:filePath];
        if (!fileData) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"HLS file not found on disk"}];
            return;
        }

        response.statusCode = 200;
        response.contentType = contentType;
        // Cache HLS files for 1 hour (they're immutable once generated)
        [response setHeader:@"public, max-age=3600" forKey:@"Cache-Control"];
        [response setHeader:@"bytes" forKey:@"Accept-Ranges"];
        [response setBodyData:fileData];
    };
    [gServer addRoute:@"OPTIONS" path:@"/watch" handler:watchHandler];
    [gServer addRoute:@"OPTIONS" path:@"/watch/*" handler:watchHandler];
    [gServer addRoute:@"GET" path:@"/watch" handler:watchHandler];
    [gServer addRoute:@"GET" path:@"/watch/*" handler:watchHandler];

    // Admin auth helper
    NSString *adminSecret = [NSProcessInfo processInfo].environment[@"JELCZ_ADMIN_SECRET"] ?: @"jelcz-admin-secret";

    // Admin: list video jobs
    [gServer addRoute:@"GET" path:@"/admin/api/video/jobs" handler:^(HttpRequest *request, HttpResponse *response) {
        // Bearer token auth
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *token = [authHeader hasPrefix:@"Bearer "] ? [authHeader substringFromIndex:7] : nil;
        if (!token || ![token isEqualToString:adminSecret]) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"Unauthorized", @"message": @"Invalid or missing admin token"}];
            return;
        }

        NSString *stateFilter = [request queryParamForKey:@"state"];
        if (stateFilter.length == 0) stateFilter = nil;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSUInteger limit = limitStr.length > 0 ? (NSUInteger)limitStr.integerValue : 25;
        if (limit == 0 || limit > 100) limit = 25;

        NSString *cursorStr = [request queryParamForKey:@"cursor"];
        NSUInteger offset = cursorStr.length > 0 ? (NSUInteger)cursorStr.integerValue : 0;

        NSError *error = nil;
        NSArray<NSDictionary *> *jobs = [database listVideoJobsWithState:stateFilter limit:limit offset:offset error:&error];
        if (error) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"VideoJobListFailed", @"message": error.localizedDescription ?: @"Failed to list video jobs"}];
            return;
        }

        NSString *nextCursor = nil;
        if (jobs.count >= limit) {
            nextCursor = [NSString stringWithFormat:@"%lu", (unsigned long)(offset + limit)];
        }

        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:jobs ?: @[] forKey:@"jobs"];
        if (nextCursor) body[@"cursor"] = nextCursor;

        response.statusCode = 200;
        [response setJsonBody:[body copy]];
    }];

    // Admin: retry video job
    [gServer addRoute:@"POST" path:@"/admin/api/video/jobs/:jobId/retry" handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *token = [authHeader hasPrefix:@"Bearer "] ? [authHeader substringFromIndex:7] : nil;
        if (!token || ![token isEqualToString:adminSecret]) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"Unauthorized", @"message": @"Invalid or missing admin token"}];
            return;
        }

        NSString *jobId = request.pathParameters[@"jobId"];
        if (jobId.length == 0) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Job ID is required"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [database incrementVideoJobRetry:jobId error:&error];
        if (!success) {
            response.statusCode = 500;
            [response setJsonBody:@{@"error": @"VideoJobRetryFailed", @"message": error.localizedDescription ?: @"Failed to retry video job"}];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    NSError *startError = nil;
    if (![gServer startWithError:&startError]) {
        GZ_LOG_ERROR(@"Failed to start HTTP server: %@", startError);
        return 1;
    }

    GZ_LOG_INFO(@"Jelcz listening on port %lu", (unsigned long)config.port);

    // Run the run loop
    [[NSRunLoop currentRunLoop] run];

    return 0;
}

int main(int argc, const char *argv[]) {
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    @autoreleasepool {
        if (argc < 2) {
            print_usage();
            return 1;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];

        if ([command isEqualToString:@"serve"]) {
            return run_serve(argc, argv);
        } else if ([command isEqualToString:@"version"]) {
            printf("Jelcz 0.1.0 (AT Protocol Video Processing Service)\n");
            return 0;
        } else if ([command isEqualToString:@"status"]) {
            return run_status(argc, argv);
        } else if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            print_usage();
            return 0;
        } else {
            printf("Unknown command: %s\n\n", argv[1]);
            print_usage();
            return 1;
        }
    }
    return 0;
}
