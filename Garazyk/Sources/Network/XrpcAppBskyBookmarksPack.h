// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  ATProtoXrpcAppBskyBookmarksPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.bookmark.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class PDSBookmarkService;
@class ATProtoJWTMinter;
@class ATProtoXrpcDispatcher;
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoXrpcAppBskyBookmarksPack : NSObject <XrpcRoutePack>

/**
 * @abstract Performs the registerWithDispatcher operation.
 */
+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
               bookmarkService:(PDSBookmarkService *)bookmarkService
                     jwtMinter:(ATProtoJWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
