// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @brief Entry point for the Jelcz video processing service.

 @discussion Standalone AT Protocol video processing side-car service powered by
 the ATProtoMediaCore framework.  Accepts video uploads via app.bsky.video.*
 XRPC endpoints, processes them asynchronously (transcode + thumbnail + HLS),
 and uploads completed blobs to the user's PDS via Service Auth.

 Named after Jelcz, a Polish vehicle manufacturer known for
 buses and trucks produced 1952–2008.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <execinfo.h>
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif
#import "MediaCore/ATProtoMediaServiceRuntime.h"
#import "MediaCore/ATProtoMediaServiceConfiguration.h"
#import "Video/ATProtoVideoProcessor.h"
#import "Video/VideoHLSGenerator.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"
#import "MediaCore/JelczCLI.h"

static ATProtoMediaServiceRuntime *gRuntime = nil;

#pragma mark - Signal Handling

static void crash_signal_handler(int sig) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  :
                          (sig == SIGTRAP) ? "SIGTRAP" : "UNKNOWN";
    char buf[256];
    int len = snprintf(buf, sizeof(buf), "\n=== FATAL SIGNAL %s (%d) in jelcz ===\n", signame, sig);
    write(STDERR_FILENO, buf, (size_t)len);
    int fd = open("/tmp/jelcz-crash.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        write(fd, buf, (size_t)len);
        void *frames[32];
        int frame_count = (int)backtrace(frames, 32);
        for (int i = 0; i < frame_count; i++) {
            char frame_buf[64];
            int flen = snprintf(frame_buf, sizeof(frame_buf), "  #%d %p\n", i, frames[i]);
            write(fd, frame_buf, (size_t)flen);
        }
        char **symbols = backtrace_symbols(frames, frame_count);
        if (symbols) {
            for (int i = 0; i < frame_count; i++) {
                char sym_buf[256];
                int slen = snprintf(sym_buf, sizeof(sym_buf), "  #%d %s\n", i, symbols[i] ?: "?");
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
    int fd = open("/tmp/jelcz-crash.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char buf[1024];
        int len = snprintf(buf, sizeof(buf), "=== UNCAUGHT EXCEPTION ===\nName: %s\nReason: %s\n",
            exception.name.UTF8String ?: "?", exception.reason.UTF8String ?: "?");
        write(fd, buf, (size_t)len);
        close(fd);
    }
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
    [gRuntime stop];
    exit(0);
}



/// Queries `/_health` on a running Jelcz instance.
static int run_status(int argc, const char *argv[]) {
    NSUInteger port = 2586;
    for (int i = 2; i < argc; i++) {
        NSString *arg = [NSString stringWithUTF8String:argv[i]];
        if ([arg isEqualToString:@"--port"] && i + 1 < argc) {
            port = [[NSString stringWithUTF8String:argv[++i]] integerValue];
        }
    }
    NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%lu/_health", (unsigned long)port];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlString] options:0 error:&error];
    if (!data) {
        printf("Jelcz status: NOT RUNNING (port %lu)\n", (unsigned long)port);
        if (error) printf("  Error: %s\n", error.localizedDescription.UTF8String);
        return 1;
    }
    printf("Jelcz status: RUNNING (port %lu)\n", (unsigned long)port);
    return 0;
}

#pragma mark - HLS Serving

static void registerHLSRoutes(HttpServer *server, ATProtoVideoHLSGenerator *hlsGenerator) {
    __weak typeof(hlsGenerator) weakGen = hlsGenerator;
    void (^setCORS)(HttpRequest *, HttpResponse *) = ^(HttpRequest *request, HttpResponse *response) {
        NSString *origin = [request headerForKey:@"Origin"];
        if (origin.length > 0) {
            [response setHeader:origin forKey:@"Access-Control-Allow-Origin"];
            [response setHeader:@"true" forKey:@"Access-Control-Allow-Credentials"];
            [response setHeader:@"Origin" forKey:@"Vary"];
        } else {
            [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        }
        [response setHeader:@"GET, POST, OPTIONS, HEAD" forKey:@"Access-Control-Allow-Methods"];
        [response setHeader:@"Authorization, Content-Type, Accept, Range, *" forKey:@"Access-Control-Allow-Headers"];
        [response setHeader:@"Content-Length, Content-Range, Accept-Ranges" forKey:@"Access-Control-Expose-Headers"];
        [response setHeader:@"true" forKey:@"Access-Control-Allow-Private-Network"];
        [response setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
    };

    void (^watchHandler)(HttpRequest *, HttpResponse *) = ^(HttpRequest *request, HttpResponse *response) {
        setCORS(request, response);
        if (request.method == HttpMethodOPTIONS) {
            response.statusCode = HttpStatusNoContent;
            [response setBodyData:[NSData data]];
            return;
        }
        NSString *path = request.path ?: @"";
        if (path.length < 12) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Invalid path"}];
            return;
        }
        // Strip /watch/ prefix, split into did/cid/remainder
        NSString *suffix = [path substringFromIndex:7];
        NSArray<NSString *> *parts = [suffix componentsSeparatedByString:@"/"];
        if (parts.count < 3) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Invalid HLS path"}];
            return;
        }
        NSString *did = parts[0];
        NSString *cid = parts[1];
        NSString *remainder = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"/"];

        if ([remainder containsString:@".."] || [remainder hasPrefix:@"/"]) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Invalid HLS path"}];
            return;
        }

        NSString *filePath = nil;
        NSString *contentType = @"application/octet-stream";
        ATProtoVideoHLSGenerator *gen = weakGen;

        if ([remainder isEqualToString:@"playlist.m3u8"]) {
            filePath = [gen masterPlaylistPathForDID:did cid:cid];
            contentType = @"application/vnd.apple.mpegurl";
        } else if ([remainder hasSuffix:@"/video.m3u8"] || [remainder hasSuffix:@".m3u8"]) {
            filePath = [[gen hlsDirectoryForDID:did cid:cid] stringByAppendingPathComponent:remainder];
            contentType = @"application/vnd.apple.mpegurl";
        } else if ([remainder hasSuffix:@".ts"]) {
            filePath = [[gen hlsDirectoryForDID:did cid:cid] stringByAppendingPathComponent:remainder];
            contentType = @"video/mp2t";
        } else if ([remainder isEqualToString:@"thumbnail.jpg"]) {
            filePath = [gen thumbnailPathForDID:did cid:cid];
            contentType = @"image/jpeg";
        }

        if (!filePath || ![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"HLS file not found"}];
            return;
        }
        response.statusCode = 200;
        response.contentType = contentType;
        [response setHeader:@"public, max-age=3600" forKey:@"Cache-Control"];
        [response setHeader:@"bytes" forKey:@"Accept-Ranges"];
        [response setBodyFileAtPath:filePath deleteAfterSend:NO];
    };

    // Only register wildcard routes — bare /watch without trailing slash would
    // always 404 (the handler strips 7 chars for "/watch/").
    [server addRoute:@"OPTIONS" path:@"/watch/*" handler:watchHandler];
    [server addRoute:@"GET" path:@"/watch/*" handler:watchHandler];
}

