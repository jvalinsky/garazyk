// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyAgeAssurancePack.h

 @abstract XRPC route pack for app.bsky.ageassurance endpoints.
 */

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class AgeAssuranceService;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyAgeAssurancePack : NSObject

/*! Register all app.bsky.ageassurance routes with the dispatcher. */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
           ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService;

@end

NS_ASSUME_NONNULL_END
