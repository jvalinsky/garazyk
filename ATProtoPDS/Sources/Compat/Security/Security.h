/**
 * @file Security.h
 *
 * @brief Security framework compatibility header.
 *
 * Imports appropriate Security framework for platform:
 * - macOS: Apple's Security framework
 * - Linux: Compatibility shims (SecRandom)
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef Security_h
#define Security_h

#ifdef __APPLE__
#import <Security/Security.h>
#else
#import "SecRandom.h"
#endif

#endif /* Security_h */
