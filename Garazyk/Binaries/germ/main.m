// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m
 @brief Entry point for the Germ E2EE Mailbox standalone service.
 */

#import <Foundation/Foundation.h>
#import <signal.h>
#import <unistd.h>
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif
#import <fcntl.h>
#import <execinfo.h>
#import "Germ/Server/Runtime/GermRuntime.h"
#import "Debug/GZLogger.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"

static const char *executable_name = "germ";
static GermRuntime *gShutdownRuntime = nil;

#pragma mark - Crash Diagnostics

static void crash_signal_handler(int sig) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  :
                          (sig == SIGTRAP) ? "SIGTRAP" : "UNKNOWN";

    char buf[256];
    int len = snprintf(buf, sizeof(buf),
        "\n=== FATAL SIGNAL %s (%d) in germ ===\n", signame, sig);
    write(STDERR_FILENO, buf, (size_t)len);

    int fd = open("/tmp/germ-crash.log",
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
}

void handleSignal(int sig) {
    [gShutdownRuntime stop];
    exit(0);
}

void print_usage(void) {
    printf("Usage: %s serve [options]\n\n", executable_name);
    printf("Germ - Standalone AT Protocol E2EE Mailbox Service\n\n");
    printf("Provides encrypted message storage and relay (com.germnetwork.*).\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 8082)\n");
    printf("  --data-dir <path>     Data directory for database\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
}

int main(int argc, const char * argv[]) {
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    [[GZSignalManager sharedManager] installIgnoredSignals];

    @autoreleasepool {
        if (argc < 2) {
            print_usage();
            return 2;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            print_usage();
            return 0;
        }

        if (![command isEqualToString:@"serve"]) {
            fprintf(stderr, "Unknown command: %s\n", command.UTF8String);
            return 2;
        }

        uint16_t port = 8082;
        NSString *dataDir = @"./germ-data";

        // Parse basic arguments
        for (int i = 2; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--port"] && i + 1 < argc) {
                port = (uint16_t)[[NSString stringWithUTF8String:argv[++i]] integerValue];
            } else if ([arg isEqualToString:@"--data-dir"] && i + 1 < argc) {
                dataDir = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]) {
                [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
            }
        }

        GermRuntime *runtime = [GermRuntime sharedRuntime];
        NSError *error = nil;
        if (![runtime startWithDataDirectory:dataDir port:port error:&error]) {
            fprintf(stderr, "Failed to start Germ service: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }

        printf("Germ E2EE mailbox server started on port %u\n", port);
        
        gShutdownRuntime = runtime;
        install_crash_handlers();
        signal(SIGTERM, handleSignal);
        signal(SIGINT,  handleSignal);

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
