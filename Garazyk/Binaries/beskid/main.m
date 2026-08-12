// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m
 @brief Entry point for the Beskid-style edge record and identity cache service.
 */

#import <Foundation/Foundation.h>
#import "Beskid/BeskidRuntime.h"
#import "Beskid/BeskidConfiguration.h"
#import "Beskid/AdminUI/BeskidAdminSnapshot.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import "Runtime/GZServiceLifecycle.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#import "CLI/GZCommandLineOptions.h"

static const char *executable_name = "beskid";

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
    printf("Admin UI options:\n");
    printf("  --admin-ui-host <address>   Admin UI bind address (default: 127.0.0.1)\n");
    printf("  --admin-ui-port <number>    Admin UI port (default: 2595)\n");
    printf("  --admin-password-file <path>  Admin password file (overrides env)\n\n");
    printf("Admin UI environment:\n");
    printf("  GARAZYK_BESKID_ADMIN_UI_HOST     Admin UI bind address\n");
    printf("  GARAZYK_BESKID_ADMIN_UI_PORT     Admin UI port\n");
    printf("  BESKID_ADMIN_PASSWORD_FILE       Admin password credential file\n");
    printf("  BESKID_ADMIN_PASSWORD            Admin password (plaintext, dev only)\n\n");
}

static void print_version(void) {
    printf("beskid (Garazyk edge cache) 1.0.0\n");
}

static NSString *BeskidAdminPassword(NSString *explicitPath) {
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    NSString *path = explicitPath.length > 0 ? explicitPath : env[@"BESKID_ADMIN_PASSWORD_FILE"];
    if (path.length > 0) {
        NSError *readError = nil;
        NSString *password = GZBeskidAdminPasswordFromFile(path, &readError);
        if (!password) {
            GZ_LOG_CORE_ERROR(@"Beskid admin UI password file could not be read: %@", readError.localizedDescription);
            return nil;
        }
        return password;
    }
    NSString *password = env[@"BESKID_ADMIN_PASSWORD"];
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
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:@"d" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"config" shortName:@"c" type:GZCommandLineOptionTypeString isRequired:NO],
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
        NSString *dataDir = parsedArgs[@"data-dir"];
        NSString *configPath = parsedArgs[@"config"];

        GZBeskidRuntime *runtime = [GZBeskidRuntime sharedRuntime];

        if (configPath.length > 0) {
            NSError *configError = nil;
            if (![runtime loadConfiguration:configPath error:&configError]) {
                fprintf(stderr, "Failed to load config file: %s\n", configError.localizedDescription.UTF8String ?: "unknown");
                return 1;
            }
        } else {
            [runtime loadConfigurationFromEnvironment];
        }

        GZBeskidConfiguration *config = runtime.configuration;
        if (port > 0) config.httpPort = port;
        if (dataDir.length > 0) config.dataDirectory = dataDir;

        // Admin UI
        NSString *adminHost = parsedArgs[@"admin-ui-host"] ?: NSProcessInfo.processInfo.environment[@"GARAZYK_BESKID_ADMIN_UI_HOST"] ?: @"127.0.0.1";
        NSString *adminPortValue = parsedArgs[@"admin-ui-port"] ?: NSProcessInfo.processInfo.environment[@"GARAZYK_BESKID_ADMIN_UI_PORT"];
        NSInteger parsedAdminPort = adminPortValue ? adminPortValue.integerValue : 2595;
        if (parsedAdminPort <= 0 || parsedAdminPort > 65535) {
            return fail_with_usage(@"Admin UI port must be an integer from 1 through 65535");
        }
        runtime.adminUIHost = adminHost;
        runtime.adminUIPort = (NSUInteger)parsedAdminPort;
        runtime.adminPassword = BeskidAdminPassword(parsedArgs[@"admin-password-file"]);

        return [GZServiceLifecycle runServiceWithRuntime:runtime serviceName:@"Beskid" onStart:^{
            printf("Beskid edge cache service running on port %lu\n", (unsigned long)config.httpPort);
        }];
    }
}
