// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSCrashReporter.h

 @abstract Shared crash signal and exception handler for Garazyk binaries.

 @discussion Consolidates the crash handling logic previously duplicated across
 kaszlak, zuk, and syrena entry points. Installs sigaction-based crash signal
 handlers with SA_SIGINFO|SA_RESETHAND|SA_ONSTACK and an alternate signal stack
 for overflow protection. Extracts the program counter from ucontext_t on all
 supported architectures (macOS ARM64, macOS x86_64, Linux aarch64, Linux x86_64).

 Crash reports are written to /tmp/<executableName>-crash.log using only
 async-signal-safe calls (write, snprintf, backtrace).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSCrashReporter

 @abstract Installs crash signal handlers and uncaught-exception handlers.

 @discussion Call +installCrashHandlersWithExecutableName: once at startup,
 before any other initialization. The executable name is used for the crash
 log file path (/tmp/<name>-crash.log).
 */
@interface PDSCrashReporter : NSObject

/*!
 @method installCrashHandlersWithExecutableName:

 @abstract Installs crash signal handlers and the uncaught-exception handler.

 @param name The executable name for crash log identification (e.g. "kaszlak").

 @discussion Installs handlers for SIGSEGV, SIGABRT, SIGBUS, SIGFPE, and
 SIGTRAP using sigaction with SA_SIGINFO|SA_RESETHAND|SA_ONSTACK. Also
 allocates an alternate signal stack (sigaltstack) for overflow protection
 and registers an NSSetUncaughtExceptionHandler.
 */
+ (void)installCrashHandlersWithExecutableName:(const char *)name;

@end

NS_ASSUME_NONNULL_END
