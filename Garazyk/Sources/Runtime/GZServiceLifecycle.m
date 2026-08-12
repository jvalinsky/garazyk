// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Runtime/GZServiceLifecycle.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import <CoreFoundation/CoreFoundation.h>
#import <execinfo.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>

#if defined(GNUSTEP)
#import <curl/curl.h>
#endif

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

static volatile sig_atomic_t gShutdownSignal = 0;
static volatile sig_atomic_t gAnnounceSignals = 1;
static volatile sig_atomic_t gForceExitArmed = 0;
static int gWakePipe[2] = { -1, -1 };

enum {
    // Graceful stop can hang when the main thread is blocked (e.g. stdout pipe
    // backpressure under firehose logging). Force-exit before the operator has
    // to reach for kill -9.
    kGZServiceShutdownWatchdogSeconds = 8
};

static void lifecycleWriteStderr(const char *msg) {
    if (!msg) return;
    size_t len = 0;
    while (msg[len] != '\0') {
        len++;
    }
    if (len > 0) {
        (void)write(STDERR_FILENO, msg, len);
    }
}

static void lifecycleWakeRunLoop(void) {
    if (gWakePipe[1] >= 0) {
        char byte = 1;
        (void)write(gWakePipe[1], &byte, 1);
    }
}

static void lifecycleForceExit(int sig) {
    if (gAnnounceSignals) {
        lifecycleWriteStderr("\nShutdown watchdog — forcing exit.\n");
    }
    _exit(128 + (sig > 0 ? sig : SIGTERM));
}

static void lifecycleAlarmHandler(int sig) {
    (void)sig;
    lifecycleForceExit(gShutdownSignal != 0 ? (int)gShutdownSignal : SIGTERM);
}

static void lifecycleShutdownHandler(int sig) {
    // Second Ctrl+C / SIGTERM while stopping: exit immediately.
    if (gShutdownSignal != 0) {
        if (gAnnounceSignals) {
            lifecycleWriteStderr("\nSecond interrupt — forcing exit.\n");
        }
        _exit(128 + sig);
    }

    gShutdownSignal = sig;
    lifecycleWakeRunLoop();

    if (!gForceExitArmed) {
        gForceExitArmed = 1;
        alarm(kGZServiceShutdownWatchdogSeconds);
    }
}

static void uncaughtExceptionHandler(NSException *exception) {
    fprintf(stderr, "=== UNCAUGHT NSException ===\n");
    fprintf(stderr, "Name: %s\n", [[exception name] UTF8String] ?: "null");
    fprintf(stderr, "Reason: %s\n", [[exception reason] UTF8String] ?: "null");
    fprintf(stderr, "UserInfo: %s\n", [[[exception userInfo] description] UTF8String] ?: "null");
    fprintf(stderr, "Stack:\n%s\n",
            [[[exception callStackSymbols] componentsJoinedByString:@"\n"] UTF8String] ?: "null");
    fprintf(stderr, "=============================\n");
}

static void sigabrtHandler(int sig) {
    void *callstack[128];
    int frames = backtrace(callstack, 128);
    fprintf(stderr, "=== SIGABRT (signal %d) ===\n", sig);
    backtrace_symbols_fd(callstack, frames, STDERR_FILENO);
    fprintf(stderr, "============================\n");
    signal(sig, SIG_DFL);
    raise(sig);
}

static BOOL lifecycleInstallWakePipe(void) {
    if (pipe(gWakePipe) != 0) {
        gWakePipe[0] = -1;
        gWakePipe[1] = -1;
        return NO;
    }
    int flags0 = fcntl(gWakePipe[0], F_GETFL, 0);
    int flags1 = fcntl(gWakePipe[1], F_GETFL, 0);
    if (flags0 >= 0) {
        (void)fcntl(gWakePipe[0], F_SETFL, flags0 | O_NONBLOCK);
    }
    if (flags1 >= 0) {
        (void)fcntl(gWakePipe[1], F_SETFL, flags1 | O_NONBLOCK);
    }
    return YES;
}

