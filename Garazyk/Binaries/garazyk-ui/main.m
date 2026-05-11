// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <execinfo.h>
#import "AdminUIServer/UIServiceConfig.h"
#import "AdminUIServer/UIServerRuntime.h"
#import "Debug/PDSLogger.h"

static const char *executable_name = "garazyk-ui";
static UIServerRuntime *gRuntime = nil;

#pragma mark - Crash Diagnostics

static void crash_signal_handler(int sig) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  :
                          (sig == SIGTRAP) ? "SIGTRAP" : "UNKNOWN";

    char buf[256];
    int len = snprintf(buf, sizeof(buf),
        "\n=== FATAL SIGNAL %s (%d) in garazyk-ui ===\n", signame, sig);
    write(STDERR_FILENO, buf, (size_t)len);

    int fd = open("/tmp/garazyk-ui-crash.log",
                  O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        write(fd, buf, (size_t)len);
        void *frames[32];
        int frame_count = (int)backtrace(frames, 32);
        for (int i = 0; i < frame_count; i++) {
            char frame_buf[64];
            int flen = snprintf(frame_buf, sizeof(frame_buf),
                                "  #%d %p\n", i, frames[i]);
            write(fd, frame_buf, (size_t)flen);
        }
        char **symbols = backtrace_symbols(frames, frame_count);
        if (symbols) {
            for (int i = 0; i < frame_count; i++) {
                char sym_buf[256];
                int slen = snprintf(sym_buf, sizeof(sym_buf),
                                    "  #%d %s\n", i, symbols[i] ?: "?");
                write(fd, sym_buf, (size_t)slen);
            }
            free(symbols);
        }
        close(fd);
    }

    signal(sig, SIG_DFL);
    raise(sig);
}

static void uncaught_exception_handler(NSException *exception) {
    fprintf(stderr, "\n=== UNCAUGHT EXCEPTION ===\n");
    fprintf(stderr, "Name: %s\n", exception.name.UTF8String ?: "?");
    fprintf(stderr, "Reason: %s\n", exception.reason.UTF8String ?: "?");

    int fd = open("/tmp/garazyk-ui-crash.log",
                  O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char buf[1024];
        int len = snprintf(buf, sizeof(buf),
            "=== UNCAUGHT EXCEPTION ===\nName: %s\nReason: %s\n",
            exception.name.UTF8String ?: "?",
            exception.reason.UTF8String ?: "?");
        write(fd, buf, (size_t)len);
        close(fd);
    }
    fflush(stderr);
}

static void install_crash_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = crash_signal_handler;
    sa.sa_flags = SA_RESETHAND;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
    NSSetUncaughtExceptionHandler(&uncaught_exception_handler);
}

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
    install_crash_handlers();
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
