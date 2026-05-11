// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m
 @brief Entry point for the Syrena Chat standalone service.
 */

#import <Foundation/Foundation.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <execinfo.h>
#import "Chat/Server/ChatRuntime.h"
#import "Chat/Server/Config/ChatConfiguration.h"
#import "Debug/PDSLogger.h"

static const char *executable_name = "syrena-chat";
static ChatRuntime *gShutdownRuntime = nil;

#pragma mark - Crash Diagnostics

static void crash_signal_handler(int sig) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  :
                          (sig == SIGTRAP) ? "SIGTRAP" : "UNKNOWN";

    char buf[256];
    int len = snprintf(buf, sizeof(buf),
        "\n=== FATAL SIGNAL %s (%d) in syrena-chat ===\n", signame, sig);
    write(STDERR_FILENO, buf, (size_t)len);

    int fd = open("/tmp/syrena-chat-crash.log",
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

    int fd = open("/tmp/syrena-chat-crash.log",
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

void handleSignal(int sig) {
    [gShutdownRuntime stop];
    exit(0);
}

void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("Syrena Chat - Standalone AT Protocol Chat Service\n\n");
    printf("Provides private messaging (chat.bsky.*) as a standalone microservice.\n\n");
    printf("Commands:\n");
    printf("  serve        Start Chat server\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 2585)\n");
    printf("  --data-dir <path>     Data directory for database\n");
    printf("  --config <path>       Configuration file path (JSON)\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
}

int main(int argc, const char * argv[]) {
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

        ChatRuntime *runtime = [ChatRuntime sharedRuntime];
        [runtime loadConfigurationFromEnvironment];

        // Parse basic arguments
        for (int i = 2; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--port"] && i + 1 < argc) {
                runtime.configuration.httpPort = (NSUInteger)[[NSString stringWithUTF8String:argv[++i]] integerValue];
            } else if ([arg isEqualToString:@"--data-dir"] && i + 1 < argc) {
                runtime.configuration.dataDirectory = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--config"] && i + 1 < argc) {
                NSError *error = nil;
                if (![runtime loadConfiguration:[NSString stringWithUTF8String:argv[++i]] error:&error]) {
                    fprintf(stderr, "Error loading config: %s\n", error.localizedDescription.UTF8String);
                    return 1;
                }
            } else if ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]) {
                [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
            }
        }

        if ([command isEqualToString:@"serve"]) {
            NSError *error = nil;
            if (![runtime startWithError:&error]) {
                fprintf(stderr, "Failed to start Chat service: %s\n", error.localizedDescription.UTF8String);
                return 1;
            }

            printf("Syrena Chat server started on port %lu\n", (unsigned long)runtime.configuration.httpPort);
            
            gShutdownRuntime = runtime;
            install_crash_handlers();
            signal(SIGTERM, handleSignal);
            signal(SIGINT,  handleSignal);

            [[NSRunLoop currentRunLoop] run];
        } else {
            fprintf(stderr, "Unknown command: %s\n", command.UTF8String);
            return 2;
        }
    }
    return 0;
}
