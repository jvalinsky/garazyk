// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class JWTMinter;
@class PDSRecordService;
@class PDSBlobService;
@class PDSRepositoryService;
@class PDSServiceDatabases;
@class RateLimiter;
@protocol PDSAccountService;
@protocol PDSAdminController;

NS_ASSUME_NONNULL_BEGIN

/**
 * XrpcRepoMethods registers all com.atproto.repo.* endpoint handlers.
 *
 * This module handles repository operations including:
 * - Record CRUD: createRecord, putRecord, deleteRecord, getRecord, listRecords
 * - Repository metadata: describeRepo
 * - Blob operations: uploadBlob, deleteBlob, listMissingBlobs
 * - Batch operations: applyWrites
 * - Repository import: importRepo
 */
@interface XrpcRepoMethods : NSObject

/**
 * Register all com.atproto.repo.* endpoint handlers with the dispatcher.
 *
 * @param dispatcher The XRPC dispatcher to register handlers with
 * @param jwtMinter JWT token minter for authentication
 * @param adminController Admin controller for authorization checks
 * @param accountService Account service for account lookups
 * @param recordService Record service for record operations
 * @param blobService Blob service for blob storage
 * @param repositoryService Repository service for MST operations
 * @param serviceDatabases Service-level database access
 */
+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
                accountService:(id<PDSAccountService>)accountService
                 recordService:(PDSRecordService *)recordService
                   blobService:(PDSBlobService *)blobService
             repositoryService:(PDSRepositoryService *)repositoryService
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END
Limiter;

@end

NS_ASSUME_NONNULL_END
