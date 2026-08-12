// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZAuthzManager.m

 @abstract Authorization manager implementation with policy enforcement.

 @discussion Implements access control checks for repo access, record operations,
 and admin functions. Validates DID formats, URI patterns, and enforces ownership
 rules. Manages admin endpoint detection and authorization verification.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Security/GZAuthzManager.h"
#import "Database/PDSDatabase.h"
#import "Security/GZInputValidator.h"

NSErrorDomain const GZAuthzErrorDomain = @"com.atproto.pds.authz";

static NSSet<NSString *> *kNonNamespaceAdminMethods = nil;

@interface GZAuthzManager ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation GZAuthzManager

+ (void)initialize {
    if (self == [GZAuthzManager class]) {
        kNonNamespaceAdminMethods = [NSSet setWithArray:@[
            @"com.atproto.temp.addReservedHandle",
        ]];
    }
}

+ (instancetype)sharedManager {
    static GZAuthzManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GZAuthzManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _database = nil;
    }
    return self;
}

- (void)setDatabase:(PDSDatabase *)database {
    _database = database;
}

- (BOOL)isAuthorizedToAccessRepo:(NSString *)repoDID
                    requestingDID:(NSString *)requestingDID
                            error:(NSError **)error {
    if (!repoDID || !requestingDID) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }

    if (![[GZInputValidator sharedValidator] isValidDID:repoDID]) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid repo DID format"}];
        }
        return NO;
    }

    if ([repoDID isEqualToString:requestingDID]) {
        return YES;
    }

    PDSDatabaseRepo *repo = [self.database getRepoForDid:repoDID error:nil];
    if (!repo) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorRepoNotFound userInfo:@{NSLocalizedDescriptionKey: @"Repository not found"}];
        }
        return NO;
    }

    if (![repo.ownerDid isEqualToString:requestingDID]) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorRepoOwnershipMismatch userInfo:@{NSLocalizedDescriptionKey: @"Not authorized to access this repository"}];
        }
        return NO;
    }

    return YES;
}

- (BOOL)isAuthorizedToModifyRecord:(NSString *)recordURI
                      repositoryDID:(NSString *)repositoryDID
                     requestingDID:(NSString *)requestingDID
                             error:(NSError **)error {
    if (!recordURI || !repositoryDID || !requestingDID) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }

    if (![[GZInputValidator sharedValidator] isValidATURI:recordURI]) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid record URI format"}];
        }
        return NO;
    }

    return [self isAuthorizedToAccessRepo:repositoryDID requestingDID:requestingDID error:error];
}

- (BOOL)isAuthorizedToCreateRecord:(NSString *)collection
                       repositoryDID:(NSString *)repositoryDID
                      requestingDID:(NSString *)requestingDID
                              error:(NSError **)error {
    if (!collection || !repositoryDID || !requestingDID) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }

    if (![[GZInputValidator sharedValidator] isValidCollectionName:collection]) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid collection name format"}];
        }
        return NO;
    }

    return [self isAuthorizedToAccessRepo:repositoryDID requestingDID:requestingDID error:error];
}

- (BOOL)isAuthorizedToDeleteRecord:(NSString *)recordURI
                      repositoryDID:(NSString *)repositoryDID
                     requestingDID:(NSString *)requestingDID
                             error:(NSError **)error {
    return [self isAuthorizedToModifyRecord:recordURI repositoryDID:repositoryDID requestingDID:requestingDID error:error];
}

- (BOOL)isAdminEndpoint:(NSString *)xrpcMethod {
    if (!xrpcMethod) return NO;
    if ([xrpcMethod hasPrefix:@"com.atproto.admin."]) {
        return YES;
    }
    return [kNonNamespaceAdminMethods containsObject:xrpcMethod];
}

- (BOOL)isAuthorizedForAdminOperation:(NSString *)requestingDID error:(NSError **)error {
    // Admin authorization is determined by ATProtoJWT scope validation in the XRPC
    // handler layer (ATProtoXrpcAuthHelper / ATProtoXrpcMethodRegistry). This method exists
    // only for backward compatibility and always returns NO as a safe default.
    // The discarded getAccountByDid: query has been removed per workstream 01
    // S8 slice 7. Do not add grant logic here — wire it through the auth cluster.
    if (error) {
        *error = [NSError errorWithDomain:GZAuthzErrorDomain
                                     code:GZAuthzErrorAdminRequired
                                 userInfo:@{NSLocalizedDescriptionKey: @"Admin privileges required (verify JWT 'admin' scope)"}];
    }
    return NO;
}

- (BOOL)validateWriteAccess:(NSString *)repoDID
             forCollection:(NSString *)collection
                   rkey:(NSString *)rkey
               actorDID:(NSString *)actorDID
                   error:(NSError **)error {
    if (![self isAuthorizedToCreateRecord:collection repositoryDID:repoDID requestingDID:actorDID error:error]) {
        return NO;
    }

    if (![[GZInputValidator sharedValidator] isValidRecordKey:rkey]) {
        if (error) {
            *error = [NSError errorWithDomain:GZAuthzErrorDomain code:GZAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid record key format"}];
        }
        return NO;
    }

    return YES;
}

- (BOOL)validateReadAccess:(NSString *)repoDID
          forCollection:(nullable NSString *)collection
                  actorDID:(NSString *)actorDID
                    error:(NSError **)error {
    if (![self isAuthorizedToAccessRepo:repoDID requestingDID:actorDID error:error]) {
        return NO;
    }

    // Mute/block enforcement is handled by ATProtoAuthVerifier and the XRPC handler
    // layer, not by this basic repo-access check. The previous branch here
    // checked for account existence (which always succeeds for the owner) and
    // then returned NO, effectively denying owners reading their own posts.
    // That branch has been removed per workstream 01 S8 slice 7.

    return YES;
}

@end
