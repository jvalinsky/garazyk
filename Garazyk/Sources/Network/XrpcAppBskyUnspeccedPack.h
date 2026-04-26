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

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyUnspeccedPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
           ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService
              searchIndexService:(nullable SearchIndexService *)searchIndexService;

@end

NS_ASSUME_NONNULL_END
