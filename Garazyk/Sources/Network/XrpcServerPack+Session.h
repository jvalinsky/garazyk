// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#pragma once

#import "Network/XrpcServerPack.h"
#import "Network/XrpcRoutePackServices.h"
#import "Registration/PDSRegistrationGate.h"

NS_ASSUME_NONNULL_BEGIN

@interface XrpcServerPack (Session)
+ (void)registerAccountCreationAndSessionEndpoints:(XrpcDispatcher *)dispatcher
                                          services:(id<XrpcRoutePackServices>)services
                                 registrationGate:(nullable id<PDSRegistrationGate>)registrationGate;
@end

NS_ASSUME_NONNULL_END
