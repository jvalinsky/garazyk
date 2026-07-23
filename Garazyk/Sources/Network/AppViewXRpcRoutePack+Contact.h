// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (Contact)

- (void)handleStartPhoneVerification:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleVerifyPhone:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleImportContacts:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetContactMatches:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleDismissContactMatch:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetContactSyncStatus:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRemoveContactData:(HttpRequest *)request response:(HttpResponse *)response;

@end