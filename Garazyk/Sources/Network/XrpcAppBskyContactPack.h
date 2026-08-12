// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoXrpcAppBskyContactPack.h

 @abstract XRPC route pack for app.bsky.contact endpoints.
 */

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class ATProtoXrpcDispatcher;
@class PDSContactService;
@class ATProtoJWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoXrpcAppBskyContactPack : NSObject <XrpcRoutePack>

/**
 * @abstract Performs the registerWithDispatcher operation.
 */
+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                 contactService:(PDSContactService *)contactService
                      jwtMinter:(ATProtoJWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
