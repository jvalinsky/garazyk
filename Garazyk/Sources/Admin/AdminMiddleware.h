// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AdminMiddleware.h

 @abstract Admin authentication middleware for protected endpoints.

 @discussion Provides authentication and authorization for admin-only endpoints.
 Verifies admin access based on session tokens and configurable admin DID lists.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for admin middleware. */
extern NSString * const AdminMiddlewareErrorDomain;

/*!

 @abstract Error codes for admin authentication.

 @constant AdminMiddlewareErrorNoAuthHeader Missing Authorization header.
 @constant AdminMiddlewareErrorInvalidToken Token is invalid.
 @constant AdminMiddlewareErrorNotAdmin User is not an admin.
 @constant AdminMiddlewareErrorSessionExpired Session has expired.
 */
typedef NS_ENUM(NSInteger, AdminMiddlewareError) {
    AdminMiddlewareErrorNoAuthHeader = 1000,
    AdminMiddlewareErrorInvalidToken,
    AdminMiddlewareErrorNotAdmin,
    AdminMiddlewareErrorSessionExpired
};

@class HttpRequest;
@class HttpResponse;
@class Session;

/*! Block type for custom admin authorization checks. */
typedef BOOL (^AdminAuthCheckBlock)(Session *session);

/*!
 @class AdminMiddleware

 @abstract Middleware for admin endpoint protection.
 */
@interface AdminMiddleware : NSObject

/*! Custom block for additional admin checks. */
@property (nonatomic, copy, nullable) AdminAuthCheckBlock customAdminCheck;

/*! List of DIDs authorized as admins. */
@property (nonatomic, copy) NSArray<NSString *> *adminDids;

/*! Returns the shared middleware instance. */
+ (instancetype)sharedMiddleware;

/*! Verifies admin access for a request. */
- (BOOL)verifyAdminAccessForRequest:(HttpRequest *)request
                           response:(HttpResponse *)response
                              error:(NSError **)error;

/*! Extracts session from request authorization header. */
- (nullable Session *)extractSessionFromRequest:(HttpRequest *)request
                                         error:(NSError **)error;

/*! Sets the list of admin DIDs. */
- (void)setAdminDids:(NSArray<NSString *> *)adminDids;

@end

NS_ASSUME_NONNULL_END
