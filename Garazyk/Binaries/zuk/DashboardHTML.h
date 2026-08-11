// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file DashboardHTML.h

 @abstract Returns the self-contained HTML dashboard for the Zuk relay root route.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 @abstract Returns the HTML content for the authenticated relay monitoring dashboard.
 @param csrfNonce One-time nonce used for the first state-changing request.
 */
NSString *ZukDashboardHTML(NSString *csrfNonce);

/**
 @abstract Returns the relay dashboard login page.
 @param csrfNonce One-time nonce used by the login request.
 */
NSString *ZukDashboardLoginHTML(NSString *csrfNonce);

NS_ASSUME_NONNULL_END
