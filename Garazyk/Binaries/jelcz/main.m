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
#import "Blob/PDSDiskBlobProvider.h"
#import "Blob/PDSCloudStorageBlobProvider.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Debug/PDSLogger.h"

static HttpServer *gServer = nil;
static ATProtoVideoWorker *gWorker = nil;

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
    PDS_LOG_INFO(@"Received signal %d, shutting down...", sig);
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
        } else if ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]) {
            // Enable debug logging
        }
    }

    PDS_LOG_INFO(@"Jelcz video processing service starting");
    PDS_LOG_INFO(@"  Port: %lu", (unsigned long)config.port);
    PDS_LOG_INFO(@"  PDS URL: %@", config.pdsURL);
    PDS_LOG_INFO(@"  Service DID: %@", config.serviceDID);
    PDS_LOG_INFO(@"  Data dir: %@", config.dataDirectory);
    PDS_LOG_INFO(@"  Blob dir: %@", config.blobDirectory);

    // Initialize database
    NSString *dbPath = [config.dataDirectory stringByAppendingPathComponent:@"jelcz.db"];
    NSError *error = nil;
    JelczDatabase *database = [[JelczDatabase alloc] initWithDatabasePath:dbPath error:&error];
    if (!database) {
        PDS_LOG_ERROR(@"Failed to open database: %@", error);
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
        PDS_LOG_INFO(@"  Blob storage: S3 (%@)", config.s3Bucket);
    } else {
        NSURL *blobURL = [NSURL fileURLWithPath:config.blobDirectory];
        blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:blobURL];
        PDS_LOG_INFO(@"  Blob storage: disk (%@)", config.blobDirectory);
    }

    // Initialize blob uploader (remote to PDS)
    VideoRemoteBlobUploader *uploader = [[VideoRemoteBlobUploader alloc] initWithPDSURL:config.pdsURL];

    // Initialize auth provider
    VideoJWTAuthProvider *authProvider = [[VideoJWTAuthProvider alloc] initWithExpectedAudience:config.serviceDID
                                                                                       pdsURL:config.pdsURL
                                                                                       plcURL:config.plcURL];

    // Initialize video worker
    gWorker = [ATProtoVideoWorker sharedWorker];
    gWorker.jobStore = database;
    gWorker.blobUploader = uploader;
    gWorker.blobProvider = blobProvider;
    gWorker.authProvider = authProvider;
    gWorker.maxConcurrentJobs = config.maxConcurrentJobs;
    gWorker.pollInterval = config.pollInterval;
    [gWorker setBlobProvider:blobProvider];
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
        [dispatcher handleRequest:request response:response];
    };

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
        PDS_LOG_ERROR(@"Failed to start HTTP server: %@", startError);
        return 1;
    }

    PDS_LOG_INFO(@"Jelcz listening on port %lu", (unsigned long)config.port);

    // Run the run loop
    [[NSRunLoop currentRunLoop] run];

    return 0;
}

int main(int argc, const char *argv[]) {
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
            printf("Status: not implemented\n");
            return 0;
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
