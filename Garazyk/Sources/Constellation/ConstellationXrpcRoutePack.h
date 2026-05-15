// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ConstellationXrpcRoutePack.h

 @abstract XRPC routes for Microcosm-compatible Constellation endpoints.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ConstellationDatabase;
@class HttpRequest;
@class HttpResponse;
@class HttpServer;

@interface ConstellationXrpcRoutePack : NSObject

- (instancetype)initWithDatabase:(ConstellationDatabase *)database NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)registerRoutesWithServer:(HttpServer *)server;

- (void)handleGetBacklinks:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetBacklinkDids:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetBacklinksCount:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetManyToMany:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetManyToManyCounts:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleResolveMiniDoc:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleGetRecordByUri:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
