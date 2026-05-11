// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyDraftsPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.draft.* XRPC endpoints.
//

#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class DraftService;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcAppBskyDraftsPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                  draftService:(DraftService *)draftService
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
