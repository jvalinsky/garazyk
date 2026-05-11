// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyUnspeccedPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.unspecced.* and related utility methods.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class AgeAssuranceService;
@class SearchIndexService;
@class FeedService;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyUnspeccedPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
           ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService
              searchIndexService:(nullable SearchIndexService *)searchIndexService
                    feedService:(nullable FeedService *)feedService;

@end

NS_ASSUME_NONNULL_END
