// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcRoutePackServices.h

 @abstract Shared dependency surface for XRPC route packs.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSAgeAssuranceService;
@class ATProtoServiceConfiguration;
@class PDSBookmarkService;
@class PDSContactService;
@class PDSDraftService;
@class PDSNotificationService;
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSRelayService;
@class PDSBlobAuditManager;
@class ATProtoSubscribeReposHandler;
@class PDSSearchIndexService;
@class PDSFeedService;
@class PDSSpaceStore;
@class PDSSpaceReconciler;
@class ATProtoJWTMinter;
@class ATProtoAuthVerifier;
@class PDSServiceDatabases;
@class PDSDatabasePool;
@class ATProtoRateLimiter;
@class ATProtoXrpcDispatcher;
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

@property (nonatomic, readonly, nullable) ATProtoXrpcDispatcher *dispatcher;
@property (nonatomic, readonly, nullable) ATProtoJWTMinter *jwtMinter;
@property (nonatomic, readonly, nullable) ATProtoAuthVerifier *authVerifier;
@property (nonatomic, readonly, nullable) id<PDSAdminController> adminController;
@property (nonatomic, readonly, nullable) ATProtoServiceConfiguration *configuration;
@property (nonatomic, readonly, nullable) NSString *adminSecret;
@property (nonatomic, readonly, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, readonly, nullable) PDSDatabasePool *userDatabasePool;
@property (nonatomic, readonly, nullable) PDSSpaceStore *spaceStore;
@property (nonatomic, readonly, nullable) PDSSpaceReconciler *spaceReconciler;
@property (nonatomic, readonly, nullable) ATProtoRateLimiter *rateLimiter;

/*! Pack-specific services populated before registration when needed. */
@property (nonatomic, readonly, nullable) PDSAgeAssuranceService *ageAssuranceService;
@property (nonatomic, readonly, nullable) PDSBookmarkService *bookmarkService;
@property (nonatomic, readonly, nullable) PDSDraftService *draftService;
@property (nonatomic, readonly, nullable) PDSContactService *contactService;
@property (nonatomic, readonly, nullable) PDSNotificationService *notificationService;
@property (nonatomic, readonly, nullable) PDSRecordService *recordService;
@property (nonatomic, readonly, nullable) PDSBlobService *blobService;
@property (nonatomic, readonly, nullable) PDSRepositoryService *repositoryService;
@property (nonatomic, readonly, nullable) PDSRelayService *relayService;
@property (nonatomic, readonly, nullable) id<PDSAccountService> accountService;
@property (nonatomic, readonly, nullable) id<PDSQueryDatabase> appViewDatabase;
@property (nonatomic, readonly, nullable) id<PDSEmailProvider> emailProvider;
@property (nonatomic, readonly, nullable) ATProtoSubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, readonly, nullable) PDSBlobAuditManager *blobAuditManager;
@property (nonatomic, readonly, nullable) PDSSearchIndexService *searchIndexService;
@property (nonatomic, readonly, nullable) PDSFeedService *feedService;

@property (nonatomic, readonly, nullable) id<VideoJobStore> videoJobStore;
@property (nonatomic, readonly, nullable) id<VideoAuthProvider> videoAuthProvider;
@property (nonatomic, readonly, nullable) id<PDSBlobProvider> blobProvider;

@end

/*!
 @class ATProtoXrpcRoutePackServiceBag

 @abstract Concrete @c XrpcRoutePackServices holder built by the method registry.
 */
@interface ATProtoXrpcRoutePackServiceBag : NSObject <XrpcRoutePackServices>

@property (nonatomic, readonly, nullable) ATProtoXrpcDispatcher *dispatcher;
@property (nonatomic, readonly, nullable) ATProtoJWTMinter *jwtMinter;
@property (nonatomic, strong, nullable) ATProtoAuthVerifier *authVerifier;
@property (nonatomic, readonly, nullable) id<PDSAdminController> adminController;
@property (nonatomic, readonly, nullable) ATProtoServiceConfiguration *configuration;
@property (nonatomic, readonly, nullable) NSString *adminSecret;
@property (nonatomic, readonly, nullable) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, readonly, nullable) PDSDatabasePool *userDatabasePool;
@property (nonatomic, readonly, nullable) ATProtoRateLimiter *rateLimiter;
@property (nonatomic, strong, nullable) PDSAgeAssuranceService *ageAssuranceService;
@property (nonatomic, strong, nullable) PDSBookmarkService *bookmarkService;
@property (nonatomic, strong, nullable) PDSDraftService *draftService;
@property (nonatomic, strong, nullable) PDSContactService *contactService;
@property (nonatomic, strong, nullable) PDSNotificationService *notificationService;
@property (nonatomic, strong, nullable) PDSRecordService *recordService;
@property (nonatomic, strong, nullable) PDSBlobService *blobService;
@property (nonatomic, strong, nullable) PDSRepositoryService *repositoryService;
@property (nonatomic, strong, nullable) PDSRelayService *relayService;
@property (nonatomic, strong, nullable) id<PDSAccountService> accountService;
@property (nonatomic, strong, nullable) id<PDSQueryDatabase> appViewDatabase;
@property (nonatomic, strong, nullable) id<PDSEmailProvider> emailProvider;
@property (nonatomic, strong, nullable) ATProtoSubscribeReposHandler *subscribeReposHandler;
@property (nonatomic, strong, nullable) PDSBlobAuditManager *blobAuditManager;
@property (nonatomic, strong, nullable) PDSSearchIndexService *searchIndexService;
@property (nonatomic, strong, nullable) PDSFeedService *feedService;
@property (nonatomic, strong, nullable) PDSSpaceStore *spaceStore;
@property (nonatomic, strong, nullable) PDSSpaceReconciler *spaceReconciler;

@property (nonatomic, strong, nullable) id<VideoJobStore> videoJobStore;
@property (nonatomic, strong, nullable) id<VideoAuthProvider> videoAuthProvider;
@property (nonatomic, strong, nullable) id<PDSBlobProvider> blobProvider;

/**
 * @abstract Performs the initWithDispatcher operation.
 */
- (instancetype)initWithDispatcher:(nullable ATProtoXrpcDispatcher *)dispatcher
                         jwtMinter:(nullable ATProtoJWTMinter *)jwtMinter
                   adminController:(nullable id<PDSAdminController>)adminController
                      configuration:(nullable ATProtoServiceConfiguration *)configuration
                        adminSecret:(nullable NSString *)adminSecret
                  serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                  userDatabasePool:(nullable PDSDatabasePool *)userDatabasePool
                        rateLimiter:(nullable ATProtoRateLimiter *)rateLimiter
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
