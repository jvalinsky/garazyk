// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  ATProtoXrpcChatBskyGroupPack.h
//  ATProtoPDS
//
//  Namespace pack for chat.bsky.group.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class ATProtoXrpcDispatcher;
/**
 * @abstract Defines the PDSQueryDatabase protocol contract.
 */
@protocol PDSQueryDatabase;
@class ATProtoJWTMinter;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoXrpcChatBskyGroupPack : NSObject <XrpcRoutePack>

/**
 * @abstract Performs the registerWithDispatcher operation.
 */
+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter
              adminController:(nullable id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
