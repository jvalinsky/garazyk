/**
 * @file PDSTypes.h
 *
 * @brief Platform compatibility type definitions.
 *
 * Defines macros for cross-platform compatibility between macOS and
 * Linux/GNUstep. Handles differences in GCD (Grand Central Dispatch)
 * Objective-C support.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef PDSTypes_h
#define PDSTypes_h

/**
 * @def PDS_PLATFORM_APPLE
 * @brief Defined when building for macOS/Apple platforms.
 * Replaces: __APPLE__, defined(__APPLE__), TARGET_OS_MAC
 */
#if defined(__APPLE__)
#define PDS_PLATFORM_APPLE 1
#else
#define PDS_PLATFORM_APPLE 0
#endif

/**
 * @def PDS_PLATFORM_LINUX
 * @brief Defined when building for Linux/GNUstep platforms.
 * Replaces: __linux__, defined(__linux__), GNUSTEP, defined(__GNUstep__), !defined(__APPLE__)
 */
#if !defined(__APPLE__)
#define PDS_PLATFORM_LINUX 1
#else
#define PDS_PLATFORM_LINUX 0
#endif

#if PDS_PLATFORM_LINUX
#import "Foundation/NSDataCompat.h"

// CF Bridging macros for ARC (GNUstep doesn't define these)
#ifndef CFBridgingRelease
#define CFBridgingRelease(x) ((__bridge_transfer id)(x))
#endif
#ifndef CFBridgingRetain
#define CFBridgingRetain(x) ((__bridge_retained CFTypeRef)(x))
#endif
#ifndef __unused
#define __unused __attribute__((unused))
#endif
#endif

/**
 * @def PDS_GCD_OBJC_SUPPORT
 * @brief Whether platform supports GCD Objective-C integration.
 *
 * Apple: 1 (GCD with Objective-C object support)
 * Linux: 0 (libdispatch without full Objective-C integration)
 */
#define PDS_GCD_OBJC_SUPPORT PDS_PLATFORM_APPLE

/**
 * @def PDS_DISPATCH_QUEUE_STRONG
 * @brief Property attribute for dispatch queue storage.
 *
 * macOS: strong (dispatch_queue_t supports ARC)
 * Linux: assign (dispatch_queue_t is not ARC-compatible)
 */
#if PDS_GCD_OBJC_SUPPORT
#define PDS_DISPATCH_QUEUE_STRONG strong
#else
#define PDS_DISPATCH_QUEUE_STRONG assign
#endif

/**
 * @def PDS_GCD_STRONG
 * @brief Property attribute for any GCD type (semaphore, group, source, etc.).
 *
 * Same as PDS_DISPATCH_QUEUE_STRONG — on GNUstep/Linux, GCD types
 * are not Objective-C objects and cannot use 'strong'.
 */
#define PDS_GCD_STRONG PDS_DISPATCH_QUEUE_STRONG

#ifdef DEPRECATED_MSG_ATTRIBUTE
#undef DEPRECATED_MSG_ATTRIBUTE
#endif

#define DEPRECATED_MSG_ATTRIBUTE(s) __attribute__((deprecated(s)))

#if PDS_PLATFORM_LINUX
#ifndef NSErrorUserInfoKey
#define NSErrorUserInfoKey NSString *
#endif
#endif

#endif /* PDSTypes_h */