#pragma mark - Serve

int run_serve(int argc, const char *argv[]) {
    install_crash_handlers();
    signal(SIGINT, handleSignal);
    signal(SIGTERM, handleSignal);

    // Build config from env + CLI overrides
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    for (int i = 2; i < argc; i++) {
        NSString *arg = [NSString stringWithUTF8String:argv[i]];
        if ([arg isEqualToString:@"--port"] && i + 1 < argc)
            config.port = [[NSString stringWithUTF8String:argv[++i]] integerValue];
        else if ([arg isEqualToString:@"--pds-url"] && i + 1 < argc)
            config.pdsURL = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--data-dir"] && i + 1 < argc)
            config.dataDirectory = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--blob-dir"] && i + 1 < argc)
            config.blobDirectory = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--did"] && i + 1 < argc)
            config.serviceDID = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--s3-bucket"] && i + 1 < argc)
            config.s3Bucket = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--s3-region"] && i + 1 < argc)
            config.s3Region = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--s3-endpoint"] && i + 1 < argc)
            config.s3Endpoint = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--hls-dir"] && i + 1 < argc)
            config.outputDirectory = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--hls-base-url"] && i + 1 < argc)
            config.outputBaseUrl = [NSString stringWithUTF8String:argv[++i]];
        else if ([arg isEqualToString:@"--hls-1080p"])
            config.includeHighQuality = YES;
    }

    GZ_LOG_INFO(@"Jelcz video processing service starting (port %lu)", (unsigned long)config.port);

    // Create video processor
    ATProtoVideoProcessor *videoProcessor = [[ATProtoVideoProcessor alloc] init];
    videoProcessor.outputBaseUrl = config.outputBaseUrl ?: [NSString stringWithFormat:@"http://localhost:%lu", (unsigned long)config.port];
    videoProcessor.include1080p = config.includeHighQuality;

    // Boot the framework runtime
    gRuntime = [[ATProtoMediaServiceRuntime alloc] initWithConfiguration:config processor:videoProcessor];
    NSError *error = nil;
    if (![gRuntime startWithError:&error]) {
        GZ_LOG_ERROR(@"Failed to start runtime: %@", error);
        return 1;
    }

    // Configure HLS generator
    ATProtoVideoHLSGenerator *hlsGenerator = [ATProtoVideoHLSGenerator sharedGenerator];
    hlsGenerator.outputBaseDirectory = config.outputDirectory ?: [config.dataDirectory stringByAppendingPathComponent:@"hls"];
    hlsGenerator.include1080p = config.includeHighQuality;

    // Register video-specific HLS serving routes on the runtime's HTTP server
    registerHLSRoutes(gRuntime.httpServer, hlsGenerator);

    GZ_LOG_INFO(@"Jelcz listening on port %lu", (unsigned long)config.port);
    [[NSRunLoop currentRunLoop] run];
    return 0;
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    @autoreleasepool {
        if (argc < 2) { JelczPrintUsage(); return 1; }
        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"serve"])
            return run_serve(argc, argv);
        else if ([command isEqualToString:@"version"]) {
            printf("Jelcz 0.2.0 (AT Protocol Video Processing Service - ATProtoMediaCore)\n");
            return 0;
        } else if ([command isEqualToString:@"status"])
            return run_status(argc, argv);
        else if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            JelczPrintUsage(); return 0;
        } else {
            printf("Unknown command: %s\n\n", argv[1]); JelczPrintUsage(); return 1;
        }
    }
    return 0;
}
