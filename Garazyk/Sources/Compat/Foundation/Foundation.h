/**
 * @file Foundation.h
 *
 * @brief Foundation framework compatibility header.
 *
 * Imports appropriate Foundation framework for platform:
 * - macOS: Apple's Foundation framework
 * - Linux: GNUstep Foundation implementation
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef Foundation_h
#define Foundation_h

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#else
#import <GNUstepBase/Foundation.h>
#endif

#endif /* Foundation_h */
