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
+ (void)bootstrapWithExecutableName:(const char *)executableName;

/**
 * @abstract Runs the service and blocks the current thread until stopped by a signal or error.
 * @param runtime The runtime instance to start and stop.
 * @param serviceName The service name for logging (e.g. "Beskid edge cache").
 * @param onStart Optional block executed immediately after successful startup.
 * @return Exist status code (0 for success, non-zero for failure).
 */
+ (int)runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                 serviceName:(NSString *)serviceName
                     onStart:(void (^ _Nullable)(void))onStart;

@end

NS_ASSUME_NONNULL_END
