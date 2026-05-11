// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file GNUstepCFNetworkCompat.h
 * @brief Compatibility alias to the canonical CFNetwork shim surface.
 *
 * This header historically provided non-functional stubs. It now forwards
 * to the platform shim implementation so GNUstep/Linux builds use the same
 * compatibility contract as the rest of the codebase.
 */

#ifndef GNUSTEP_CFNETWORK_COMPAT_H
#define GNUSTEP_CFNETWORK_COMPAT_H

#if defined(__APPLE__)
#import <CFNetwork/CFNetwork.h>
#else
#import "Compat/PlatformShims/CoreFoundation/CFNetwork.h"
#endif

#endif