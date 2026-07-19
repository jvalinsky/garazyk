// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

#import "AdminUIServer/UIServiceConfig.h"
#import "AdminUIServer/UIServerRuntime.h"
#import "CLI/GZCommandLineOptions.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Debug/GZLogger.h"
#import "Runtime/GZServiceLifecycle.h"

static const char *executable_name = "garazyk-ui";

static void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("Garazyk Dedicated Admin UI Service\n\n");
    printf("Commands:\n");
    printf("  serve       Start the UI service\n");
    printf("  version     Show version information\n");
    printf("  help        Show this help\n\n");
    printf("Options:\n");
    printf("  --host <addr>       Override GARAZYK_UI_HOST\n");
    printf("  --port <number>     Override GARAZYK_UI_PORT\n");
    printf("  -v, --verbose       Enable debug logging\n");
    printf("  -h, --help          Show this help\n\n");
    printf("Environment:\n");
    printf("  GARAZYK_UI_HOST             Bind host (default: 127.0.0.1)\n");
    printf("  GARAZYK_UI_PORT             Bind port (default: 2590)\n");
    printf("  GARAZYK_UI_ADMIN_PASSWORD   UI admin password (default: changeme)\n");
    printf("  GARAZYK_UI_PDS_URL          PDS base URL\n");
    printf("  GARAZYK_UI_PLC_URL          PLC base URL\n");
    printf("  GARAZYK_UI_RELAY_URL        Relay base URL\n");
    printf("  GARAZYK_UI_APPVIEW_URL      AppView base URL\n");
    printf("  GARAZYK_UI_CHAT_URL         Chat base URL\n");
    printf("  GARAZYK_UI_PDS_TOKEN        Optional bearer token for PDS admin XRPC\n");
    printf("  GARAZYK_UI_PDS_PASSWORD     PDS admin password (auto-obtains JWT on startup)\n");
}

static void print_version(void) {
    printf("garazyk-ui 1.0.0\n");
}

static int fail_with_usage(NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\n\n", message.UTF8String);
    }
    print_usage();
    return 2;
}

static BOOL help_requested_before_parse_error(NSArray<NSString *> *args) {
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--host"] ||
            [arg isEqualToString:@"--port"] ||
            [arg isEqualToString:@"-p"]) {
            if (i + 1 >= args.count) {
                return NO;
            }
            i++;
        } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
        } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            return YES;
        } else {
            return NO;
        }
    }
    return NO;
}

int main(int argc, const char *argv[]) {
    [GZServiceLifecycle bootstrapWithExecutableName:executable_name];
    // Preserve the UI's dedicated named crash log after lifecycle bootstrap.
    [GZCrashReporter installCrashHandlersWithExecutableName:executable_name];
    @autoreleasepool {
        if (argc < 2) {
            print_usage();
            return 2;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"help"]) {
            print_usage();
            return 0;
        }
        if ([command isEqualToString:@"version"]) {
            print_version();
            return 0;
        }
        if (![command isEqualToString:@"serve"]) {
            fprintf(stderr, "Error: Unknown command: %s\n\n", [command UTF8String]);
            print_usage();
            return 2;
        }

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if (help_requested_before_parse_error(args)) {
            print_usage();
            return 0;
        }

        GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
        [parser registerOptions:@[
            [GZCommandLineOption optionWithLongName:@"host" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
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
        NSInteger parsedPort = portString.integerValue;
        if (portString && parsedPort <= 0) {
            return fail_with_usage(@"Port must be a positive integer");
        }

        if ([parsedArgs[@"verbose"] boolValue]) {
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
        }

        UIServiceConfig *config = [UIServiceConfig configurationFromEnvironment];
        NSString *hostOverride = parsedArgs[@"host"];
        if (hostOverride.length > 0) {
            config.host = hostOverride;
        }
        NSUInteger portOverride = (NSUInteger)parsedPort;
        if (portOverride > 0) {
            config.port = portOverride;
        }

        UIServerRuntime *runtime = [[UIServerRuntime alloc] initWithConfiguration:config];
        return [GZServiceLifecycle runServiceWithRuntime:runtime
                                              serviceName:@"UI service"
                                                  onStart:^{
            printf("garazyk-ui listening on http://%s:%lu/admin\n",
                   config.host.UTF8String, (unsigned long)config.port);
            printf("Press Ctrl+C to stop.\n");
        }
                                          announceSignals:NO];
    }
}
