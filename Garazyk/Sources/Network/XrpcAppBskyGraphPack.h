// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcAppBskyGraphPack.h
//  ATProtoPDS
//
//  Namespace pack for app.bsky.graph.* XRPC endpoints.
//

#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

@class XrpcDispatcher;
@class JWTMinter;
@class PDSDatabase;
@class PDSServiceDatabases;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

@class PDSRecordService;

/**
 @brief Namespace pack for app.bsky.graph.* endpoints.
 */
@interface XrpcAppBskyGraphPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                  recordService:(nullable PDSRecordService *)recordService
                 appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                      jwtMinter:(JWTMinter *)jwtMinter
                adminController:(id<PDSAdminController>)adminController;

@end

NS_ASSUME_NONNULL_END
