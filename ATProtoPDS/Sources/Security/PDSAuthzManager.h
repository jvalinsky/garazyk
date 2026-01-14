/*!
 @file PDSAuthzManager.h

 @abstract Authorization management for ATProto PDS operations.

 @discussion Enforces access control policies for repository access, record
 operations (create, read, update, delete), and admin endpoints. Validates
 ownership, session validity, and administrative privileges.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class PDSDatabase;
@class PDSDatabaseRepo;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const PDSAuthzErrorDomain;

typedef NS_ENUM(NSInteger, PDSAuthzError) {
    PDSAuthzErrorUnauthorized = 2000,
    PDSAuthzErrorRepoNotFound = 2001,
    PDSAuthzErrorRepoOwnershipMismatch = 2002,
    PDSAuthzErrorInvalidSession = 2003,
    PDSAuthzErrorInsufficientScope = 2004,
    PDSAuthzErrorAdminRequired = 2005,
};

@interface PDSAuthzManager : NSObject

+ (instancetype)sharedManager;

- (BOOL)isAuthorizedToAccessRepo:(NSString *)repoDID
                    requestingDID:(NSString *)requestingDID
                            error:(NSError **)error;

- (BOOL)isAuthorizedToModifyRecord:(NSString *)recordURI
                      repositoryDID:(NSString *)repositoryDID
                     requestingDID:(NSString *)requestingDID
                             error:(NSError **)error;

- (BOOL)isAuthorizedToCreateRecord:(NSString *)collection
                       repositoryDID:(NSString *)repositoryDID
                      requestingDID:(NSString *)requestingDID
                              error:(NSError **)error;

- (BOOL)isAuthorizedToDeleteRecord:(NSString *)recordURI
                      repositoryDID:(NSString *)repositoryDID
                     requestingDID:(NSString *)requestingDID
                             error:(NSError **)error;

- (BOOL)isAdminEndpoint:(NSString *)xrpcMethod;
- (BOOL)isAuthorizedForAdminOperation:(NSString *)requestingDID error:(NSError **)error;

- (BOOL)validateWriteAccess:(NSString *)repoDID
             forCollection:(NSString *)collection
                   rkey:(NSString *)rkey
               actorDID:(NSString *)actorDID
                   error:(NSError **)error;

- (BOOL)validateReadAccess:(NSString *)repoDID
          forCollection:(nullable NSString *)collection
                  actorDID:(NSString *)actorDID
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
