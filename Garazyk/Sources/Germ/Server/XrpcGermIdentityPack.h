/*!
 @file XrpcGermIdentityPack.h

 @abstract XRPC handler registration for Germ AC Protocol identity.

 @discussion Registers com.germnetwork.identity.* XRPC endpoints
 for the Germ Protocol identity layer. Models after Germ's current
 shipping 1:1 E2EE DM product.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class GermIdentityService;
@class ChatAuthManager;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcGermIdentityPack : NSObject

- (instancetype)initWithIdentityService:(GermIdentityService *)identityService
                            authManager:(ChatAuthManager *)authManager;

- (void)registerHandlersWithDispatcher:(XrpcDispatcher *)dispatcher;

@end

NS_ASSUME_NONNULL_END
