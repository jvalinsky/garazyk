// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file DashboardHTML.h

 @abstract Returns the self-contained HTML dashboard for the Zuk relay root route.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 @abstract Returns the HTML content for the relay monitoring dashboard.
 */
NSString *ZukDashboardHTML(void);

NS_ASSUME_NONNULL_END
