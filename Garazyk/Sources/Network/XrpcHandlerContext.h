// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcHandlerContext.h

 @abstract Per-request context for XRPC route-pack handlers.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;
@protocol XrpcRoutePackServices;

/*!
 @class XrpcHandlerContext

 @abstract Bundles request/response state and authentication helpers for handlers.
 */
@interface XrpcHandlerContext : NSObject

@property (nonatomic, readonly) HttpRequest *request;
@property (nonatomic, readonly) HttpResponse *response;
@property (nonatomic, readonly) id<XrpcRoutePackServices> services;
@property (nonatomic, readonly, nullable) NSString *authenticatedDID;

- (instancetype)initWithRequest:(HttpRequest *)request
                       response:(HttpResponse *)response
                       services:(id<XrpcRoutePackServices>)services
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/*!
 @brief Require a valid Authorization header.

 @discussion When @c jwtMinter and @c adminController are available on
 @c services, validates the token via @c XrpcAuthHelper. Otherwise only
 checks that a non-empty Authorization header is present (standalone chat).
 */
- (BOOL)requireAuthentication;

/*!
 @brief Require authentication and return the authenticated DID when available.
 */
- (BOOL)requireAuthenticatedDID:(NSString * _Nullable * _Nullable)did;

@end

NS_ASSUME_NONNULL_END
