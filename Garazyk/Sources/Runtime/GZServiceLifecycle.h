// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Minimal protocol implemented by top-level service runtimes.
 */
@protocol GZServiceRuntimeProtocol <NSObject>
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
@end

/**
 * @abstract Centralizes process lifecycle management for Garazyk services.
 * @discussion Handles signal registration, crash reporters, curl global init,
 * runloop dispatching, and category loading verification.
 */
@interface GZServiceLifecycle : NSObject

/**
 * @abstract Bootstraps the common environment early in `main`.
 * @discussion Installs crash handlers, ignored signals, libcurl, and verifies Objective-C categories.
 * Should be called immediately inside `main` but outside the autorelease pool (except where category checks require it).
 * @param executableName The name of the process (e.g. "syrena", "beskid")
 */
+ (BOOL)bootstrapWithExecutableName:(const char *)executableName error:(NSError **)error;

/**
 * @abstract Runs the service and blocks the current thread until stopped by a signal or error.
 * @param runtime The runtime instance to start and stop.
 * @param serviceName The service name for logging (e.g. "Beskid edge cache").
 * @param onStart Optional block executed immediately after successful startup.
 * @return Exist status code (0 for success, non-zero for failure).
 * @discussion SIGINT/SIGTERM set a flag, wake the runloop, and arm a force-exit
 * watchdog so a hung graceful stop (or a main thread blocked on a full stdout pipe)
 * cannot leave the process stuck. A second interrupt exits immediately.
 * Shutdown banners use non-blocking writes to stderr only — never stdout —
 * so a full stdout pipe cannot stall the first Ctrl+C.
 */
+ (int)runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                 serviceName:(NSString *)serviceName
                     onStart:(void (^ _Nullable)(void))onStart;

/**
 * @abstract Runs a service while allowing its established signal-output policy.
 * @param announceSignals Whether SIGINT and SIGTERM should be printed before
 * the runtime is stopped and the process exits successfully.
 * @discussion Pass NO only for a binary whose existing command contract
 * requires silent signal termination.
 */
+ (int)runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                 serviceName:(NSString *)serviceName
                     onStart:(void (^ _Nullable)(void))onStart
             announceSignals:(BOOL)announceSignals;

/**
 * @abstract Install SIGINT/SIGTERM handlers that wake the main runloop.
 * @discussion Prefer this over `GZSignalManager` for INT/TERM: GCD signal
 * sources require `SIG_BLOCK` and only run on the main queue, so a main thread
 * stuck in a full stdout `write` never observes Ctrl+C. These handlers are
 * async-signal-safe, arm a force-exit watchdog, and `_exit` on a second interrupt.
 * @param announceSignals Whether shutdown banners may be written to stderr.
 */
+ (void)beginInterruptibleRunLoopAnnouncing:(BOOL)announceSignals;

/**
 * @abstract YES after the first SIGINT or SIGTERM.
 */
+ (BOOL)interruptRequested;

/**
 * @abstract Pump `NSDefaultRunLoopMode` until `interruptRequested` is YES.
 */
+ (void)runMainRunLoopUntilInterrupted;

/**
 * @abstract Non-blocking stderr banner for the pending interrupt (no-op when silent).
 */
+ (void)announceInterrupt;

/**
 * @abstract Cancel the force-exit watchdog and tear down the wake pipe.
 * @discussion Call after graceful stop finishes so a late alarm cannot kill a
 * process that already exited the wait loop cleanly.
 */
+ (void)endInterruptibleRunLoop;

@end

NS_ASSUME_NONNULL_END
