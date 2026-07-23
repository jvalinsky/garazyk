// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Notification)

- (void)handleListNotifications:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetUnreadCount:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleUpdateSeen:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRegisterPush:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleUnregisterPush:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleListActivitySubscriptions:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePutActivitySubscription:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetNotificationPreferences:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePutNotificationPreferences:(HttpRequest *)request response:(HttpResponse *)response;

@end