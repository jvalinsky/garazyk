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
#import "MediaCore/ATProtoMediaWorker.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "Video/GZJelczStreamplaceBlobFetcher.h"
#import "Video/GZJelczStreamplaceOriginHints.h"
#import "Video/GZJelczStreamplaceCompatServe.h"
#import "Video/GZJelczStreamplacePeerDemo.h"
#import "Video/GZJelczPeerProviderIndex.h"
#import "Video/GZJelczOriginAnnouncer.h"
#import "Core/CID.h"
#import "Blob/PDSBlobProvider.h"
#import "Blob/PDSDiskBlobProvider.h"
#import "Blob/PDSCloudStorageBlobProvider.h"
#import "Video/ATProtoVideoProcessor.h"
#import "Video/VideoHLSGenerator.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/XrpcHandler.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Debug/GZLogger.h"
#import "MediaCore/JelczCLI.h"
#import "CLI/GZCommandLineOptions.h"
#import "Runtime/GZServiceLifecycle.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Video/AdminUI/JelczAdminUIPack.h"
#import "Video/AdminUI/JelczAdminEmbedContext.h"

/** Adapts ATProtoSafeHTTPClient to MediaCore's injectable HTTP surface. */
@interface GZJelczCAMirrorHTTPAdapter : NSObject <ATProtoCAMirrorHTTPClient>
@end

