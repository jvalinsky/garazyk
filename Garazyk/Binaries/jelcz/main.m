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
#import "CLI/GZCommandLineOptions.h"
#import "Runtime/GZServiceLifecycle.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"

static const char *executable_name = "jelcz";

static int fail_with_usage(NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\n\n", message.UTF8String);
    }
    JelczPrintUsage();
    return 1;
}

static BOOL help_requested_before_parse_error(NSArray<NSString *> *args) {
    NSSet<NSString *> *argFlags = [NSSet setWithObjects:
        @"--port", @"-p",
        @"--pds-url",
        @"--data-dir",
        @"--blob-dir",
        @"--did",
        @"--s3-bucket",
        @"--s3-region",
        @"--s3-endpoint",
        @"--hls-dir",
        @"--hls-base-url",
        nil];
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([argFlags containsObject:arg]) {
            if (i + 1 >= args.count) {
                return NO;
            }
            i++;
        } else if ([arg isEqualToString:@"--hls-1080p"] ||
                   [arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
        } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            return YES;
        } else {
            return NO;
        }
    }
    return NO;
}

/// Queries `/_health` on a running Jelcz instance.
static int run_status(NSArray<NSString *> *args) {
    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    [parser registerOptions:@[
        [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO]
    ] forCommand:@"status"];

    NSError *error = nil;
    NSDictionary<NSString *, id> *parsedArgs = [parser parseArguments:args forCommand:@"status" error:&error];
    if (!parsedArgs) {
        return fail_with_usage(error.localizedDescription);
    }

    NSUInteger port = 2586;
    if (parsedArgs[@"port"]) {
        NSInteger parsedPort = [parsedArgs[@"port"] integerValue];
        if (parsedPort <= 0) {
            return fail_with_usage(@"Port must be a positive integer");
        }
        port = (NSUInteger)parsedPort;
    }

    NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%lu/_health", (unsigned long)port];
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

static int run_serve(NSArray<NSString *> *args) {
    if (help_requested_before_parse_error(args)) {
        JelczPrintUsage();
        return 0;
    }

    GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
    [parser registerOptions:@[
        [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"pds-url" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"blob-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"did" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"s3-bucket" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"s3-region" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"s3-endpoint" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"hls-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"hls-base-url" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"hls-1080p" shortName:nil type:GZCommandLineOptionTypeBoolean isRequired:NO],
        [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO],
    ] forCommand:@"serve"];

    NSError *parseError = nil;
    NSDictionary<NSString *, id> *parsedArgs = [parser parseArguments:args
                                                              forCommand:@"serve"
                                                                   error:&parseError];
    if (!parsedArgs) {
        return fail_with_usage(parseError.localizedDescription);
    }

    NSString *portString = parsedArgs[@"port"];
    if (portString && portString.integerValue <= 0) {
        return fail_with_usage(@"Port must be a positive integer");
    }

    if ([parsedArgs[@"verbose"] boolValue]) {
        [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
    }

    // Build config from env + CLI overrides
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
    if (parsedArgs[@"port"]) config.port = [parsedArgs[@"port"] integerValue];
    if (parsedArgs[@"pds-url"]) config.pdsURL = parsedArgs[@"pds-url"];
    if (parsedArgs[@"data-dir"]) config.dataDirectory = parsedArgs[@"data-dir"];
    if (parsedArgs[@"blob-dir"]) config.blobDirectory = parsedArgs[@"blob-dir"];
    if (parsedArgs[@"did"]) config.serviceDID = parsedArgs[@"did"];
    if (parsedArgs[@"s3-bucket"]) config.s3Bucket = parsedArgs[@"s3-bucket"];
    if (parsedArgs[@"s3-region"]) config.s3Region = parsedArgs[@"s3-region"];
    if (parsedArgs[@"s3-endpoint"]) config.s3Endpoint = parsedArgs[@"s3-endpoint"];
    if (parsedArgs[@"hls-dir"]) config.outputDirectory = parsedArgs[@"hls-dir"];
    if (parsedArgs[@"hls-base-url"]) config.outputBaseUrl = parsedArgs[@"hls-base-url"];
    if ([parsedArgs[@"hls-1080p"] boolValue]) config.includeHighQuality = YES;

    GZ_LOG_INFO(@"Jelcz video processing service starting (port %lu)", (unsigned long)config.port);

    // Create video processor
    ATProtoVideoProcessor *videoProcessor = [[ATProtoVideoProcessor alloc] init];
    videoProcessor.outputBaseUrl = config.outputBaseUrl ?: [NSString stringWithFormat:@"http://localhost:%lu", (unsigned long)config.port];
    videoProcessor.include1080p = config.includeHighQuality;

    // Boot the framework runtime
    ATProtoMediaServiceRuntime *runtime = [[ATProtoMediaServiceRuntime alloc] initWithConfiguration:config processor:videoProcessor];

    // Configure HLS generator
    ATProtoVideoHLSGenerator *hlsGenerator = [ATProtoVideoHLSGenerator sharedGenerator];
    hlsGenerator.outputBaseDirectory = config.outputDirectory ?: [config.dataDirectory stringByAppendingPathComponent:@"hls"];
    hlsGenerator.include1080p = config.includeHighQuality;

    // Register video-specific HLS serving routes on the runtime's HTTP server
    registerHLSRoutes(runtime.httpServer, hlsGenerator);

    return [GZServiceLifecycle runServiceWithRuntime:runtime
                                         serviceName:@"Jelcz video processing service"
                                             onStart:^{
        GZ_LOG_INFO(@"Jelcz listening on port %lu", (unsigned long)config.port);
    }
                                     announceSignals:NO];
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    [GZServiceLifecycle bootstrapWithExecutableName:executable_name];
    [GZCrashReporter installCrashHandlersWithExecutableName:executable_name];
    @autoreleasepool {
        if (argc < 2) {
            JelczPrintUsage();
            return 1;
        }
        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            JelczPrintUsage();
            return 0;
        }
        if ([command isEqualToString:@"version"]) {
            printf("Jelcz 0.2.0 (AT Protocol Video Processing Service - ATProtoMediaCore)\n");
            return 0;
        }

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if ([command isEqualToString:@"serve"]) {
            return run_serve(args);
        } else if ([command isEqualToString:@"status"]) {
            return run_status(args);
        } else {
            printf("Unknown command: %s\n\n", argv[1]);
            JelczPrintUsage();
            return 1;
        }
    }
    return 0;
}
