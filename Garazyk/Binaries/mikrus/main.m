// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @brief Entry point for the Mikrus-style link index service.
 */

#import <Foundation/Foundation.h>
#import "Mikrus/MikrusRuntime.h"
#import "Mikrus/MikrusConfiguration.h"
#import "Mikrus/AdminUI/MikrusAdminSnapshot.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import "Runtime/GZServiceLifecycle.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#import "CLI/GZCommandLineOptions.h"

static const char *executable_name = "mikrus";

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
    printf("Admin UI options:\n");
    printf("  --admin-ui-host <address>   Admin UI bind address (default: 127.0.0.1)\n");
    printf("  --admin-ui-port <number>    Admin UI port (default: 2593)\n");
    printf("  --admin-password-file <path>  Admin password file (overrides env)\n\n");
    printf("Admin UI environment:\n");
    printf("  GARAZYK_MIKRUS_ADMIN_UI_HOST     Admin UI bind address\n");
    printf("  GARAZYK_MIKRUS_ADMIN_UI_PORT     Admin UI port\n");
    printf("  MIKRUS_ADMIN_PASSWORD_FILE       Admin password credential file\n");
    printf("  MIKRUS_ADMIN_PASSWORD            Admin password (plaintext, dev only)\n\n");
}

static void print_version(void) {
    printf("mikrus (Garazyk link index) 1.0.0\n");
}

static NSString *MikrusAdminPassword(NSString *explicitPath) {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    NSString *path = explicitPath.length > 0 ? explicitPath : env[@"MIKRUS_ADMIN_PASSWORD_FILE"];
    if (path.length > 0) {
        NSError *readError = nil;
        NSString *password = GZMikrusAdminPasswordFromFile(path, &readError);
        if (!password) { GZ_LOG_CORE_ERROR(@"Mikrus admin password file error: %@", readError.localizedDescription); return nil; }
        return password;
    }
    NSString *password = env[@"MIKRUS_ADMIN_PASSWORD"];
    return password.length > 0 ? password : nil;
}

static int fail_with_usage(NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\n\n", message.UTF8String);
    }
    print_usage();
    return 2;
}


int main(int argc, const char *argv[]) {
    NSError *bootstrapError = nil;
    if (![GZServiceLifecycle bootstrapWithExecutableName:executable_name error:&bootstrapError]) {
        fprintf(stderr, "FATAL: %s\n", bootstrapError.localizedDescription.UTF8String);
        return 1;
    }
    @autoreleasepool {
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

        GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
        [parser registerOptions:@[
            [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"relay" shortName:@"r" type:GZCommandLineOptionTypeRepeatableString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:@"d" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"config" shortName:@"c" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"no-ingest" shortName:nil type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"admin-ui-host" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"admin-ui-port" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"admin-password-file" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO]
        ] forCommand:@"serve"];

        NSError *parseError = nil;
        NSDictionary *parsedArgs = [parser parseArguments:args forCommand:@"serve" error:&parseError];
        if (!parsedArgs) {
            return fail_with_usage(parseError.localizedDescription);
        }

        if ([parsedArgs[@"verbose"] boolValue]) {
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
        }

        NSUInteger port = parsedArgs[@"port"] ? (NSUInteger)[parsedArgs[@"port"] integerValue] : 0;
        NSArray<NSString *> *relayURLs = parsedArgs[@"relay"];
        NSString *dataDir = parsedArgs[@"data-dir"];
        NSString *configPath = parsedArgs[@"config"];
        BOOL noIngest = [parsedArgs[@"no-ingest"] boolValue];

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

        // Admin UI
        NSString *adminHost = parsedArgs[@"admin-ui-host"] ?: NSProcessInfo.processInfo.environment[@"GARAZYK_MIKRUS_ADMIN_UI_HOST"] ?: @"127.0.0.1";
        NSString *adminPortValue = parsedArgs[@"admin-ui-port"] ?: NSProcessInfo.processInfo.environment[@"GARAZYK_MIKRUS_ADMIN_UI_PORT"];
        NSInteger parsedAdminPort = adminPortValue ? adminPortValue.integerValue : 2593;
        if (parsedAdminPort <= 0 || parsedAdminPort > 65535) return fail_with_usage(@"Admin UI port must be 1-65535");
        runtime.adminUIHost = adminHost;
        runtime.adminUIPort = (NSUInteger)parsedAdminPort;
        runtime.adminPassword = MikrusAdminPassword(parsedArgs[@"admin-password-file"]);

        return [GZServiceLifecycle runServiceWithRuntime:runtime serviceName:@"Mikrus" onStart:^{
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
        }];
    }
    return 0;
}
