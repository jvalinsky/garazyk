#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSRelayService;
@class PDSConfiguration;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcSyncMethods registers all com.atproto.sync.* endpoint handlers.
 *
 * This module handles repository synchronization operations including:
 * - Repository export: getRepo, getCheckout
 * - Commit operations: getHead, getLatestCommit
 * - Record sync: getRecord
 * - Blob sync: getBlob, listBlobs
 * - Repository listing: listRepos
 * - Host management: getHostStatus, listHosts
 * - Crawl notifications: requestCrawl, notifyOfUpdate
 * - WebSocket subscriptions: subscribeRepos
 */
@interface XrpcSyncMethods : NSObject

/**
 * Register all com.atproto.sync.* endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register handlers with
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin controller for authorization checks
 * @param serviceDatabases Service-level database access
 * @param userDatabasePool User-level database pool
 * @param recordService Record service for record operations
 * @param blobService Blob service for blob storage
 * @param repositoryService Repository service for MST operations
 * @param relayService Relay service for crawl notifications
 * @param config Server configuration
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
              userDatabasePool:(PDSDatabasePool *)userDatabasePool
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
                  relayService:(PDSRelayService *)relayService
                 configuration:(PDSConfiguration *)config;

@end

NS_ASSUME_NONNULL_END
