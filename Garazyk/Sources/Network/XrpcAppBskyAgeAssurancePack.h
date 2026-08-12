// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoXrpcAppBskyAgeAssurancePack.h

 @abstract XRPC route pack for app.bsky.ageassurance endpoints.
 */

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class ATProtoXrpcDispatcher;
@class PDSAgeAssuranceService;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoXrpcAppBskyAgeAssurancePack : NSObject <XrpcRoutePack>

/*! Legacy entry point retained for call sites not yet on @c XrpcRoutePackServices. */
+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
           ageAssuranceService:(nullable PDSAgeAssuranceService *)ageAssuranceService;

@end

NS_ASSUME_NONNULL_END
