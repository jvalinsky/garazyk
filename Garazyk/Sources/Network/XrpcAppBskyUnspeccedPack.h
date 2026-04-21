//
//  XrpcAppBskyUnspeccedPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.unspecced.* and related utility methods.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class AgeAssuranceService;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyUnspeccedPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
           ageAssuranceService:(nullable AgeAssuranceService *)ageAssuranceService;

@end

NS_ASSUME_NONNULL_END
