#import "Security/PDSAuthzManager.h"
#import "Database/PDSDatabase.h"
#import "Security/PDSInputValidator.h"

NSErrorDomain const PDSAuthzErrorDomain = @"com.atproto.pds.authz";

static NSSet<NSString *> *kAdminMethods = nil;

@interface PDSAuthzManager ()
@property (nonatomic, strong) PDSDatabase *database;
#if defined(__linux__) || defined(__GNUstep__)
@property (nonatomic, assign) dispatch_queue_t dbQueue;
#else
@property (nonatomic, strong) dispatch_queue_t dbQueue;
#endif
@end

@implementation PDSAuthzManager

+ (void)initialize {
    if (self == [PDSAuthzManager class]) {
        kAdminMethods = [NSSet setWithArray:@[
            @"com.atproto.admin.getAccountInfo",
            @"com.atproto.admin.getInviteCodes",
            @"com.atproto.admin.resolveModerationReports",
            @"com.atproto.admin.takeModerationAction",
            @"com.atproto.admin.disableAccountInvites",
            @"com.atproto.admin.enableAccountInvites",
            @"com.atproto.admin.deleteAccount",
            @"com.atproto.admin.updateAccountEmail",
            @"com.atproto.admin.updateAccountHandle",
            @"com.atproto.server.createInviteCode",
            @"com.atproto.server.createInviteCodes",
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
    return [kAdminMethods containsObject:xrpcMethod];
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

    BOOL isAdmin = [account.handle hasPrefix:@"admin."] || [requestingDID hasPrefix:@"did:plc:admin"];
    if (!isAdmin) {
        if (error) {
            *error = [NSError errorWithDomain:PDSAuthzErrorDomain code:PDSAuthzErrorAdminRequired userInfo:@{NSLocalizedDescriptionKey: @"Admin privileges required"}];
        }
        return NO;
    }

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
