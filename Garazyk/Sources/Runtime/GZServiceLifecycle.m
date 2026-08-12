// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Runtime/GZServiceLifecycle.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import <CoreFoundation/CoreFoundation.h>
#import <execinfo.h>
#import <fcntl.h>
#import <poll.h>
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
static dispatch_source_t gWakeSource = nil;

enum {
    // Graceful stop can hang (checkpoint flush, stdout pipe backpressure under
    // firehose logging). Force-exit before the operator reaches for kill -9.
    // Keep this short: first Ctrl+C should feel responsive even when stop stalls.
    kGZServiceShutdownWatchdogSeconds = 3
};

static void lifecycleWriteStderr(const char *msg) {
    if (!msg || !gAnnounceSignals) {
        return;
    }
    size_t len = 0;
    while (msg[len] != '\0') {
        len++;
    }
    if (len == 0) {
        return;
    }

    // Never block the main thread or a signal handler on a full stderr pipe
    // (common when the operator redirected 2>&1 into an undrained pipe).
    struct pollfd pfd = { .fd = STDERR_FILENO, .events = POLLOUT, .revents = 0 };
    if (poll(&pfd, 1, 0) <= 0 || (pfd.revents & POLLOUT) == 0) {
        return;
    }

    int flags = fcntl(STDERR_FILENO, F_GETFL, 0);
    BOOL restored = NO;
    if (flags >= 0 && (flags & O_NONBLOCK) == 0) {
        if (fcntl(STDERR_FILENO, F_SETFL, flags | O_NONBLOCK) == 0) {
            restored = YES;
        }
    }
    (void)write(STDERR_FILENO, msg, len);
    if (restored) {
        (void)fcntl(STDERR_FILENO, F_SETFL, flags);
    }
}

static void lifecycleWakeRunLoop(void) {
    if (gWakePipe[1] >= 0) {
        char byte = 1;
        (void)write(gWakePipe[1], &byte, 1);
    }
}

static void lifecycleForceExit(int sig) {
    lifecycleWriteStderr("\nShutdown watchdog — forcing exit.\n");
    _exit(128 + (sig > 0 ? sig : SIGTERM));
}

static void lifecycleAlarmHandler(int sig) {
    (void)sig;
    lifecycleForceExit(gShutdownSignal != 0 ? (int)gShutdownSignal : SIGTERM);
}

static void lifecycleShutdownHandler(int sig) {
    // Second Ctrl+C / SIGTERM while stopping: exit immediately.
    if (gShutdownSignal != 0) {
        lifecycleWriteStderr("\nSecond interrupt — forcing exit.\n");
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
    if (gWakePipe[0] >= 0) {
        return YES;
    }
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

static void lifecycleCancelWakeSource(void) {
    if (gWakeSource) {
        dispatch_source_cancel(gWakeSource);
        gWakeSource = nil;
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

+ (void)beginInterruptibleRunLoopAnnouncing:(BOOL)announceSignals {
    gShutdownSignal = 0;
    gForceExitArmed = 0;
    gAnnounceSignals = announceSignals ? 1 : 0;

    lifecycleCancelWakeSource();
    lifecycleCloseWakePipe();
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
    // Ensure GCD signal sources did not leave INT/TERM blocked for this process.
    sigset_t unblock;
    sigemptyset(&unblock);
    sigaddset(&unblock, SIGINT);
    sigaddset(&unblock, SIGTERM);
    sigprocmask(SIG_UNBLOCK, &unblock, NULL);
    sigaction(SIGTERM, &shutdownAction, NULL);
    sigaction(SIGINT, &shutdownAction, NULL);

    // When the signal handler writes the wake pipe, drain it on the main queue
    // and stop the runloop so we don't wait out the full beforeDate interval.
    if (gWakePipe[0] >= 0) {
        gWakeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,
                                             (uintptr_t)gWakePipe[0],
                                             0,
                                             dispatch_get_main_queue());
        dispatch_source_set_event_handler(gWakeSource, ^{
            char buf[32];
            while (read(gWakePipe[0], buf, sizeof(buf)) > 0) {
            }
#if defined(__APPLE__)
            CFRunLoopStop(CFRunLoopGetMain());
#endif
            // GNUstep: +runMainRunLoopUntilInterrupted polls gShutdownSignal every 250ms.
        });
        dispatch_resume(gWakeSource);
    }
}

+ (BOOL)interruptRequested {
    return gShutdownSignal != 0;
}

+ (void)runMainRunLoopUntilInterrupted {
    while (gShutdownSignal == 0) {
        @autoreleasepool {
            // Short timeout so a missed wake still observes the flag quickly.
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        }
    }
}

+ (void)announceInterrupt {
    if (!gAnnounceSignals || gShutdownSignal == 0) {
        return;
    }
    const char *name = gShutdownSignal == SIGTERM ? "SIGTERM" : "SIGINT";
    char buf[64];
    // Keep this tiny so a non-blocking write usually succeeds.
    int n = snprintf(buf, sizeof(buf), "\nReceived %s, shutting down...\n", name);
    if (n > 0) {
        lifecycleWriteStderr(buf);
    }
}

+ (void)endInterruptibleRunLoop {
    alarm(0);
    gForceExitArmed = 0;
    lifecycleCancelWakeSource();
    lifecycleCloseWakePipe();
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
    [self beginInterruptibleRunLoopAnnouncing:announceSignals];

    NSError *startError = nil;
    if (![runtime startWithError:&startError]) {
        [self endInterruptibleRunLoop];
        fprintf(stderr, "Failed to start %s: %s\n", serviceName.UTF8String, startError.localizedDescription.UTF8String ?: "unknown");
        return 1;
    }

    if (onStart) {
        onStart();
    }

    [self runMainRunLoopUntilInterrupted];
    [self announceInterrupt];
    [runtime stop];
    [self endInterruptibleRunLoop];
    return 0;
}

@end
