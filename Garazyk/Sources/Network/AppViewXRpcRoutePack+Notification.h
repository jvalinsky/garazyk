// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

/**
 * @abstract Authenticated notification XRPC route handlers.
 * @discussion Every handler derives its actor DID from a validated bearer token; an auth failure
 * writes the response and stops processing. Paginated reads clamp `limit` to 1...100. Invalid
 * required JSON bodies yield 400, while notification-service failures yield 500 error JSON.
 */
@interface AppViewXRpcRoutePack (Notification)

/** @abstract Lists the caller's notifications with optional cursor pagination. */
- (void)handleListNotifications:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns the caller's unread notification count. */
- (void)handleGetUnreadCount:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Marks a bounded number of the caller's notifications as read; an omitted limit is zero. */
- (void)handleUpdateSeen:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Validates a JSON push token and registers it for the authenticated caller. */
- (void)handleRegisterPush:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Removes the authenticated caller's registered push delivery state. */
- (void)handleUnregisterPush:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Lists the caller's activity subscriptions with optional cursor pagination. */
- (void)handleListActivitySubscriptions:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Validates a JSON `subject` and creates or updates that caller's activity subscription. */
- (void)handlePutActivitySubscription:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Returns the authenticated caller's notification preferences. */
- (void)handleGetNotificationPreferences:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;
/** @abstract Validates a JSON `priority` value and updates the caller's notification preferences. */
- (void)handlePutNotificationPreferences:(ATProtoHttpRequest *)request response:(ATProtoHttpResponse *)response;

@end
