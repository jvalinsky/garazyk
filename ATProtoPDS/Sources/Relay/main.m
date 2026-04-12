/*!
 @file main.m

 @brief Entry point for the Zuk relay server.

 @discussion A standalone AT Protocol relay server that receives events from
 upstream PDS instances and broadcasts them to downstream subscribers.

 Named after the FSC Żuk, a Polish light truck known for reliability.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/RelayClient.h"
#import "Sync/RelayUpstreamManager.h"
#import "Sync/RelayMetrics.h"
#import "Sync/RelayAPIHandler.h"
#import "Sync/RelayEventBuffer.h"
#import "Sync/RelayDownstreamHandler.h"
#import "Sync/SubscribeReposHandler.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/PDSNetworkTransport.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

static const char *executable_name = "zuk";

void print_usage(void) {
    printf("Usage: %s [options]\n\n", executable_name);
    printf("Zuk - AT Protocol Relay Server\n\n");
    printf("Receives events from upstream PDS instances and broadcasts\n");
    printf("to downstream subscribers via WebSocket firehose.\n\n");
    printf("Commands:\n");
    printf("  serve        Start relay server (default)\n");
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
    printf("  %s --port 2584\n", executable_name);
    printf("  %s --upstream wss://bsky.network/xrpc/com.atproto.sync.subscribeRepos\n", executable_name);
    printf("  %s --upstream ws://localhost:2583/xrpc/com.atproto.sync.subscribeRepos\n", executable_name);
}

void print_version(void) {
    printf("zuk (AT Protocol Relay) 1.0.0\n");
    printf("Named after the FSC Żuk light truck\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUInteger port = 2584;
        NSString *dataDir = nil;
        NSString *configPath = nil;
        NSMutableArray *upstreamURLs = [NSMutableArray array];
        BOOL verbose = NO;
        BOOL noUpstream = NO;
        NSString *command = @"serve";

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
                if (i + 1 < argc) {
                    port = (NSUInteger)[[NSString stringWithUTF8String:argv[++i]] integerValue];
                }
            } else if ([arg isEqualToString:@"--data-dir"]) {
                if (i + 1 < argc) {
                    dataDir = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
                if (i + 1 < argc) {
                    configPath = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--upstream"] || [arg isEqualToString:@"-u"]) {
                if (i + 1 < argc) {
                    [upstreamURLs addObject:[NSString stringWithUTF8String:argv[++i]]];
                }
            } else if ([arg isEqualToString:@"--no-upstream"]) {
                noUpstream = YES;
            } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                verbose = YES;
                [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
            } else if ([arg isEqualToString:@"serve"]) {
                command = @"serve";
            } else if ([arg isEqualToString:@"status"]) {
                command = @"status";
            } else if ([arg isEqualToString:@"version"]) {
                print_version();
                return 0;
            } else if ([arg isEqualToString:@"help"] || [arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]) {
                print_usage();
                return 0;
            }
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

        // Load configuration if provided
        if (configPath) {
            // TODO: Load JSON config
        }

        if ([command isEqualToString:@"status"]) {
            printf("Relay status: TODO - query running relay\n");
            return 0;
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

        // Initialize upstream manager with configured upstreams
        RelayUpstreamManager *upstreamManager = [[RelayUpstreamManager alloc] initWithInitialURLs:upstreamURLs];
        upstreamManager.delegate = downstreamHandler;

        // Configure relay API handler
        RelayAPIHandler *relayAPIHandler = [RelayAPIHandler sharedHandler];
        [relayAPIHandler setMetrics:metrics];
        [relayAPIHandler setUpstreamManager:upstreamManager];

        // Create HTTP server
        HttpServer *server = [HttpServer serverWithPort:port];

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
