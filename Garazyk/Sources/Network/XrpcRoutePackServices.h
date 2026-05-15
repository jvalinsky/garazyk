// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcRoutePackServices.h

 @abstract Shared dependency surface for XRPC route packs.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AgeAssuranceService;
@class ATProtoServiceConfiguration;
@class BookmarkService;
@class ContactService;
@class DraftService;
@class NotificationService;
@class JWTMinter;
@class PDSServiceDatabases;
@class RateLimiter;
@class XrpcDispatcher;
@protocol PDSAdminController;
@protocol PDSQueryDatabase;

/*!
 @protocol XrpcRoutePackServices

 @abstract Dependencies commonly required when registering XRPC handlers.
 */
@protocol XrpcRoutePackServices <NSObject>

@property (nonatomic, readonly, nullable) XrpcDispatcher *dispatcher;
@property (nonatomic, readonly, nullable) JWTMinter *jwtMinter;
@property (nonatomic, readonly, nullable) id<PDSAdminController> adminController;
@property (nonatomic, readonly, nullable) ATProtoServiceConfiguration *configuration;
@property (nonatomic, readonly, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, readonly, nullable) RateLimiter *rateLimiter;

/*! Pack-specific services populated before registration when needed. */
@property (nonatomic, readonly, nullable) AgeAssuranceService *ageAssuranceService;
@property (nonatomic, readonly, nullable) BookmarkService *bookmarkService;
@property (nonatomic, readonly, nullable) DraftService *draftService;
@property (nonatomic, readonly, nullable) ContactService *contactService;
@property (nonatomic, readonly, nullable) NotificationService *notificationService;
@property (nonatomic, readonly, nullable) id<PDSQueryDatabase> appViewDatabase;

@end

/*!
 @class XrpcRoutePackServiceBag

 @abstract Concrete @c XrpcRoutePackServices holder built by the method registry.
 */
@interface XrpcRoutePackServiceBag : NSObject <XrpcRoutePackServices>

@property (nonatomic, readonly, nullable) XrpcDispatcher *dispatcher;
@property (nonatomic, readonly, nullable) JWTMinter *jwtMinter;
@property (nonatomic, readonly, nullable) id<PDSAdminController> adminController;
@property (nonatomic, readonly, nullable) ATProtoServiceConfiguration *configuration;
@property (nonatomic, readonly, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, readonly, nullable) RateLimiter *rateLimiter;
@property (nonatomic, strong, nullable) AgeAssuranceService *ageAssuranceService;
@property (nonatomic, strong, nullable) BookmarkService *bookmarkService;
@property (nonatomic, strong, nullable) DraftService *draftService;
@property (nonatomic, strong, nullable) ContactService *contactService;
@property (nonatomic, strong, nullable) NotificationService *notificationService;
@property (nonatomic, strong, nullable) id<PDSQueryDatabase> appViewDatabase;

- (instancetype)initWithDispatcher:(nullable XrpcDispatcher *)dispatcher
                         jwtMinter:(nullable JWTMinter *)jwtMinter
                   adminController:(nullable id<PDSAdminController>)adminController
                      configuration:(nullable ATProtoServiceConfiguration *)configuration
                  serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                        rateLimiter:(nullable RateLimiter *)rateLimiter
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
