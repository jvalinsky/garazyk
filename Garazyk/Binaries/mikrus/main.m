// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @brief Entry point for the Mikrus-style link index service.
 */

#import <Foundation/Foundation.h>
#import "Mikrus/MikrusRuntime.h"
#import "Mikrus/MikrusConfiguration.h"
#import "Compat/PlatformShims/CrashReporting/PDSCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/PDSSignalManager.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif

static const char *executable_name = "mikrus";
static MikrusRuntime *gRuntime = nil;

extern void NSDateFormatterLinkATProtoCategory(void);

static void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("Mikrus - ATProto link index and blue.microcosm.* XRPC service\n\n");
    printf("Commands:\n");
    printf("  serve        Start the service\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 3210)\n");
    printf("  --relay <url>         Relay WebSocket URL (repeatable; default: wss://bsky.network)\n");
    printf("  --data-dir <path>     Data directory for database and ingest state\n");
    printf("  --config <path>       JSON configuration file path\n");
    printf("  --no-ingest           Serve queries without connecting to a relay\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
    printf("Environment variables:\n");
    printf("  MIKRUS_RELAY_URLS             Comma-separated relay URLs\n");
    printf("  MIKRUS_DATA_DIR               Data directory path\n");
    printf("  MIKRUS_HTTP_PORT              HTTP API port\n");
    printf("  MIKRUS_CURSOR_CHECKPOINT_MS   Cursor checkpoint interval\n");
    printf("  MIKRUS_INGEST_ENABLED         true|false\n\n");
}

static void print_version(void) {
    printf("mikrus (Garazyk link index) 1.0.0\n");
}

static int fail_with_usage(NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\n\n", message.UTF8String);
    }
    print_usage();
    return 2;
}

static BOOL parse_options(NSArray<NSString *> *args,
                          NSUInteger *port,
                          NSMutableArray<NSString *> *relayURLs,
                          NSString **dataDir,
                          NSString **configPath,
                          BOOL *noIngest,
                          NSString **errorMessage) {
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) *errorMessage = @"Missing value for --port";
                return NO;
            }
            if (port) *port = (NSUInteger)[args[++i] integerValue];
            else i++;
        } else if ([arg isEqualToString:@"--relay"] || [arg isEqualToString:@"-r"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) *errorMessage = @"Missing value for --relay";
                return NO;
            }
            if (relayURLs) [relayURLs addObject:args[++i]];
            else i++;
        } else if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) *errorMessage = @"Missing value for --data-dir";
                return NO;
            }
            if (dataDir) *dataDir = args[++i];
            else i++;
        } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) *errorMessage = @"Missing value for --config";
                return NO;
            }
            if (configPath) *configPath = args[++i];
            else i++;
        } else if ([arg isEqualToString:@"--no-ingest"]) {
            if (noIngest) *noIngest = YES;
        } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
        } else if ([arg hasPrefix:@"-"]) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unknown option: %@", arg];
            return NO;
        } else {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unexpected argument: %@", arg];
            return NO;
        }
    }
    return YES;
}

int main(int argc, const char *argv[]) {
    [[PDSSignalManager sharedManager] installIgnoredSignals];
    [PDSCrashReporter installCrashHandlersWithExecutableName:"mikrus"];
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    @autoreleasepool {
        NSDateFormatterLinkATProtoCategory();
        if (argc < 2) return fail_with_usage(@"Missing command");

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if ([command isEqualToString:@"help"] || [args containsObject:@"--help"] || [args containsObject:@"-h"]) {
            print_usage();
            return 0;
        }
        if ([command isEqualToString:@"version"]) {
            print_version();
            return 0;
        }
        if (![command isEqualToString:@"serve"]) {
            return fail_with_usage([NSString stringWithFormat:@"Unknown command: %@", command]);
        }

        NSUInteger port = 0;
        NSMutableArray<NSString *> *relayURLs = [NSMutableArray array];
        NSString *dataDir = nil;
        NSString *configPath = nil;
        BOOL noIngest = NO;
        NSString *parseError = nil;
        if (!parse_options(args, &port, relayURLs, &dataDir, &configPath, &noIngest, &parseError)) {
            return fail_with_usage(parseError);
        }

        MikrusRuntime *runtime = [MikrusRuntime sharedRuntime];
        if (configPath.length > 0) {
            NSError *configError = nil;
            if (![runtime loadConfiguration:configPath error:&configError]) {
                fprintf(stderr, "Failed to load config: %s\n", configError.localizedDescription.UTF8String ?: "unknown");
                return 1;
            }
        } else {
            [runtime loadConfigurationFromEnvironment];
        }

        MikrusConfiguration *config = runtime.configuration;
        if (port > 0) config.httpPort = port;
        if (relayURLs.count > 0) config.relayURLs = relayURLs;
        if (dataDir.length > 0) config.dataDirectory = dataDir;
        if (noIngest) config.ingestEnabled = NO;

        NSError *startError = nil;
        if (![runtime startWithError:&startError]) {
            fprintf(stderr, "Failed to start Mikrus: %s\n", startError.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }

        printf("Mikrus link index started\n");
        printf("  Port:     %lu\n", (unsigned long)config.httpPort);
        printf("  Data dir: %s\n", config.dataDirectory.UTF8String);
        printf("  Ingest:   %s\n", config.ingestEnabled ? "enabled" : "disabled");
        printf("  Relays:   %lu configured\n", (unsigned long)config.relayURLs.count);
        printf("\nEndpoints:\n");
        printf("  GET /xrpc/blue.microcosm.links.getBacklinks\n");
        printf("  GET /xrpc/blue.microcosm.links.getBacklinkDids\n");
        printf("  GET /xrpc/blue.microcosm.links.getBacklinksCount\n");
        printf("  GET /xrpc/blue.microcosm.links.getManyToMany\n");
        printf("  GET /xrpc/blue.microcosm.links.getManyToManyCounts\n");
        printf("  GET /xrpc/blue.microcosm.identity.resolveMiniDoc\n");
        printf("  GET /xrpc/blue.microcosm.repo.getRecordByUri\n");
        printf("\nPress Ctrl+C to stop.\n");

        gRuntime = runtime;
        [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:^(int sig) {
            (void)sig;
            [gRuntime stop];
            exit(0);
        }];
        [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGINT handler:^(int sig) {
            (void)sig;
            [gRuntime stop];
            exit(0);
        }];

        dispatch_main();
    }
    return 0;
}
