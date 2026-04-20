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
#import "Sync/Firehose/SubscribeReposHandler.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/RelayXrpcRoutePack.h"
#import "Network/PDSNetworkTransport.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "PLC/DIDPLCResolver.h"

static const char *executable_name = "zuk";

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

static BOOL parse_relay_options(NSArray<NSString *> *args,
                                NSUInteger *port,
                                NSString **dataDir,
                                NSString **configPath,
                                NSMutableArray<NSString *> *upstreamURLs,
                                BOOL *noUpstream,
                                BOOL *verbose,
                                NSString **errorMessage) {
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --port";
                }
                return NO;
            }
            if (port) {
                *port = (NSUInteger)[args[++i] integerValue];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--data-dir"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --data-dir";
                }
                return NO;
            }
            if (dataDir) {
                *dataDir = args[++i];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --config";
                }
                return NO;
            }
            if (configPath) {
                *configPath = args[++i];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--upstream"] || [arg isEqualToString:@"-u"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --upstream";
                }
                return NO;
            }
            if (upstreamURLs) {
                [upstreamURLs addObject:args[++i]];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--no-upstream"]) {
            if (noUpstream) {
                *noUpstream = YES;
            }
        } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            if (verbose) {
                *verbose = YES;
            }
            [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
        } else if ([arg hasPrefix:@"-"]) {
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"Unknown option: %@", arg];
            }
            return NO;
        } else {
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"Unexpected argument: %@", arg];
            }
            return NO;
        }
    }
    return YES;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
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

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if ([command isEqualToString:@"help"]) {
            print_usage();
            return 0;
        }
        if ([command isEqualToString:@"version"]) {
            print_version();
            return 0;
        }
        if ([args containsObject:@"--help"] || [args containsObject:@"-h"]) {
            print_usage();
            return 0;
        }

        NSUInteger port = 2584;
        NSString *dataDir = nil;
        NSString *configPath = nil;
        NSMutableArray<NSString *> *upstreamURLs = [NSMutableArray array];
        BOOL noUpstream = NO;
        NSString *parseError = nil;
        if (![command isEqualToString:@"serve"] && ![command isEqualToString:@"status"]) {
            return fail_with_usage([NSString stringWithFormat:@"Unknown command: %@", command]);
        }
        if (!parse_relay_options(args, &port, &dataDir, &configPath, upstreamURLs, &noUpstream, nil, &parseError)) {
            return fail_with_usage(parseError);
        }

        // Load configuration if provided
        if (configPath) {
            NSError *configError = nil;
            NSData *configData = [NSData dataWithContentsOfFile:configPath options:0 error:&configError];
            if (!configData) {
                PDS_LOG_CORE_ERROR(@"Failed to read config file: %@", configError.localizedDescription);
                return 1;
            }
            NSDictionary *config = [NSJSONSerialization JSONObjectWithData:configData options:0 error:&configError];
            if (!config || ![config isKindOfClass:[NSDictionary class]]) {
                PDS_LOG_CORE_ERROR(@"Failed to parse config JSON: %@", configError.localizedDescription);
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
            
            PDS_LOG_CORE_INFO(@"Loaded config from %@", configPath);
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
                PDS_LOG_CORE_ERROR(@"Failed to create data directory: %@", dirError.localizedDescription);
                return 1;
            }
        }

        // Initialize relay metrics
        RelayMetrics *metrics = [[RelayMetrics alloc] init];

        // Initialize event buffer (72hr retention per Sync v1.1)
        RelayEventBuffer *eventBuffer = [RelayEventBuffer bufferWithDefaultRetention];

        // Initialize SubscribeReposHandler for downstream WebSocket connections
        SubscribeReposHandler *subscribeReposHandler = [[SubscribeReposHandler alloc] init];

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

        // Root info endpoint
        [server addRoute:@"GET"
                    path:@"/"
                 handler:^(HttpRequest *request, HttpResponse *response) {
                     NSDictionary *info = @{
                         @"service": @"zuk",
                         @"version": @"1.0.0",
                         @"type": @"com.atproto.relay",
                     };
                     NSData *json = [NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
                     [response setHeader:@"application/json" forKey:@"Content-Type"];
                     response.statusCode = 200;
                     [response setBody:json];
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
                                     id<PDSNetworkConnection> connection) {
            SubscribeReposHandler *strongHandler = weakSubscribeReposHandler;
            if (!strongHandler) {
                [connection cancel];
                return;
            }
            [strongHandler acceptUpgradedConnection:connection request:request];
        }];

        // Register XRPC sync endpoints (listRepos, getHead, getRepo)
        // Initialize PLC resolver for getRepo redirect functionality
        DIDPLCResolver *plcResolver = [[DIDPLCResolver alloc] initWithPlcUrl:@"https://plc.directory"];
        RelayXrpcRoutePack *xrpcRoutePack = [[RelayXrpcRoutePack alloc]
            initWithRepoStateManager:repoStateManager
               subscribeReposHandler:subscribeReposHandler
                       plcResolver:plcResolver];
        [xrpcRoutePack registerRoutesWithServer:server];

        // Start server
        NSError *startError = nil;
        if (![server startWithError:&startError]) {
            PDS_LOG_CORE_ERROR(@"Failed to start relay server: %@", startError.localizedDescription ?: @"unknown error");
            return 1;
        }

        // Connect to upstreams
        if (!noUpstream && upstreamURLs.count > 0) {
            printf("Connecting to %lu upstream(s)...\n", (unsigned long)upstreamURLs.count);
            [upstreamManager connectAll];
        } else if (!noUpstream) {
            printf("No upstreams configured. Running in passthrough mode.\n");
            printf("Use --upstream to connect to upstream firehose.\n");
        }

        printf("Zuk relay server started on port %lu\n", (unsigned long)port);
        printf("Data directory: %s\n", [dataDir UTF8String]);
        printf("Upstreams: %lu configured\n", (unsigned long)upstreamURLs.count);
        printf("\nAPI endpoints:\n");
        printf("  GET  /api/relay/metrics\n");
        printf("  GET  /api/relay/upstreams\n");
        printf("  GET  /api/relay/health\n");
        printf("\nFirehose endpoint:\n");
        printf("  WS   /xrpc/com.atproto.sync.subscribeRepos\n");
        printf("\nPress Ctrl+C to stop.\n");

        // Run the run loop
        [[NSRunLoop currentRunLoop] run];

        // Cleanup
        [upstreamManager disconnectAll];
        [server stop];
    }
    return 0;
}
