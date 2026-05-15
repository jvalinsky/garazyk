// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyContactPack.h

 @abstract XRPC route pack for app.bsky.contact endpoints.
 */

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class XrpcDispatcher;
@class ContactService;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyContactPack : NSObject <XrpcRoutePack>

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 contactService:(ContactService *)contactService
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
