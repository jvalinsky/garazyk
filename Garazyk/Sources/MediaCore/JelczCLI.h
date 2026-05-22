// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JelczCLI.h

 @brief Shared CLI utility functions for the Jelcz video processing service.

 @discussion Exports functions that are shared between the jelcz binary and
 its unit tests.  Keeps CLI presentation logic testable without linking
 against the executable target.
 */

#ifndef JELCZ_CLI_H
#define JELCZ_CLI_H

#import <Foundation/Foundation.h>

/*!
 @abstract Prints the jelcz help/usage text to stdout.
 @discussion Outputs the standard usage banner, command list, and option
 descriptions.  Designed to be testable via StdoutCapture in unit tests.
 */
extern void JelczPrintUsage(void);

#endif /* JELCZ_CLI_H */
