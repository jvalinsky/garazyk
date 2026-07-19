// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @brief Entry point for the Zuk relay server.

 @discussion A standalone AT Protocol relay server that receives events from
 upstream PDS instances and broadcasts them to downstream subscribers.

 Named after the FSC Żuk, a Polish light truck known for reliability.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/Relay/RelayClient.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayAPIHandler.h"
#import "Sync/Relay/RelayEventBuffer.h"
#import "Sync/Relay/RelayDownstreamHandler.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RelayXrpcRoutePack.h"
#import "Network/ATProtoNetworkTransport.h"
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "PLC/DIDPLCResolver.h"
#import "CLI/GZCommandLineOptions.h"
#import "Runtime/GZServiceLifecycle.h"

static const char *executable_name = "zuk";

@interface ZukRuntimeComposite : NSObject <GZServiceRuntimeProtocol>
@property (nonatomic, strong) HttpServer *server;
@property (nonatomic, strong, nullable) RelayUpstreamManager *upstreamManager;
@property (nonatomic, strong) NSArray<NSString *> *upstreamURLs;
@property (nonatomic, assign) BOOL noUpstream;
@end

@implementation ZukRuntimeComposite
- (BOOL)startWithError:(NSError **)error {
    if (![self.server startWithError:error]) {
        return NO;
    }
    if (!self.noUpstream && self.upstreamURLs.count > 0) {
        printf("Connecting to %lu upstream(s)...\n", (unsigned long)self.upstreamURLs.count);
        [self.upstreamManager connectAll];
    } else if (!self.noUpstream) {
        printf("No upstreams configured. Running in passthrough mode.\n");
        printf("Use --upstream to connect to upstream firehose.\n");
    }
    return YES;
}
- (void)stop {
    if (self.upstreamManager) {
        [self.upstreamManager disconnectAll];
    }
    [self.server stop];
}
@end

void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("Zuk - AT Protocol Relay Server\n\n");
    printf("Receives events from upstream PDS instances and broadcasts\n");
    printf("to downstream subscribers via WebSocket firehose.\n\n");
    printf("Commands:\n");
    printf("  serve        Start relay server\n");
    printf("  status       Show relay status\n");
    printf("  version      Show version\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP/WebSocket port (default: 2584)\n");
    printf("  --upstream <url>      Upstream firehose URL (wss://...)\n");
    printf("  --data-dir <path>     Data directory for relay state\n");
    printf("  --config <path>       Configuration file path\n");
    printf("  --no-upstream         Run without upstream (passthrough mode)\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
    printf("Examples:\n");
    printf("  %s serve --port 2584\n", executable_name);
    printf("  %s serve --upstream wss://bsky.network/xrpc/com.atproto.sync.subscribeRepos\n", executable_name);
    printf("  %s status --port 2584\n", executable_name);
}

void print_version(void) {
    printf("zuk (AT Protocol Relay) 1.0.0\n");
    printf("Named after the FSC Żuk light truck\n");
}

static int fail_with_usage(NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\n\n", [message UTF8String]);
    }
    print_usage();
    return 2;
}

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

