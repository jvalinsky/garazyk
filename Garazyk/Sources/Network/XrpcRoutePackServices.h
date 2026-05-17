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
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSRelayService;
@class PDSBlobAuditManager;
@class SubscribeReposHandler;
@class SearchIndexService;
@class FeedService;
@class JWTMinter;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class RateLimiter;
@class XrpcDispatcher;
/**
 * @abstract Defines the PDSAdminController protocol contract.
 */
@protocol PDSAdminController;
@protocol PDSQueryDatabase;
@protocol VideoJobStore;
@protocol VideoAuthProvider;
@protocol PDSBlobProvider;
@protocol PDSAccountService;
@protocol PDSEmailProvider;

/*!
 @protocol XrpcRoutePackServices

 @abstract Dependencies commonly required when registering XRPC handlers.
 */
@protocol XrpcRoutePackServices <NSObject>

@property (nonatomic, readonly, nullable) XrpcDispatcher *dispatcher;
@property (nonatomic, readonly, nullable) JWTMinter *jwtMinter;
@property (nonatomic, readonly, nullable) id<PDSAdminController> adminController;
@property (nonatomic, readonly, nullable) ATProtoServiceConfiguration *configuration;
@property (nonatomic, readonly, nullable) NSString *adminSecret;
@property (nonatomic, readonly, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, readonly, nullable) PDSDatabasePool *userDatabasePool;
@property (nonatomic, readonly, nullable) RateLimiter *rateLimiter;

/*! Pack-specific services populated before registration when needed. */
@property (nonatomic, readonly, nullable) AgeAssuranceService *ageAssuranceService;
@property (nonatomic, readonly, nullable) BookmarkService *bookmarkService;
@property (nonatomic, readonly, nullable) DraftService *draftService;
@property (nonatomic, readonly, nullable) ContactService *contactService;
@property (nonatomic, readonly, nullable) NotificationService *notificationService;
@property (nonatomic, readonly, nullable) PDSRecordService *recordService;
@property (nonatomic, readonly, nullable) PDSBlobService *blobService;
@property (nonatomic, readonly, nullable) PDSRepositoryService *repositoryService;
@property (nonatomic, readonly, nullable) PDSRelayService *relayService;
@property (nonatomic, readonly, nullable) id<PDSAccountService> accountService;
@property (nonatomic, readonly, nullable) id<PDSQueryDatabase> appViewDatabase;
@property (nonatomic, readonly, nullable) id<PDSEmailProvider> emailProvider;
@property (nonatomic, readonly, nullable) SubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, readonly, nullable) PDSBlobAuditManager *blobAuditManager;
@property (nonatomic, readonly, nullable) SearchIndexService *searchIndexService;
@property (nonatomic, readonly, nullable) FeedService *feedService;

@property (nonatomic, readonly, nullable) id<VideoJobStore> videoJobStore;
@property (nonatomic, readonly, nullable) id<VideoAuthProvider> videoAuthProvider;
@property (nonatomic, readonly, nullable) id<PDSBlobProvider> blobProvider;

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
@property (nonatomic, readonly, nullable) NSString *adminSecret;
@property (nonatomic, readonly, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, readonly, nullable) PDSDatabasePool *userDatabasePool;
@property (nonatomic, readonly, nullable) RateLimiter *rateLimiter;
@property (nonatomic, strong, nullable) AgeAssuranceService *ageAssuranceService;
@property (nonatomic, strong, nullable) BookmarkService *bookmarkService;
@property (nonatomic, strong, nullable) DraftService *draftService;
@property (nonatomic, strong, nullable) ContactService *contactService;
@property (nonatomic, strong, nullable) NotificationService *notificationService;
@property (nonatomic, strong, nullable) PDSRecordService *recordService;
@property (nonatomic, strong, nullable) PDSBlobService *blobService;
@property (nonatomic, strong, nullable) PDSRepositoryService *repositoryService;
@property (nonatomic, strong, nullable) PDSRelayService *relayService;
@property (nonatomic, strong, nullable) id<PDSAccountService> accountService;
@property (nonatomic, strong, nullable) id<PDSQueryDatabase> appViewDatabase;
@property (nonatomic, strong, nullable) id<PDSEmailProvider> emailProvider;
@property (nonatomic, strong, nullable) SubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, strong, nullable) PDSBlobAuditManager *blobAuditManager;
@property (nonatomic, strong, nullable) SearchIndexService *searchIndexService;
@property (nonatomic, strong, nullable) FeedService *feedService;

@property (nonatomic, strong, nullable) id<VideoJobStore> videoJobStore;
@property (nonatomic, strong, nullable) id<VideoAuthProvider> videoAuthProvider;
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/**
 * @abstract Performs the initWithDispatcher operation.
 */
- (instancetype)initWithDispatcher:(nullable XrpcDispatcher *)dispatcher
                         jwtMinter:(nullable JWTMinter *)jwtMinter
                   adminController:(nullable id<PDSAdminController>)adminController
                      configuration:(nullable ATProtoServiceConfiguration *)configuration
                        adminSecret:(nullable NSString *)adminSecret
                  serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                  userDatabasePool:(nullable PDSDatabasePool *)userDatabasePool
                        rateLimiter:(nullable RateLimiter *)rateLimiter
    NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Returns the operation result.
 */
- (instancetype)init NS_UNAVAILABLE;
/**
 * @abstract Returns the operation result.
 */
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
