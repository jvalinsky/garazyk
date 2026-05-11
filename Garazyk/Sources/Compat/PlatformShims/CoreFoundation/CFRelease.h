// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file CFRelease.h
 *
 * @brief Safe CFRelease macro for both macOS and Linux.
 *
 * @discussion On macOS, CFRelease delegates to CoreFoundation's reference counting.
 * On Linux, we use the Objective-C autorelease pool for toll-free-bridged objects.
 * This macro ensures proper cleanup on both platforms.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef _CF_RELEASE_H_
#define _CF_RELEASE_H_

#import <Foundation/Foundation.h>
#import "CoreFoundation.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Safe release of CF objects.

 On macOS, calls CFRelease directly.
 On Linux, autoreleases toll-free-bridged objects and clears the pointer.

 After calling this macro, the pointer is guaranteed to be NULL.

 Example:
     SecKeyRef key = [self createKey];
     CF_RELEASE(key);  // key is now NULL
 */
#if defined(__APPLE__)
    #define CF_RELEASE(ref) do { \
        if ((ref)) { \
            CFRelease((ref)); \
            (ref) = NULL; \
        } \
    } while(0)
#else
    #define CF_RELEASE(ref) do { \
        if ((ref)) { \
            CFAutorelease((ref)); \
            (ref) = NULL; \
        } \
    } while(0)
#endif

/**
 Release a SecKey specifically.

 On macOS, calls CFRelease.
 On Linux, calls EVP_PKEY_free and free (for manually-allocated SecKey structs).

 After calling this macro, the pointer is guaranteed to be NULL.
 */
#if defined(__APPLE__)
    #define SECKEY_RELEASE(ref) do { \
        if ((ref)) { \
            CFRelease((ref)); \
            (ref) = NULL; \
        } \
    } while(0)
#else
    extern void SecKeyRelease(SecKeyRef ref);
    #define SECKEY_RELEASE(ref) do { \
        if ((ref)) { \
            SecKeyRelease((ref)); \
            (ref) = NULL; \
        } \
    } while(0)
#endif

NS_ASSUME_NONNULL_END

#endif // _CF_RELEASE_H_