@implementation GZJelczCAMirrorHTTPAdapter
- (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                           options:(id)options
                          response:(NSHTTPURLResponse **)response
                             error:(NSError **)error {
    return [[ATProtoSafeHTTPClient sharedClient]
        sendSynchronousRequest:request
                       options:(ATProtoSafeHTTPClientOptions *)options
                      response:response
                         error:error];
}
@end

/** Tries Streamplace getVideoBlob first, then RASL well-known. */
@interface GZJelczCAMirrorCompositeFetcher : NSObject <ATProtoCAMirrorFetching>
@property (nonatomic, strong) id<ATProtoCAMirrorFetching> primary;
@property (nonatomic, strong, nullable) id<ATProtoCAMirrorFetching> secondary;
@end

@implementation GZJelczCAMirrorCompositeFetcher
- (NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                         providers:(NSArray<NSString *> *)providers
                             error:(NSError **)error {
    NSError *primaryError = nil;
    NSData *data = [self.primary fetchObjectBytesForCID:cid providers:providers error:&primaryError];
    if (data) {
        return data;
    }
    if (self.secondary) {
        NSError *secondaryError = nil;
        data = [self.secondary fetchObjectBytesForCID:cid providers:providers error:&secondaryError];
        if (data) {
            return data;
        }
        if (error) {
            *error = secondaryError ?: primaryError;
        }
        return nil;
    }
    if (error) {
        *error = primaryError;
    }
    return nil;
}
@end

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

static void registerHLSRoutes(ATProtoHttpServer *server, ATProtoVideoHLSGenerator *hlsGenerator) {
    __weak typeof(hlsGenerator) weakGen = hlsGenerator;
    void (^setCORS)(ATProtoHttpRequest *, ATProtoHttpResponse *) = ^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
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

    void (^watchHandler)(ATProtoHttpRequest *, ATProtoHttpResponse *) = ^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
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
        [GZCommandLineOption optionWithLongName:@"admin-password-file" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
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
    videoProcessor.enableContentAddressedManifest = config.enableContentAddressedManifest;
    BOOL needCAStore = config.enableContentAddressedManifest
        || config.enableStreamplaceServeCompat
        || config.enableStreamplacePeerDemo
        || (config.enableCAMirrorFetch && config.streamplaceMirrorBase.length > 0)
        || ([[[NSProcessInfo processInfo] environment][@"JELCZ_PEER_HTTPS_PROVIDERS"] length] > 0);
    if (needCAStore) {
        NSString *caRoot = config.caObjectStoreDirectory;
        if (caRoot.length == 0) {
            caRoot = [config.dataDirectory stringByAppendingPathComponent:@"ca-objects"];
        }
        NSError *caError = nil;
        ATProtoCAObjectStore *caStore = [[ATProtoCAObjectStore alloc] initWithRootDirectory:caRoot error:&caError];
        if (!caStore) {
            GZ_LOG_ERROR(@"Failed to open CA object store at %@: %@", caRoot, caError);
            return 1;
        }
        videoProcessor.caObjectStore = caStore;
        if (config.enableContentAddressedManifest) {
            GZ_LOG_INFO(@"  CA manifest: enabled (store %@)", caRoot);
        } else {
            GZ_LOG_INFO(@"  CA store: enabled for Streamplace peership/demo (store %@)", caRoot);
        }
    } else {
        GZ_LOG_INFO(@"  CA manifest: disabled (set JELCZ_CA_MANIFEST=1 to enable)");
    }

    // Select the blob storage backend. MediaCore only depends on the
    // id<PDSBlobProvider> protocol, so the concrete backend is chosen and
    // constructed here, where the whole library set is already linked.
    id<PDSBlobProvider> blobProvider;
    if (config.s3Bucket) {
        blobProvider = [[PDSCloudStorageBlobProvider alloc] initWithBucket:config.s3Bucket
                                                                     region:config.s3Region
                                                                   endpoint:config.s3Endpoint
                                                                  keyPrefix:@"blobs/"
                                                                accessKeyId:config.s3AccessKey ?: @""
                                                            secretAccessKey:config.s3SecretKey ?: @""];
    } else {
        blobProvider = [[PDSDiskBlobProvider alloc] initWithStorageDirectory:[NSURL fileURLWithPath:config.blobDirectory]];
    }

    // Boot the framework runtime
    ATProtoMediaServiceRuntime *runtime = [[ATProtoMediaServiceRuntime alloc] initWithConfiguration:config
                                                                                           processor:videoProcessor
                                                                                        blobProvider:blobProvider];

    // Merge Streamplace operator base into mirror providers (WS15).
    if (config.enableStreamplacePeerDemo && config.streamplaceMirrorBase.length == 0) {
        config.streamplaceMirrorBase = @"https://stream.place";
    }
    if (config.enableStreamplacePeerDemo && config.streamplaceAttributionDID.length == 0) {
        config.streamplaceAttributionDID = @"did:web:stream.place";
    }
    NSString *streamplaceBase =
        [GZJelczStreamplaceOriginHints normalizedProviderBaseURL:config.streamplaceMirrorBase];

    // WS16 Phase 2: operator HTTPS peers + optional origins JSON (consent-gated).
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSArray<NSString *> *envPeers =
        [GZJelczPeerProviderIndex parseCSVBases:env[@"JELCZ_PEER_HTTPS_PROVIDERS"]];
    NSSet *allowedStreamers =
        [GZJelczPeerProviderIndex allowlistSetFromCSV:env[@"JELCZ_P2P_ALLOWED_STREAMERS"]];
    NSSet *allowedBroadcasters =
        [GZJelczPeerProviderIndex allowlistSetFromCSV:env[@"JELCZ_P2P_ALLOWED_BROADCASTERS"]];
    NSArray<GZJelczPeerProviderEntry *> *originEntries = @[];
    NSString *originsPath = env[@"JELCZ_PEER_ORIGINS_JSON"];
    if (originsPath.length > 0) {
        NSData *data = [NSData dataWithContentsOfFile:originsPath];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        originEntries =
            [GZJelczPeerProviderIndex entriesFromOriginsJSONObject:json
                                                configuredBaseURL:streamplaceBase];
        GZ_LOG_INFO(@"  Peer origins JSON: %lu entries from %@",
                     (unsigned long)originEntries.count, originsPath);
    }
    NSArray<NSString *> *mergedProviders =
        [GZJelczPeerProviderIndex httpsProviderBasesWithBootstrap:streamplaceBase
                                                     envPeerBases:envPeers
                                                    originEntries:originEntries
                                                 allowedStreamers:allowedStreamers
                                              allowedBroadcasters:allowedBroadcasters];
    if (mergedProviders.count > 0) {
        config.caMirrorProviders = mergedProviders;
        GZ_LOG_INFO(@"  HTTPS peer providers (%lu): %@",
                     (unsigned long)mergedProviders.count,
                     [mergedProviders componentsJoinedByString:@", "]);
    } else if (streamplaceBase.length > 0) {
        config.caMirrorProviders =
            [GZJelczStreamplaceOriginHints providersByMergingStreamplaceBase:streamplaceBase
                                                          existingProviders:config.caMirrorProviders];
    }
    if (streamplaceBase.length > 0 && config.streamplaceAttributionDID.length == 0) {
        GZ_LOG_WARN(@"JELCZ_STREAMPLACE_MIRROR_BASE set without JELCZ_STREAMPLACE_ATTRIBUTION_DID; "
                    @"Streamplace getVideoBlob mirror fetch will not be wired");
    }

    __block GZJelczStreamplaceBlobFetcher *streamplaceFetcher = nil;
    __block GZJelczStreamplaceCompatServe *streamplaceCompat = nil;
    __block GZJelczStreamplacePeerDemo *peerDemo = nil;
    BOOL wantBlobServe = config.enableStreamplaceServeCompat || config.enableStreamplacePeerDemo;
    if (videoProcessor.caObjectStore && wantBlobServe) {
        streamplaceCompat =
            [[GZJelczStreamplaceCompatServe alloc] initWithObjectStore:videoProcessor.caObjectStore];
        if (config.enableStreamplacePeerDemo && streamplaceBase.length > 0) {
            NSString *publicBase =
                [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)config.port];
            id<ATProtoCAMirrorHTTPClient> demoHTTP = [[GZJelczCAMirrorHTTPAdapter alloc] init];
            peerDemo = [[GZJelczStreamplacePeerDemo alloc] initWithObjectStore:videoProcessor.caObjectStore
                                                                    httpClient:demoHTTP
                                                               upstreamBaseURL:streamplaceBase
                                                                 publicBaseURL:publicBase];
            peerDemo.peerHTTPSProviders = envPeers ?: @[];
            peerDemo.originEntries = originEntries;
            peerDemo.allowedStreamers = allowedStreamers;
            peerDemo.allowedBroadcasters = allowedBroadcasters;
            BOOL announceOn = [env[@"JELCZ_ORIGIN_ANNOUNCE"] isEqualToString:@"1"]
                || [env[@"JELCZ_ORIGIN_ANNOUNCE"] isEqualToString:@"true"]
                || [env[@"JELCZ_ORIGIN_ANNOUNCE"] isEqualToString:@"yes"];
            NSString *announceId = env[@"JELCZ_ORIGIN_ANNOUNCE_IDENTIFIER"];
            NSString *announcePass = env[@"JELCZ_ORIGIN_ANNOUNCE_APP_PASSWORD"];
            if (announceOn && announceId.length > 0 && announcePass.length > 0) {
                NSString *pds =
                    env[@"JELCZ_ORIGIN_ANNOUNCE_PDS_URL"] ?: config.pdsURL ?: @"http://127.0.0.1:2583";
                NSString *serverDID =
                    env[@"JELCZ_ORIGIN_ANNOUNCE_SERVER_DID"] ?: config.serviceDID ?: @"did:web:localhost";
                GZJelczOriginAnnouncer *ann =
                    [[GZJelczOriginAnnouncer alloc] initWithHTTPClient:demoHTTP
                                                            pdsBaseURL:pds
                                                            identifier:announceId
                                                           appPassword:announcePass
                                                             serverDID:serverDID];
                ann.httpsBase = env[@"JELCZ_ORIGIN_ANNOUNCE_HTTPS_BASE"] ?: publicBase;
                ann.irohTicket = env[@"JELCZ_ORIGIN_ANNOUNCE_IROH_TICKET"];
                peerDemo.originAnnouncer = ann;
                GZ_LOG_INFO(@"  Origin announce: enabled (remote PDS write → %@ as %@)",
                             pds, announceId);
            } else if (announceOn) {
                GZ_LOG_WARN(@"JELCZ_ORIGIN_ANNOUNCE set without IDENTIFIER/APP_PASSWORD; announce off");
            }
        }
        runtime.additionalXrpcSetup = ^(ATProtoXrpcDispatcher *dispatcher) {
            [dispatcher registerMethod:kGZXrpcNSID_place_stream_playback_getVideoBlob
                               handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
                                   if (peerDemo) {
                                       [peerDemo serveBlobForRequest:request response:response error:nil];
                                       return;
                                   }
                                   [streamplaceCompat handleRequest:request response:response error:nil];
                               }];
        };
        GZ_LOG_INFO(@"  Streamplace getVideoBlob serve: enabled%@",
                    peerDemo ? @" (demo local+proxy)" : @" (local CA only)");
    }

    if (videoProcessor.caObjectStore) {
        runtime.caObjectStore = videoProcessor.caObjectStore;
        if (config.enableCAMirrorFetch) {
            id<ATProtoCAMirrorHTTPClient> http =
                [[GZJelczCAMirrorHTTPAdapter alloc] init];
            ATProtoCAMirrorHTTPSFetcher *raslFetcher =
                [[ATProtoCAMirrorHTTPSFetcher alloc] initWithHTTPClient:http];
            id<ATProtoCAMirrorFetching> fetcher = raslFetcher;
            if (streamplaceBase.length > 0 && config.streamplaceAttributionDID.length > 0) {
                streamplaceFetcher =
                    [[GZJelczStreamplaceBlobFetcher alloc] initWithHTTPClient:http
                                                              attributionDID:config.streamplaceAttributionDID];
                GZJelczCAMirrorCompositeFetcher *composite =
                    [[GZJelczCAMirrorCompositeFetcher alloc] init];
                composite.primary = streamplaceFetcher;
                composite.secondary = raslFetcher;
                fetcher = composite;
                GZ_LOG_INFO(@"  CA mirror fetch: Streamplace getVideoBlob + RASL (%lu providers)",
                             (unsigned long)config.caMirrorProviders.count);
            } else {
                GZ_LOG_INFO(@"  CA mirror fetch: RASL fetcher wired (%lu providers)",
                             (unsigned long)config.caMirrorProviders.count);
            }
            runtime.caMirrorFetcher = fetcher;
        }
    }

    // Configure HLS generator
    ATProtoVideoHLSGenerator *hlsGenerator = [ATProtoVideoHLSGenerator sharedGenerator];
    hlsGenerator.outputBaseDirectory = config.outputDirectory ?: [config.dataDirectory stringByAppendingPathComponent:@"hls"];
    hlsGenerator.include1080p = config.includeHighQuality;
    NSString *ffmpegPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"JELCZ_FFMPEG_PATH"];
    if (ffmpegPath.length == 0) {
        ffmpegPath = @"/opt/homebrew/bin/ffmpeg";
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:ffmpegPath]) {
            ffmpegPath = @"/usr/local/bin/ffmpeg";
            if (![[NSFileManager defaultManager] isExecutableFileAtPath:ffmpegPath]) {
                ffmpegPath = @"ffmpeg";
            }
        }
    }
    hlsGenerator.ffmpegPath = ffmpegPath;
    GZ_LOG_INFO(@"  FFmpeg: %@", ffmpegPath);

    // HLS /watch/* routes are registered in onStart — httpServer is nil until start.

    // --- Embedded admin UI listener ---
    NSString *adminPassword = nil;
    NSString *adminPasswordFile = parsedArgs[@"admin-password-file"];
    if (adminPasswordFile.length > 0) {
        adminPassword = [NSString stringWithContentsOfFile:adminPasswordFile
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
        adminPassword = [adminPassword stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if (adminPassword.length == 0) {
        adminPassword = [[[NSProcessInfo processInfo] environment]
                         objectForKey:@"JELCZ_ADMIN_PASSWORD"];
    }

    GZAdminUIHost *adminUIHost = nil;
    __block GZJelczAdminEmbedContext *embedContext = nil;
    if (adminPassword.length > 0) {
        GZAdminUIServiceConfig *adminConfig = [[GZAdminUIServiceConfig alloc] init];
        adminConfig.host = @"127.0.0.1";
        adminConfig.port = 2597;
        adminConfig.adminPassword = adminPassword;
        adminConfig.serviceIdentifier = @"video";

        adminUIHost = [[GZAdminUIHost alloc] initWithConfiguration:adminConfig
                                                              packs:@[GZJelczAdminUIPack.class]];

        embedContext = [[GZJelczAdminEmbedContext alloc]
            initWithWorker:nil
                  jobStore:nil
                    config:@{
                        @"maxUploadSize": @(50 * 1024 * 1024),
                        @"maxDuration": @(180),
                        @"enableContentAddressedManifest": @(config.enableContentAddressedManifest),
                        @"caObjectStoreConfigured": @(videoProcessor.caObjectStore != nil),
                        @"enableCAMirrorFetch": @(config.enableCAMirrorFetch),
                        @"caMirrorProviderCount": @(config.caMirrorProviders.count),
                        @"caObjectSweepEnabled": @(config.caObjectSweepEnabled),
                        @"enableMUXLPresentation": @(videoProcessor.enableMUXLPresentation),
                        @"storageBackend": config.s3Bucket.length > 0 ? @"s3" : @"disk",
                        @"streamplaceMirrorConfigured": @(streamplaceBase.length > 0),
                        @"streamplaceAttributionDIDConfigured":
                            @(config.streamplaceAttributionDID.length > 0),
                        @"streamplaceServeCompat": @(config.enableStreamplaceServeCompat),
                        @"streamplaceFetchSuccessCount": @0,
                        @"streamplaceBlobNotFoundCount": @0,
                        @"streamplaceFetchFailureCount": @0,
                    }
                 startTime:[NSDate date]];
        [GZJelczAdminUIPack configureHost:adminUIHost embedContext:embedContext];

        NSError *adminErr = nil;
        if (![adminUIHost startWithError:&adminErr]) {
            GZ_LOG_WARN(@"Jelcz admin UI failed to start: %@", adminErr.localizedDescription);
        } else {
            GZ_LOG_INFO(@"Jelcz admin UI listening on 127.0.0.1:%lu", (unsigned long)adminConfig.port);
        }
    } else {
        GZ_LOG_INFO(@"Jelcz admin UI disabled: set JELCZ_ADMIN_PASSWORD or --admin-password-file");
    }

    return [GZServiceLifecycle runServiceWithRuntime:runtime
                                         serviceName:@"Jelcz video processing service"
                                             onStart:^{
        // Filesystem HLS /watch only when CA manifests are off. When CA is on,
        // ATProtoMediaServiceRuntime already registered MASL-backed /watch/*.
        if (!config.enableContentAddressedManifest) {
            registerHLSRoutes(runtime.httpServer, hlsGenerator);
        }
        videoProcessor.caObjectLifecycle = runtime.caObjectLifecycle;
        if (peerDemo) {
            [peerDemo registerRoutesOnServer:runtime.httpServer];
            GZ_LOG_INFO(@"Streamplace peer demo UI: %@/demo/streamplace",
                        [NSString stringWithFormat:@"http://127.0.0.1:%lu", (unsigned long)config.port]);
        }
        if (embedContext) {
            embedContext.worker = runtime.worker;
            embedContext.jobStore = runtime.worker.jobStore;
            NSMutableDictionary *cfg = [embedContext.config mutableCopy] ?: [NSMutableDictionary dictionary];
            cfg[@"enableContentAddressedManifest"] = @(config.enableContentAddressedManifest);
            cfg[@"caObjectStoreConfigured"] = @(runtime.caObjectStore != nil || videoProcessor.caObjectStore != nil);
            cfg[@"enableCAMirrorFetch"] = @(config.enableCAMirrorFetch);
            cfg[@"caMirrorProviderCount"] = @(config.caMirrorProviders.count);
            cfg[@"caObjectSweepEnabled"] = @(config.caObjectSweepEnabled);
            cfg[@"enableMUXLPresentation"] = @(videoProcessor.enableMUXLPresentation);
            cfg[@"storageBackend"] = config.s3Bucket.length > 0 ? @"s3" : @"disk";
            cfg[@"streamplaceMirrorConfigured"] = @(streamplaceBase.length > 0);
            cfg[@"streamplaceAttributionDIDConfigured"] =
                @(config.streamplaceAttributionDID.length > 0);
            cfg[@"streamplaceServeCompat"] = @(config.enableStreamplaceServeCompat);
            if (streamplaceFetcher) {
                NSDictionary *stats = [streamplaceFetcher allowlistedStatsDictionary];
                cfg[@"streamplaceFetchSuccessCount"] = stats[@"successCount"] ?: @0;
                cfg[@"streamplaceBlobNotFoundCount"] = stats[@"blobNotFoundCount"] ?: @0;
                cfg[@"streamplaceFetchFailureCount"] = stats[@"failureCount"] ?: @0;
                if (stats[@"lastSuccessAt"] && stats[@"lastSuccessAt"] != [NSNull null]) {
                    cfg[@"streamplaceLastSuccessAt"] = stats[@"lastSuccessAt"];
                }
            } else {
                cfg[@"streamplaceFetchSuccessCount"] = @0;
                cfg[@"streamplaceBlobNotFoundCount"] = @0;
                cfg[@"streamplaceFetchFailureCount"] = @0;
            }
            embedContext.config = cfg;
        }
        GZ_LOG_INFO(@"Jelcz listening on port %lu", (unsigned long)config.port);
    }
                                     announceSignals:NO];
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    NSError *bootstrapError = nil;
    if (![GZServiceLifecycle bootstrapWithExecutableName:executable_name error:&bootstrapError]) {
        fprintf(stderr, "FATAL: %s\n", bootstrapError.localizedDescription.UTF8String);
        return 1;
    }
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
