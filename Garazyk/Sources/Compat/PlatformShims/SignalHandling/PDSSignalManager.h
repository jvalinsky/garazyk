// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSSignalManager.h

 @abstract Lifecycle signal management for Garazyk binaries.

 @discussion Manages signal installation and dispatch_source-based signal
 handling. Uses sigaction() exclusively (never signal()). Provides a clean
 ObjC interface for registering blocks to run when lifecycle signals are
 received (SIGINT, SIGTERM, SIGHUP, SIGUSR1, SIGUSR2).

 Crash signals (SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGTRAP) are handled by
 PDSCrashReporter, not this class.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract Block invoked when a registered signal is received.

 @param signalNumber The signal number that was received.

 @discussion The block is invoked on the main dispatch queue, NOT in a
 signal handler context. This means it is safe to call any ObjC method,
 allocate memory, acquire locks, etc.
 */
typedef void (^PDSSignalHandlerBlock)(int signalNumber);

/*!
 @class PDSSignalManager

 @abstract Manages lifecycle signal handling via dispatch sources.

 @discussion PDSSignalManager replaces raw signal() calls with sigaction()
 for signal installation and GCD dispatch sources for safe, main-queue
 delivery of signal events. Multiple handlers can be registered for the
 same signal.
 */
@interface PDSSignalManager : NSObject

/*!
 @method sharedManager

 @abstract Returns the shared signal manager singleton.

 @return The shared PDSSignalManager instance.
 */
+ (instancetype)sharedManager;

/*!
 @method installIgnoredSignals

 @abstract Installs SIGPIPE and SIGHUP as ignored signals via sigaction().

 @discussion SIGPIPE is ignored to prevent crashes when clients disconnect.
 SIGHUP is ignored at the process level so that dispatch_source handlers
 can receive it instead. Call this once at startup.
 */
- (void)installIgnoredSignals;

/*!
 @method registerHandlerForSignal:handler:

 @abstract Registers a block to be invoked when the given signal is received.

 @param signalNumber The signal to handle (e.g. SIGINT, SIGTERM, SIGHUP, SIGUSR1).
 @param handler The block to invoke on the main queue when the signal is received.

 @discussion Creates a dispatch_source for the signal if one does not already
 exist. Multiple handlers can be registered for the same signal. The signal
 is unblocked (sigprocmask) so that dispatch_source can receive it.

 For SIGHUP: you must NOT call installIgnoredSignals if you want to receive
 SIGHUP via this method. Instead, call registerHandlerForSignal:SIGHUP and
 the manager will handle the sigaction setup.
 */
- (void)registerHandlerForSignal:(int)signalNumber
                          handler:(PDSSignalHandlerBlock)handler;

/*!
 @method unregisterHandlerForSignal:

 @abstract Removes all registered handlers for the given signal.

 @param signalNumber The signal to stop handling.

 @discussion Cancels the dispatch source for this signal and restores
 the signal to its default disposition.
 */
- (void)unregisterHandlerForSignal:(int)signalNumber;

@end

NS_ASSUME_NONNULL_END
