// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m
 @brief Entry point for the Beskid-style edge record and identity cache service.
 */

#import <Foundation/Foundation.h>
#import "Beskid/BeskidRuntime.h"
#import "Beskid/BeskidConfiguration.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif

static const char *executable_name = "beskid";
static BeskidRuntime *gRuntime = nil;

extern void NSDateFormatterLinkATProtoCategory(void);

static void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("Beskid - ATProto edge record & identity cache and blue.microcosm.* XRPC service\n\n");
    printf("Commands:\n");
    printf("  serve        Start the service\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 8085)\n");
    printf("  --data-dir <path>     Data directory for database and cache state\n");
    printf("  --config <path>       JSON configuration file path\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
    printf("Environment variables:\n");
    printf("  BESKID_DATA_DIR               Data directory path\n");
    printf("  BESKID_HTTP_PORT              HTTP API port\n");
    printf("  BESKID_DOMAIN                 Service proxying domain name\n\n");
}

static void print_version(void) {
    printf("beskid (Garazyk edge cache) 1.0.0\n");
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
                          NSString **dataDir,
                          NSString **configPath,
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
    [[GZSignalManager sharedManager] installIgnoredSignals];
    [GZCrashReporter installCrashHandlersWithExecutableName:"beskid"];
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
        NSString *dataDir = nil;
        NSString *configPath = nil;
        NSString *parseError = nil;
        if (!parse_options(args, &port, &dataDir, &configPath, &parseError)) {
            return fail_with_usage(parseError);
        }

        BeskidRuntime *runtime = [BeskidRuntime sharedRuntime];
        gRuntime = runtime;

        if (configPath.length > 0) {
            NSError *configError = nil;
            if (![runtime loadConfiguration:configPath error:&configError]) {
                fprintf(stderr, "Failed to load config file: %s\n", configError.localizedDescription.UTF8String ?: "unknown");
                return 1;
            }
        } else {
            [runtime loadConfigurationFromEnvironment];
        }

        BeskidConfiguration *config = runtime.configuration;
        if (port > 0) config.httpPort = port;
        if (dataDir.length > 0) config.dataDirectory = dataDir;

        [[GZSignalManager sharedManager] registerHandlerForSignal:SIGINT handler:^(int sig) {
            printf("\nReceived SIGINT, shutting down...\n");
            [gRuntime stop];
            exit(0);
        }];
        [[GZSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:^(int sig) {
            printf("\nReceived SIGTERM, shutting down...\n");
            [gRuntime stop];
            exit(0);
        }];

        NSError *startError = nil;
        if (![runtime startWithError:&startError]) {
            fprintf(stderr, "Failed to start Beskid: %s\n", startError.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }

        printf("Beskid edge cache service running on port %lu\n", (unsigned long)config.httpPort);
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