int main(int argc, const char * argv[]) {
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    @autoreleasepool {
        [GZServiceLifecycle bootstrapWithExecutableName:executable_name];
        NSDateFormatterLinkATProtoCategory();
#ifdef LINUX
        // On Linux/GNUstep, verify critical categories are loaded
        if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) {
            fprintf(stderr, "FATAL: Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings.\n");
            return 1;
        }
#endif
        if (argc < 2) {
            return fail_with_usage(@"Missing command");
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command hasPrefix:@"-"]) {
            return fail_with_usage(@"Flags must follow the command name");
        }

        if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            print_usage();
            return 0;
        }
        if ([command isEqualToString:@"version"] || [command isEqualToString:@"-V"] || [command isEqualToString:@"--version"]) {
            print_version();
            return 0;
        }

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        if ([args containsObject:@"--help"] || [args containsObject:@"-h"]) {
            print_usage();
            return 0;
        }

        if (![command isEqualToString:@"serve"] && ![command isEqualToString:@"status"]) {
            return fail_with_usage([NSString stringWithFormat:@"Unknown command: %@", command]);
        }

        GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
        NSArray<GZCommandLineOption *> *serveOptions = @[
            [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"config" shortName:@"c" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"upstream" shortName:@"u" type:GZCommandLineOptionTypeRepeatableString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"no-upstream" shortName:nil type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"help" shortName:@"h" type:GZCommandLineOptionTypeBoolean isRequired:NO]
        ];
        [parser registerOptions:serveOptions forCommand:@"serve"];

        NSArray<GZCommandLineOption *> *statusOptions = @[
            [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"help" shortName:@"h" type:GZCommandLineOptionTypeBoolean isRequired:NO]
        ];
        [parser registerOptions:statusOptions forCommand:@"status"];

        NSError *parseError = nil;
        NSDictionary<NSString *, id> *parsedArgs = [parser parseArguments:args forCommand:command error:&parseError];
        if (!parsedArgs) {
            return fail_with_usage(parseError.localizedDescription);
        }

        NSUInteger port = parsedArgs[@"port"] ? (NSUInteger)[parsedArgs[@"port"] integerValue] : 2584;
        NSString *dataDir = parsedArgs[@"data-dir"];
        NSString *configPath = parsedArgs[@"config"];
        NSMutableArray<NSString *> *upstreamURLs = [NSMutableArray arrayWithArray:parsedArgs[@"upstream"] ?: @[]];
        BOOL noUpstream = [parsedArgs[@"no-upstream"] boolValue];
        BOOL verbose = [parsedArgs[@"verbose"] boolValue];
        if (verbose) {
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
        }

        // Load configuration if provided
        if (configPath) {
            NSError *configError = nil;
            NSData *configData = [NSData dataWithContentsOfFile:configPath options:0 error:&configError];
            if (!configData) {
                GZ_LOG_CORE_ERROR(@"Failed to read config file: %@", configError.localizedDescription);
                return 1;
            }
            NSDictionary *config = [NSJSONSerialization JSONObjectWithData:configData options:0 error:&configError];
            if (!config || ![config isKindOfClass:[NSDictionary class]]) {
                GZ_LOG_CORE_ERROR(@"Failed to parse config JSON: %@", configError.localizedDescription);
                return 1;
            }
            
            // Apply relay config
            NSDictionary *relayConfig = config[@"relay"];
            if (relayConfig) {
                // Override port if not set via CLI
                if (port == 2584 && relayConfig[@"port"]) {
                    port = [relayConfig[@"port"] unsignedIntegerValue];
                }
                // Add upstreams from config if not set via CLI
                if (upstreamURLs.count == 0 && relayConfig[@"upstreams"]) {
                    NSArray *configUpstreams = relayConfig[@"upstreams"];
                    if ([configUpstreams isKindOfClass:[NSArray class]]) {
                        [upstreamURLs addObjectsFromArray:configUpstreams];
                    }
                }
                // Override data directory if not set via CLI
                if (!dataDir && relayConfig[@"dataDirectory"]) {
                    dataDir = relayConfig[@"dataDirectory"];
                }
            }
            
            GZ_LOG_CORE_INFO(@"Loaded config from %@", configPath);
        }

        if ([command isEqualToString:@"status"]) {
            // Query running relay's health endpoint
            NSURL *healthURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/api/relay/health", (unsigned long)port]];
            NSError *error = nil;
            NSData *syncData = [NSData dataWithContentsOfURL:healthURL options:0 error:&error];
            
            if (error || !syncData) {
                printf("Relay status: NOT RUNNING (port %lu)\n", (unsigned long)port);
                printf("  Error: %s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            
            NSDictionary *health = [NSJSONSerialization JSONObjectWithData:syncData options:0 error:&error];
            printf("Relay status: RUNNING\n");
            printf("  Port: %lu\n", (unsigned long)port);
            if (health && [health isKindOfClass:[NSDictionary class]]) {
                id upstreams = health[@"upstreams"];
                if (upstreams && [upstreams respondsToSelector:@selector(count)] && [upstreams count] > 0) {
                    printf("  Upstreams: %lu connected\n", (unsigned long)[upstreams count]);
                }
                id status = health[@"status"];
                if (status && [status isKindOfClass:[NSString class]]) {
                    printf("  Health: %s\n", [status UTF8String]);
                } else {
                    printf("  Health: OK\n");
                }
            }
            return 0;
        }

        // Default data directory
        if (!dataDir) {
            dataDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)
                       firstObject];
            dataDir = [dataDir stringByAppendingPathComponent:@"zuk"];
        }

        // Ensure data directory exists
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dataDir]) {
            NSError *dirError = nil;
            [fm createDirectoryAtPath:dataDir
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&dirError];
            if (dirError) {
                GZ_LOG_CORE_ERROR(@"Failed to create data directory: %@", dirError.localizedDescription);
                return 1;
            }
        }

        // Initialize relay metrics
        RelayMetrics *metrics = [[RelayMetrics alloc] init];

        // Initialize event buffer (72hr retention per Sync v1.1)
        RelayEventBuffer *eventBuffer = [RelayEventBuffer bufferWithDefaultRetention];

        // Initialize SubscribeReposHandler for downstream WebSocket connections
        // Persistence disabled in Relay for performance/stability in scenario tests
        SubscribeReposHandler *subscribeReposHandler = [[SubscribeReposHandler alloc] initWithServiceDatabases:nil];
        subscribeReposHandler.relayMetrics = metrics;
        subscribeReposHandler.eventBuffer = eventBuffer;


        // Initialize downstream handler (bridges upstream events to downstream)
        RelayDownstreamHandler *downstreamHandler = [[RelayDownstreamHandler alloc]
            initWithEventBuffer:eventBuffer
            subscribeReposHandler:subscribeReposHandler];
        downstreamHandler.metrics = metrics;

        // Initialize repo state manager for XRPC queries
        RelayRepoStateManager *repoStateManager = [[RelayRepoStateManager alloc] init];
        downstreamHandler.repoStateManager = repoStateManager;

        // Initialize upstream manager with configured upstreams
        RelayUpstreamManager *upstreamManager = [[RelayUpstreamManager alloc] initWithInitialURLs:upstreamURLs];
        upstreamManager.delegate = downstreamHandler;

        // Configure relay API handler
        RelayAPIHandler *relayAPIHandler = [RelayAPIHandler sharedHandler];
        [relayAPIHandler setMetrics:metrics];
        [relayAPIHandler setUpstreamManager:upstreamManager];

        // Create HTTP server
        HttpServer *server = [HttpServer serverWithPort:port];

        // Root ASCII service banner
        [server addRoute:@"GET"
                    path:@"/"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     response.statusCode = 200;
                     response.contentType = @"text/plain; charset=utf-8";
                     [response setBodyString:@"________  ___  ___  ___  __       \n|\\_____  \\|\\  \\|\\  \\|\\  \\|\\  \\     \n \\|___/  /\\ \\  \\\\  \\ \\  \\/  /|_   \n     /  / /\\ \\  \\\\  \\ \\   ___  \\  \n    /  /_/__\\ \\  \\\\  \\ \\  \\\\ \\  \\ \n   |\\________\\ \\_______\\ \\__\\\\ \\___\\\n    \\|_______|\\|_______|\\|__| \\|__| \n"];
                 }];

        [server addRoute:@"GET"
                    path:@"/favicon.ico"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     response.statusCode = HttpStatusNoContent;
                     response.contentType = @"image/x-icon";
                     [response setBodyData:[NSData data]];
                 }];

        // Register relay API endpoints
        [server addRoute:@"GET"
                    path:@"/api/relay/metrics"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/api/relay/upstreams"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/api/relay/health"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        // POST routes for relay API
        [server addRoute:@"POST"
                    path:@"/api/relay/upstreams"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/api/relay/requestCrawl"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/api/relay/upstreams/reconnect-all"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        [server addRoute:@"POST"
                    path:@"/api/relay/upstreams/disconnect-all"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        [server addRoute:@"GET"
                    path:@"/api/relay/capabilities"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [relayAPIHandler handleRequest:request response:response];
                 }];

        // Catch-all for upstream sub-paths (connect/disconnect individual URLs)
        [server addHandlerForPath:@"/api/relay/upstreams/"
                          handler:^(HttpRequest *request, HttpResponse *response) {
                              [relayAPIHandler handleRequest:request response:response];
                          }];


        // OPTIONS preflight for WebSocket upgrade (CORS)
        [server addRoute:@"OPTIONS"
                    path:@"/xrpc/com.atproto.sync.subscribeRepos"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
                     [response setHeader:@"GET, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
                     response.statusCode = HttpStatusOK;
                 }];

        // WebSocket upgrade path for downstream subscribers
        __weak SubscribeReposHandler *weakSubscribeReposHandler = subscribeReposHandler;
        [server addWebSocketRoute:@"/xrpc/com.atproto.sync.subscribeRepos"
                           handler:^(HttpRequest *request, HttpResponse *response,
                                     id<ATProtoNetworkConnection> connection) {
            SubscribeReposHandler *strongHandler = weakSubscribeReposHandler;
            if (!strongHandler) {
                [connection cancel];
                return;
            }
            [strongHandler acceptUpgradedConnection:connection request:request];
        }];

        // Register XRPC sync endpoints (listRepos, getHead, getRepo, getLatestCommit,
        // getRepoStatus, getHostStatus, requestCrawl)
        // Initialize PLC resolver for getRepo redirect functionality
        DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"https://plc.directory"];
        RelayXrpcRoutePack *xrpcRoutePack = [[RelayXrpcRoutePack alloc]
            initWithRepoStateManager:repoStateManager
               subscribeReposHandler:subscribeReposHandler
                       plcResolver:plcResolver];
        xrpcRoutePack.upstreamManager = upstreamManager;
        [xrpcRoutePack registerRoutesWithServer:server];

        ZukRuntimeComposite *composite = [[ZukRuntimeComposite alloc] init];
        composite.server = server;
        composite.upstreamManager = upstreamManager;
        composite.upstreamURLs = upstreamURLs;
        composite.noUpstream = noUpstream;

        return [GZServiceLifecycle runServiceWithRuntime:composite
                                             serviceName:@"Zuk relay server"
                                                 onStart:^{
                                                     printf("Zuk relay server started on port %lu\n", (unsigned long)port);
                                                     printf("Data directory: %s\n", [dataDir UTF8String]);
                                                     printf("Upstreams: %lu configured\n", (unsigned long)upstreamURLs.count);
                                                     printf("\nAPI endpoints:\n");
                                                     printf("  GET  /api/relay/metrics\n");
                                                     printf("  GET  /api/relay/upstreams\n");
                                                     printf("  POST /api/relay/upstreams\n");
                                                     printf("  GET  /api/relay/capabilities\n");
                                                     printf("  GET  /api/relay/health\n");
                                                     printf("  POST /api/relay/requestCrawl\n");
                                                     printf("  POST /api/relay/upstreams/reconnect-all\n");
                                                     printf("  POST /api/relay/upstreams/disconnect-all\n");
                                                     printf("\nFirehose endpoint:\n");
                                                     printf("  WS   /xrpc/com.atproto.sync.subscribeRepos\n");
                                                     printf("\nPress Ctrl+C to stop.\n");
                                                 }
                                         announceSignals:NO];
    }
    return 0;
}
