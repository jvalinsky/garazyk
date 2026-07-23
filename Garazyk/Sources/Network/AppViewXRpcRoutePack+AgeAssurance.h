// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/AppViewXRpcRoutePack.h"

@interface AppViewXRpcRoutePack (AgeAssurance)

- (void)handleAgeAssuranceBegin:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAgeAssuranceGetConfig:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAgeAssuranceGetState:(HttpRequest *)request response:(HttpResponse *)response;

@end