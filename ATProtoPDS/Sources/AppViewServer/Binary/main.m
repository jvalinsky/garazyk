/*!
 @file main.m

 @brief Entry point for the Syrena AppView server.

 @discussion A standalone AT Protocol AppView server that consumes the
 subscribeRepos firehose, materializes full-network or interest-graph-scoped
 views, and serves app.bsky.* query XRPC endpoints.

 Named after the FSO Syrena, a Polish automobile produced 1957–1983.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppViewServer/AppViewRuntime.h"
#import "AppViewServer/Config/AppViewConfiguration.h"
#import "Debug/PDSLogger.h"

static const char *executable_name = "syrena";

void print_usage(void) {
    printf("Usage: %s [options] [command]\n\n", executable_name);
    printf("Syrena - Standalone AT Protocol AppView Server\n\n");
    printf("Consumes the subscribeRepos firehose, materializes app.bsky.* views,\n");
    printf("and serves them as XRPC query endpoints.\n\n");
    printf("Commands:\n");
    printf("  serve        Start AppView server (default)\n");
    printf("  status       Query a running server's status\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 3200)\n");
    printf("  --relay <url>         Relay URL (default: wss://bsky.network)\n");
    printf("                        Repeat for multiple relays.\n");
    printf("  --data-dir <path>     Data directory for database and state\n");
    printf("  --config <path>       Configuration file path (JSON)\n");
    printf("  --partial             Enable interest-graph partial mode\n");
    printf("  --seed-did <did>      Add a seed DID (partial mode)\n");
    printf("  --no-backfill         Disable backfill orchestrator\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
    printf("Environment variables:\n");
    printf("  APPVIEW_MODE                     standalone|proxy\n");
    printf("  APPVIEW_RELAY_URLS               Comma-separated relay URLs\n");
    printf("  APPVIEW_DATA_DIR                 Data directory path\n");
    printf("  APPVIEW_HTTP_PORT                HTTP API port\n");
    printf("  APPVIEW_ADMIN_SECRET             Admin API bearer token\n");
    printf("  APPVIEW_CURSOR_CHECKPOINT_MS     Cursor checkpoint interval (ms)\n");
    printf("  APPVIEW_BACKFILL_ENABLED         true|false\n");
    printf("  APPVIEW_BACKFILL_GLOBAL_WORKERS  Integer\n");
    printf("  APPVIEW_BACKFILL_PER_HOST_WORKERS Integer\n");
    printf("  APPVIEW_PARTIAL_ENABLED          true|false\n");
    printf("  APPVIEW_PARTIAL_SEED_DIDS        Comma-separated DIDs\n");
    printf("  APPVIEW_PARTIAL_ALLOWLIST        Comma-separated DIDs\n");
    printf("  APPVIEW_PARTIAL_TTL_HOURS        Integer\n");
    printf("  APPVIEW_PARTIAL_PROXY_FALLBACK   true|false\n\n");
    printf("Examples:\n");
    printf("  %s serve\n", executable_name);
    printf("  %s --port 3200 --relay wss://bsky.network serve\n", executable_name);
    printf("  %s --partial --seed-did did:plc:youraccountdid serve\n", executable_name);
    printf("  %s --config /etc/syrena/config.json serve\n", executable_name);
}

void print_version(void) {
    printf("syrena (AT Protocol AppView) 1.0.0\n");
    printf("Named after the FSO Syrena — a Polish automobile (1957-1983)\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUInteger port = 0;
        NSMutableArray<NSString *> *relayURLs = [NSMutableArray array];
        NSMutableArray<NSString *> *seedDIDs  = [NSMutableArray array];
        NSString *dataDir    = nil;
        NSString *configPath = nil;
        BOOL partial         = NO;
        BOOL noBackfill      = NO;
        BOOL verbose         = NO;
        NSString *command    = @"serve";

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];

            if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
                if (i + 1 < argc) port = (NSUInteger)[[NSString stringWithUTF8String:argv[++i]] integerValue];
            } else if ([arg isEqualToString:@"--relay"] || [arg isEqualToString:@"-r"]) {
                if (i + 1 < argc) [relayURLs addObject:[NSString stringWithUTF8String:argv[++i]]];
            } else if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
                if (i + 1 < argc) dataDir = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
                if (i + 1 < argc) configPath = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--partial"]) {
                partial = YES;
            } else if ([arg isEqualToString:@"--seed-did"]) {
                if (i + 1 < argc) [seedDIDs addObject:[NSString stringWithUTF8String:argv[++i]]];
            } else if ([arg isEqualToString:@"--no-backfill"]) {
                noBackfill = YES;
            } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                verbose = YES;
                [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
            } else if ([arg isEqualToString:@"serve"]) {
                command = @"serve";
            } else if ([arg isEqualToString:@"status"]) {
                command = @"status";
            } else if ([arg isEqualToString:@"version"]) {
                print_version(); return 0;
            } else if ([arg isEqualToString:@"help"] ||
                       [arg isEqualToString:@"-h"] ||
                       [arg isEqualToString:@"--help"]) {
                print_usage(); return 0;
            }
        }

        // ----------------------------------------------------------------
        // status command: query a running instance
        // ----------------------------------------------------------------
        if ([command isEqualToString:@"status"]) {
            NSUInteger statusPort = port > 0 ? port : 3200;
            NSURL *statusURL = [NSURL URLWithString:
                [NSString stringWithFormat:@"http://localhost:%lu/admin/backfill/status",
                 (unsigned long)statusPort]];
            NSError *fetchErr = nil;
            NSData *data = [NSData dataWithContentsOfURL:statusURL options:0 error:&fetchErr];
            if (!data) {
                printf("AppView status: NOT RUNNING (port %lu)\n", (unsigned long)statusPort);
                return 1;
            }
            NSError *jsonErr = nil;
            NSDictionary *status = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            printf("AppView status: RUNNING\n");
            if (status) {
                printf("  Queue depth:    %ld\n", [status[@"queue_depth"] longValue]);
                printf("  Active workers: %ld\n", [status[@"active_workers"] longValue]);
                printf("  Repos pending:  %ld\n", [status[@"repos_pending"] longValue]);
                printf("  Repos synced:   %ld\n", [status[@"repos_synced"] longValue]);
                printf("  Repos dirty:    %ld\n", [status[@"repos_dirty"] longValue]);
            }
            return 0;
        }

        // ----------------------------------------------------------------
        // Load configuration
        // ----------------------------------------------------------------
        AppViewRuntime *runtime = [AppViewRuntime sharedRuntime];

        if (configPath) {
            NSError *configErr = nil;
            if (![runtime loadConfiguration:configPath error:&configErr]) {
                fprintf(stderr, "Failed to load config: %s\n",
                        configErr.localizedDescription.UTF8String ?: "unknown error");
                return 1;
            }
        } else {
            [runtime loadConfigurationFromEnvironment];
        }

        // Apply CLI overrides
        AppViewConfiguration *config = runtime.configuration;
        if (port > 0)            config.httpPort       = port;
        if (relayURLs.count > 0) config.relayURLs      = relayURLs;
        if (seedDIDs.count > 0)  config.partialSeedDIDs = seedDIDs;
        if (dataDir)             config.dataDirectory   = dataDir;
        if (partial)             config.partialEnabled  = YES;
        if (noBackfill)          config.backfillEnabled = NO;

        // ----------------------------------------------------------------
        // Start
        // ----------------------------------------------------------------
        NSError *startErr = nil;
        if (![runtime startWithError:&startErr]) {
            fprintf(stderr, "Failed to start AppView: %s\n",
                    startErr.localizedDescription.UTF8String ?: "unknown error");
            return 1;
        }

        printf("Syrena AppView server started\n");
        printf("  Port:       %lu\n", (unsigned long)config.httpPort);
        printf("  Data dir:   %s\n",  config.dataDirectory.UTF8String);
        printf("  Relays:     %lu configured\n", (unsigned long)config.relayURLs.count);
        printf("  Backfill:   %s\n",  config.backfillEnabled ? "enabled" : "disabled");
        printf("  Partial:    %s\n",  config.partialEnabled  ? "enabled" : "disabled");
        if (config.partialEnabled && config.partialSeedDIDs.count > 0) {
            printf("  Seeds:      %lu DIDs\n", (unsigned long)config.partialSeedDIDs.count);
        }
        printf("\nAdmin endpoints (requires APPVIEW_ADMIN_SECRET):\n");
        printf("  GET  /admin/backfill/status\n");
        printf("  POST /admin/backfill/repos\n");
        printf("  POST /admin/backfill/scope/rebuild\n");
        printf("\nPress Ctrl+C to stop.\n");

        // Signal handler for graceful shutdown
        signal(SIGTERM, ^(int sig){ [runtime stop]; exit(0); });
        signal(SIGINT,  ^(int sig){ [runtime stop]; exit(0); });

        [[NSRunLoop currentRunLoop] run];

        [runtime stop];
    }
    return 0;
}
