/*!
 @file PDSAuthzManager.m

 @abstract Authorization manager implementation with policy enforcement.

 @discussion Implements access control checks for repo access, record operations,
 and admin functions. Validates DID formats, URI patterns, and enforces ownership
 rules. Manages admin endpoint detection and authorization verification.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Security/PDSAuthzManager.h"
#import "Database/PDSDatabase.h"
#import "Security/PDSInputValidator.h"

NSErrorDomain const PDSAuthzErrorDomain = @"com.atproto.pds.authz";

static NSSet<NSString *> *kNonNamespaceAdminMethods = nil;

@interface PDSAuthzManager ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation PDSAuthzManager

+ (void)initialize {
    if (self == [PDSAuthzManager class]) {
        kNonNamespaceAdminMethods = [NSSet setWithArray:@[
            @"com.atproto.temp.addReservedHandle",
        ]];
    }
}

+ (instancetype)sharedManager {
    static PDSAuthzManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PDSAuthzManager alloc] init];
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
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }

    if (![[PDSInputValidator sharedValidator] isValidDID:repoDID]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid repo DID format"}];
        }
        return NO;
    }

    if ([repoDID isEqualToString:requestingDID]) {
        return YES;
    }

    PDSDatabaseRepo *repo = [self.database getRepoForDid:repoDID error:nil];
    if (!repo) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorRepoNotFound userInfo:@{NSLocalizedDescriptionKey: @"Repository not found"}];
        }
        return NO;
    }

    if (![repo.ownerDid isEqualToString:requestingDID]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorRepoOwnershipMismatch userInfo:@{NSLocalizedDescriptionKey: @"Not authorized to access this repository"}];
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
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }

    if (![[PDSInputValidator sharedValidator] isValidATURI:recordURI]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid record URI format"}];
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
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Missing required parameters"}];
        }
        return NO;
    }

    if (![[PDSInputValidator sharedValidator] isValidCollectionName:collection]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid collection name format"}];
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
    if (!requestingDID) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorAdminRequired userInfo:@{NSLocalizedDescriptionKey: @"Admin authentication required"}];
        }
        return NO;
    }

    PDSDatabaseAccount *account = [self.database getAccountByDid:requestingDID error:nil];
    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }

    // P0 Security Fix: Removed handle/DID prefix-based admin escalation.
    // Admin privileges must be granted via JWT scope 'admin' signed by the correct issuer.
    // This method now returns NO by default to prevent unauthorized access via this path.
    // The calling layer (XrpcMethodRegistry) is responsible for verifying the admin JWT.
    
    if (error) {
        *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorAdminRequired userInfo:@{NSLocalizedDescriptionKey: @"Admin privileges required (check JWT scope)"}];
    }
    return NO;

    return YES;
}

- (BOOL)validateWriteAccess:(NSString *)repoDID
             forCollection:(NSString *)collection
                   rkey:(NSString *)rkey
               actorDID:(NSString *)actorDID
                   error:(NSError **)error {
    if (![self isAuthorizedToCreateRecord:collection repositoryDID:repoDID requestingDID:actorDID error:error]) {
        return NO;
    }

    if (![[PDSInputValidator sharedValidator] isValidRecordKey:rkey]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorUnauthorized userInfo:@{NSLocalizedDescriptionKey: @"Invalid record key format"}];
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

    if (collection && ![collection isEqualToString:@"app.bsky.actor.profile"]) {
        NSArray *mutedCollections = @[@"app.bsky.feed.post", @"app.bsky.feed.repost", @"app.bsky.feed.like"];
        if ([mutedCollections containsObject:collection]) {
            PDSDatabaseAccount *account = [self.database getAccountByDid:repoDID error:nil];
            if (account) {
                return NO;
            }
        }
    }

    return YES;
}

@end
