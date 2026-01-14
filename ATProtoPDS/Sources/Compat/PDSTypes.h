/**
 * @file PDSTypes.h
 *
 * @brief Platform compatibility type definitions.
 *
 * Defines macros for cross-platform compatibility between macOS and Linux/GNUstep.
 * Handles differences in GCD (Grand Central Dispatch) Objective-C support.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef PDSTypes_h
#define PDSTypes_h

/**
 * @def PDS_GCD_OBJC_SUPPORT
 * @brief Whether platform supports GCD Objective-C integration.
 *
 * macOS: 1 (GCD with Objective-C object support)
 * Linux: 0 (libdispatch without full Objective-C integration)
 */
#if defined(__APPLE__)
#define PDS_GCD_OBJC_SUPPORT 1
#else
#define PDS_GCD_OBJC_SUPPORT 0
#endif

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

#endif /* PDSTypes_h */
