// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Runtime/GZServiceLifecycle.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"
#import <execinfo.h>

#if defined(GNUSTEP)
#import <curl/curl.h>
#endif

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

static id<GZServiceRuntimeProtocol> gRunningRuntime = nil;

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
    gRunningRuntime = runtime;

    [[GZSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:^(int sig) {
        printf("\nReceived SIGTERM, shutting down...\n");
        [gRunningRuntime stop];
        exit(0);
    }];
    [[GZSignalManager sharedManager] registerHandlerForSignal:SIGINT handler:^(int sig) {
        printf("\nReceived SIGINT, shutting down...\n");
        [gRunningRuntime stop];
        exit(0);
    }];

    NSError *startError = nil;
    if (![runtime startWithError:&startError]) {
        fprintf(stderr, "Failed to start %s: %s\n", serviceName.UTF8String, startError.localizedDescription.UTF8String ?: "unknown");
        return 1;
    }

    if (onStart) {
        onStart();
    }

    [[NSRunLoop currentRunLoop] run];
    [runtime stop];
    return 0;
}

@end
