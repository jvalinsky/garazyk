#import <Foundation/Foundation.h>

#import "AdminUIServer/UIServiceConfig.h"
#import "AdminUIServer/UIServerRuntime.h"
#import "Debug/PDSLogger.h"

static const char *executable_name = "garazyk-ui";
static UIServerRuntime *gRuntime = nil;

static void handleSignal(int sig) {
    (void)sig;
    [gRuntime stop];
    exit(0);
}

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

static BOOL parse_options(NSArray<NSString *> *args,
                          NSString **hostOverride,
                          NSUInteger *portOverride,
                          BOOL *verbose,
                          NSString **errorMessage) {
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--host"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) *errorMessage = @"Missing value for --host";
                return NO;
            }
            if (hostOverride) *hostOverride = args[++i];
        } else if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) *errorMessage = @"Missing value for --port";
                return NO;
            }
            NSInteger port = [args[++i] integerValue];
            if (port <= 0) {
                if (errorMessage) *errorMessage = @"Port must be a positive integer";
                return NO;
            }
            if (portOverride) *portOverride = (NSUInteger)port;
        } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            if (verbose) *verbose = YES;
        } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            print_usage();
            exit(0);
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
    signal(SIGPIPE, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    signal(SIGINT, handleSignal);
    signal(SIGTERM, handleSignal);

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

        NSString *hostOverride = nil;
        NSUInteger portOverride = 0;
        BOOL verbose = NO;
        NSString *errorMessage = nil;
        if (!parse_options(args, &hostOverride, &portOverride, &verbose, &errorMessage)) {
            fprintf(stderr, "Error: %s\n\n", [errorMessage UTF8String]);
            print_usage();
            return 2;
        }

        if (verbose) {
            [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
        }

        UIServiceConfig *config = [UIServiceConfig configurationFromEnvironment];
        if (hostOverride.length > 0) {
            config.host = hostOverride;
        }
        if (portOverride > 0) {
            config.port = portOverride;
        }

        UIServerRuntime *runtime = [[UIServerRuntime alloc] initWithConfiguration:config];
        gRuntime = runtime;
        NSError *startError = nil;
        if (![runtime startWithError:&startError]) {
            fprintf(stderr, "Failed to start UI service: %s\n",
                    [startError.localizedDescription UTF8String]);
            return 1;
        }

        printf("garazyk-ui listening on http://%s:%lu/admin\n",
               [config.host UTF8String], (unsigned long)config.port);
        printf("Press Ctrl+C to stop.\n");

        while (runtime.isRunning) {
            @autoreleasepool {
                [[NSRunLoop mainRunLoop]
                    runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
            }
        }
    }
    return 0;
}
