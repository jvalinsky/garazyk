// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Runtime/GZServiceLifecycle.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import <execinfo.h>
#import <signal.h>

#if defined(GNUSTEP)
#import <curl/curl.h>
#endif

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

static volatile sig_atomic_t gShutdownSignal = 0;

static void lifecycleShutdownHandler(int sig) {
    gShutdownSignal = sig;
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

@implementation GZServiceLifecycle

+ (void)bootstrapWithExecutableName:(const char *)executableName {
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
        fprintf(stderr, "FATAL: Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings.\n");
        exit(1);
    }
#endif
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
    struct sigaction shutdownAction;
    memset(&shutdownAction, 0, sizeof(shutdownAction));
    shutdownAction.sa_handler = lifecycleShutdownHandler;
    sigemptyset(&shutdownAction.sa_mask);
    sigaction(SIGTERM, &shutdownAction, NULL);
    sigaction(SIGINT, &shutdownAction, NULL);

    NSError *startError = nil;
    if (![runtime startWithError:&startError]) {
        fprintf(stderr, "Failed to start %s: %s\n", serviceName.UTF8String, startError.localizedDescription.UTF8String ?: "unknown");
        return 1;
    }

    if (onStart) {
        onStart();
    }

    while (gShutdownSignal == 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                      beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        }
    }

    if (announceSignals) {
        const char *name = gShutdownSignal == SIGTERM ? "SIGTERM" : "SIGINT";
        printf("\nReceived %s, shutting down...\n", name);
    }
    [runtime stop];
    return 0;
}

@end