static void lifecycleCloseWakePipe(void) {
    if (gWakePipe[0] >= 0) {
        close(gWakePipe[0]);
        gWakePipe[0] = -1;
    }
    if (gWakePipe[1] >= 0) {
        close(gWakePipe[1]);
        gWakePipe[1] = -1;
    }
}

@implementation GZServiceLifecycle

+ (BOOL)bootstrapWithExecutableName:(const char *)executableName error:(NSError **)error {
    [[GZSignalManager sharedManager] installIgnoredSignals];
    [GZCrashReporter installCrashHandlersWithExecutableName:executableName];
    
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sigabrtHandler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGABRT, &sa, NULL);

#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif

    NSDateFormatterLinkATProtoCategory();
    
#ifdef LINUX
    // On Linux/GNUstep, verify critical categories are loaded
    if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZServiceLifecycleErrorDomain"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings."}];
        }
        return NO;
    }
#endif
    return YES;
}

+ (int)runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                 serviceName:(NSString *)serviceName
                     onStart:(void (^ _Nullable)(void))onStart {
    return [self runServiceWithRuntime:runtime
                            serviceName:serviceName
                                onStart:onStart
                        announceSignals:YES];
}

+ (int)runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                 serviceName:(NSString *)serviceName
                     onStart:(void (^ _Nullable)(void))onStart
             announceSignals:(BOOL)announceSignals {
    gShutdownSignal = 0;
    gForceExitArmed = 0;
    gAnnounceSignals = announceSignals ? 1 : 0;

    (void)lifecycleInstallWakePipe();

    struct sigaction alarmAction;
    memset(&alarmAction, 0, sizeof(alarmAction));
    alarmAction.sa_handler = lifecycleAlarmHandler;
    sigemptyset(&alarmAction.sa_mask);
    sigaction(SIGALRM, &alarmAction, NULL);

    struct sigaction shutdownAction;
    memset(&shutdownAction, 0, sizeof(shutdownAction));
    shutdownAction.sa_handler = lifecycleShutdownHandler;
    sigemptyset(&shutdownAction.sa_mask);
    sigaction(SIGTERM, &shutdownAction, NULL);
    sigaction(SIGINT, &shutdownAction, NULL);

    // When the signal handler writes the wake pipe, drain it on the main queue
    // and stop the runloop so we don't wait out the full beforeDate interval.
    dispatch_source_t wakeSource = nil;
    if (gWakePipe[0] >= 0) {
        wakeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                            (uintptr_t)gWakePipe[0],
                                            0,
                                            dispatch_get_main_queue());
        dispatch_source_set_event_handler(wakeSource, ^{
            char buf[32];
            while (read(gWakePipe[0], buf, sizeof(buf)) > 0) {
            }
            CFRunLoopStop(CFRunLoopGetMain());
        });
        dispatch_resume(wakeSource);
    }

    NSError *startError = nil;
    if (![runtime startWithError:&startError]) {
        if (wakeSource) {
            dispatch_source_cancel(wakeSource);
        }
        lifecycleCloseWakePipe();
        fprintf(stderr, "Failed to start %s: %s\n", serviceName.UTF8String, startError.localizedDescription.UTF8String ?: "unknown");
        return 1;
    }

    if (onStart) {
        onStart();
    }

    while (gShutdownSignal == 0) {
        @autoreleasepool {
            // Short timeout so a missed wake still observes the flag quickly.
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                      beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        }
    }

    if (announceSignals) {
        const char *name = gShutdownSignal == SIGTERM ? "SIGTERM" : "SIGINT";
        printf("\nReceived %s, shutting down...\n", name);
        fflush(stdout);
    }

    [runtime stop];

    // Graceful stop finished — cancel the force-exit watchdog.
    alarm(0);
    gForceExitArmed = 0;

    if (wakeSource) {
        dispatch_source_cancel(wakeSource);
    }
    lifecycleCloseWakePipe();
    return 0;
}

@end
