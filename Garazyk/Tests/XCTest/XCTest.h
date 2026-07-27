// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @file XCTest.h
 *
 * @brief Makes the GNUstep XCTest shim available to tests using framework-style imports.
 */

#ifndef GZ_TEST_XCTEST_FORWARDING_HEADER_H
#define GZ_TEST_XCTEST_FORWARDING_HEADER_H

#ifdef __APPLE__
#include_next <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#endif
