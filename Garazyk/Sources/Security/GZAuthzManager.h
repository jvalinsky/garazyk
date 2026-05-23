// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAuthzManager.h

 @abstract Authorization management for ATProto PDS operations.

 @discussion Enforces access control policies for repository access, record
 operations (create, read, update, delete), and admin endpoints. Validates
 ownership, session validity, and administrative privileges.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSDatabase;
@class PDSDatabaseRepo;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const GZAuthzErrorDomain;

/**
 * @abstract Authorization failures returned by GZAuthzManager.
 */
typedef NS_ENUM(NSInteger, GZAuthzError) {
    /** The caller is not authenticated for the requested operation. */
    GZAuthzErrorUnauthorized = 2000,
    /** The requested repository could not be found. */
    GZAuthzErrorRepoNotFound = 2001,
    /** The authenticated actor does not own the target repository. */
    GZAuthzErrorRepoOwnershipMismatch = 2002,
    /** The supplied session is absent, expired, or invalid. */
    GZAuthzErrorInvalidSession = 2003,
    /** The caller lacks the scope required by the operation. */
    GZAuthzErrorInsufficientScope = 2004,
    /** The operation requires administrative authorization. */
    GZAuthzErrorAdminRequired = 2005,
};

/**
 * @abstract Central authorization policy for repository, record, and admin operations.
 */
@interface GZAuthzManager : NSObject

/**
 * @abstract Returns the process-wide authorization manager instance.
 */
+ (instancetype)sharedManager;

/**
 * @abstract Creates an authorization manager with no configured database.
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Sets the database used for repository ownership and session checks.
 * @param database The database backing authorization decisions.
 */
- (void)setDatabase:(PDSDatabase *)database;

/**
 * @abstract Validates read access to a repository.
 * @param repoDID The repository DID being accessed.
 * @param requestingDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the requester may access the repository.
 */
- (BOOL)isAuthorizedToAccessRepo:(NSString *)repoDID
                    requestingDID:(NSString *)requestingDID
                            error:(NSError **)error;

/**
 * @abstract Validates update access for an existing record.
 * @param recordURI The AT URI of the record being modified.
 * @param repositoryDID The repository DID containing the record.
 * @param requestingDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the requester may modify the record.
 */
- (BOOL)isAuthorizedToModifyRecord:(NSString *)recordURI
                      repositoryDID:(NSString *)repositoryDID
                     requestingDID:(NSString *)requestingDID
                             error:(NSError **)error;

/**
 * @abstract Validates create access for a collection in a repository.
 * @param collection The NSID of the target collection.
 * @param repositoryDID The repository DID that will own the record.
 * @param requestingDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the requester may create the record.
 */
- (BOOL)isAuthorizedToCreateRecord:(NSString *)collection
                       repositoryDID:(NSString *)repositoryDID
                      requestingDID:(NSString *)requestingDID
                              error:(NSError **)error;

/**
 * @abstract Validates delete access for an existing record.
 * @param recordURI The AT URI of the record being deleted.
 * @param repositoryDID The repository DID containing the record.
 * @param requestingDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the requester may delete the record.
 */
- (BOOL)isAuthorizedToDeleteRecord:(NSString *)recordURI
                      repositoryDID:(NSString *)repositoryDID
                     requestingDID:(NSString *)requestingDID
                             error:(NSError **)error;

/**
 * @abstract Returns whether an XRPC method is treated as an admin endpoint.
 * @param xrpcMethod The method NSID to classify.
 */
- (BOOL)isAdminEndpoint:(NSString *)xrpcMethod;

/**
 * @abstract Validates administrative access for a requester.
 * @param requestingDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the requester may perform admin operations.
 */
- (BOOL)isAuthorizedForAdminOperation:(NSString *)requestingDID error:(NSError **)error;

/**
 * @abstract Validates write access for a specific collection and record key.
 * @param repoDID The repository DID being written.
 * @param collection The NSID of the target collection.
 * @param rkey The record key being written.
 * @param actorDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the actor may write the target record.
 */
- (BOOL)validateWriteAccess:(NSString *)repoDID
             forCollection:(NSString *)collection
                   rkey:(NSString *)rkey
               actorDID:(NSString *)actorDID
                   error:(NSError **)error;

/**
 * @abstract Validates read access for a repository or collection.
 * @param repoDID The repository DID being read.
 * @param collection The optional collection NSID being read.
 * @param actorDID The actor DID making the request.
 * @param error Receives an authorization error when access is denied.
 * @return YES when the actor may read the target data.
 */
- (BOOL)validateReadAccess:(NSString *)repoDID
          forCollection:(nullable NSString *)collection
                  actorDID:(NSString *)actorDID
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
