// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewWebhookHook.h

 @abstract Index hook that sends HTTP POST notifications to a webhook URL.

 @discussion A built-in index hook that notifies an external service
 when records are created, updated, or deleted. Useful for integrating
 with external systems (notification services, analytics pipelines, etc.).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "AppView/Server/Hooks/AppViewIndexHook.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AppViewWebhookHook

 @abstract Sends HTTP POST notifications to a configured webhook URL.
 */
@interface AppViewWebhookHook : NSObject <AppViewIndexHook>

/*!
 @method initWithWebhookURL:collections:

 @abstract Initialize with the webhook URL and optional collection filter.

 @param webhookURL  The URL to POST notifications to.
 @param collections Optional array of collection NSIDs to filter on (nil = all).
 */
- (instancetype)initWithWebhookURL:(NSString *)webhookURL
                       collections:(nullable NSArray<NSString *> *)collections;

/*!
 @method initWithWebhookURL:

 @abstract Initialize with the webhook URL (fires for all collections).

 @param webhookURL The URL to POST notifications to.
 */
- (instancetype)initWithWebhookURL:(NSString *)webhookURL;

@end

NS_ASSUME_NONNULL_END
