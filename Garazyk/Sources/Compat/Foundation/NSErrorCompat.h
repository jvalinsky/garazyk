// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file NSErrorCompat.h
 *
 * @brief NSError compatibility header.
 *
 * Imports appropriate NSError support for platform:
 * - macOS: Standard Foundation NSError
 * - Linux: GNUstep NSError extensions
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef NSErrorCompat_h
#define NSErrorCompat_h

#ifdef __APPLE__
#import <Foundation/Foundation.h>
#else
#import <GNUstepBase/NSError+GNUstepBase.h>
#endif

#endif /* NSErrorCompat_h */
