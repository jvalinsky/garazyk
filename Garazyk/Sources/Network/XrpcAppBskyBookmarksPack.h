// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyBookmarksPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.bookmark.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class BookmarkService;
@class JWTMinter;
@class XrpcDispatcher;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyBookmarksPack : NSObject <XrpcRoutePack>

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               bookmarkService:(BookmarkService *)bookmarkService
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
