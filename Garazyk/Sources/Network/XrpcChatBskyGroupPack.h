// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcChatBskyGroupPack.h
//  ATProtoPDS
//
//  Namespace pack for chat.bsky.group.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class XrpcDispatcher;
/**
 * @abstract Defines the PDSQueryDatabase protocol contract.
 */
@protocol PDSQueryDatabase;
@class JWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface XrpcChatBskyGroupPack : NSObject <XrpcRoutePack>

/**
 * @abstract Performs the registerWithDispatcher operation.
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(nullable JWTMinter *)jwtMinter
              adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
