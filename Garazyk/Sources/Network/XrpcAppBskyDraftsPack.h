// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  ATProtoXrpcAppBskyDraftsPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.draft.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Network/XrpcRoutePack.h"

@class ATProtoXrpcDispatcher;
@class PDSDraftService;
@class ATProtoJWTMinter;
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoXrpcAppBskyDraftsPack : NSObject <XrpcRoutePack>

/**
 * @abstract Performs the registerWithDispatcher operation.
 */
+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                  draftService:(PDSDraftService *)draftService
                     jwtMinter:(ATProtoJWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
