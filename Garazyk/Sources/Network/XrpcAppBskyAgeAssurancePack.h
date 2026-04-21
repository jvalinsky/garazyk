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
