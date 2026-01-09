#import "PDSController.h"
#import "Database/PDSDatabase.h"
#import "Identity/ATProtoHandleValidator.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Repository/MST.h"
#import "Repository/MSTPersistence.h"
#import "Repository/MSTPersistence.h"
#import "Blob/BlobStorage.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Auth/JWT.h"
#import "Sync/SubscribeReposHandler.h"
#import "Repository/RepoCommit.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSConfiguration.h"
#import <os/log.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString *const PDSControllerErrorDomain = @"com.atproto.pds.controller";
NSString *const kDefaultPlcServerURL = @"https://plc.directory";

@implementation PDSController {
    os_log_t _log;
    PDSServiceDatabases *_serviceDatabases;
    PDSDatabasePool *_userDatabasePool;
    NSMutableDictionary<NSString *, MST *> *_repos;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_collections;
    dispatch_queue_t _repoQueue;
    dispatch_queue_t _controllerQueue;
    SubscribeReposHandler *_subscribeReposHandler;
    NSString *_dataDirectory;
    BOOL _running;
}

- (NSString *)dataDirectory {
    return _dataDirectory;
}

- (id)database {
    return nil;
}

+ (instancetype)sharedController {
    static PDSController *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSController alloc] initWithDirectory:[self defaultDataDirectory]
                                           serviceMaxSize:100
                                         userDatabaseSize:30000];
    });
    return shared;
}

+ (NSString *)defaultDataDirectory {
    NSURL *appSupport = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory 
                                                               inDomains:NSUserDomainMask].firstObject;
    return [[appSupport URLByAppendingPathComponent:@"ATProtoPDS"] path];
}

- (instancetype)initWithDirectory:(NSString *)directory 
                   serviceMaxSize:(NSUInteger)serviceMaxSize 
                 userDatabaseSize:(NSUInteger)userDatabaseSize {
    self = [super init];
    if (self) {
        _dataDirectory = [directory copy];
        _serviceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:directory 
                                                            serviceMaxSize:serviceMaxSize 
                                                          didCacheMaxSize:1000 
                                                        sequencerMaxSize:100];
        _userDatabasePool = [[PDSDatabasePool alloc] initWithDbDirectory:directory maxSize:userDatabaseSize];
        _repos = [NSMutableDictionary dictionary];
        _collections = [NSMutableDictionary dictionary];
        _repoQueue = dispatch_queue_create("com.atproto.pds.repository", DISPATCH_QUEUE_SERIAL);
        _controllerQueue = dispatch_queue_create("com.atproto.pds.controller", DISPATCH_QUEUE_SERIAL);
        _plcServerURL = kDefaultPlcServerURL;
        _running = NO;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *blobDir = [_dataDirectory stringByAppendingPathComponent:@"blobs"];
        if (![fm fileExistsAtPath:blobDir]) {
            [fm createDirectoryAtPath:blobDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        _log = os_log_create("com.atproto.pds", "PDSController");
        os_log_info(_log, "PDS Controller initialized with single-tenant architecture");
    }
    return self;
}

#pragma mark - Server Lifecycle

- (BOOL)startServerWithError:(NSError **)error {
    os_log_info(_log, "Starting ATProto PDS server with single-tenant architecture...");
    
    NSError *streamingError = nil;
    _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithController:self];
    
    if (![_subscribeReposHandler startOnPort:8081 error:&streamingError]) {
        os_log_error(_log, "Failed to start subscribeRepos WebSocket handler: %@", streamingError);
        if (error) *error = streamingError;
        return NO;
    }
    
    _running = YES;
    os_log_info(_log, "PDS server started successfully");
    return YES;
}

- (void)stopServer {
    os_log_info(_log, "Stopping ATProto PDS server...");
    [_subscribeReposHandler stop];
    [_userDatabasePool closeAll];
    [_serviceDatabases closeAll];
    _running = NO;
    os_log_info(_log, "PDS server stopped");
}

#pragma mark - Password Utilities

- (NSData *)hashPassword:(NSString *)password salt:(NSData *)salt {
    const char *passwordBytes = [password UTF8String];
    size_t passwordLength = strlen(passwordBytes);
    NSMutableData *derivedKey = [NSMutableData dataWithLength:32];
    
    CCKeyDerivationPBKDF(kCCPBKDF2,
                         passwordBytes,
                         passwordLength,
                         salt.bytes,
                         salt.length,
                         kCCPRFHmacAlgSHA256,
                         10000,
                         derivedKey.mutableBytes,
                         derivedKey.length);
    
    return derivedKey;
}

- (BOOL)verifyPassword:(NSString *)password hash:(NSData *)hash salt:(NSData *)salt {
    NSData *computedHash = [self hashPassword:password salt:salt];
    return [computedHash isEqualToData:hash];
}

- (NSData *)generateSalt {
    NSMutableData *salt = [NSMutableData dataWithLength:16];
    if (SecRandomCopyBytes(kSecRandomDefault, 16, salt.mutableBytes) != errSecSuccess) {
        for (NSUInteger i = 0; i < 16; i++) {
            ((uint8_t *)salt.mutableBytes)[i] = arc4random_uniform(256);
        }
    }
    return salt;
}

#pragma mark - Account Operations

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                          password:(NSString *)password
                                           handle:(NSString *)handle
                                               did:(nullable NSString *)did
                                              error:(NSError **)error {

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    BOOL debugMode = config.debugSkipPlcOperations;

    // Validate Handle
    if (![ATProtoHandleValidator validateHandle:handle error:error]) {
        return nil;
    }
    handle = [ATProtoHandleValidator normalizeHandle:handle];

    NSString *resolvedDid;
    if (did) {
        resolvedDid = did;
    } else if (debugMode) {
        resolvedDid = [self generatePlcIdentifier];
    } else {
        resolvedDid = [NSString stringWithFormat:@"did:web:%@", handle];
    }

    NSError *dbError = nil;
    PDSDatabaseAccount *existingAccount = [_serviceDatabases getAccountByDid:resolvedDid error:&dbError];

    if (existingAccount) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorAccountAlreadyExists
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account already exists"}];
        }
        return nil;
    }

    NSData *salt = [self generateSalt];
    NSData *passwordHash = [self hashPassword:password salt:salt];

    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.email = email;
    account.handle = handle;
    account.did = resolvedDid;
    account.passwordHash = passwordHash;
    account.passwordSalt = salt;
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];

    NSError *createError = nil;
    if (![_serviceDatabases createAccount:account error:&createError]) {
        if (error) {
            if ([createError.domain isEqualToString:PDSActorStoreErrorDomain] &&
                createError.code == PDSActorStoreErrorAlreadyExists) {
                *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                             code:PDSControllerErrorAccountAlreadyExists
                                         userInfo:@{NSLocalizedDescriptionKey: createError.localizedDescription ?: @"Account already exists"}];
            } else {
                *error = createError;
            }
        }
        return nil;
    }

    NSString *accessToken = [[NSUUID UUID] UUIDString];
    NSString *refreshToken = [[NSUUID UUID] UUIDString];

    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_serviceDatabases updateAccount:account error:nil];
    [_serviceDatabases storeRefreshToken:refreshToken forAccount:resolvedDid error:nil];

    if (debugMode) {
        os_log_info(_log, "[DEBUG] Created account with mock DID: %{public}@", resolvedDid);
    }

    if (debugMode) {
        os_log_info(_log, "[DEBUG] Created account with mock DID: %{public}@", resolvedDid);
    }

    MST *repo = [[MST alloc] init];
    dispatch_sync(_repoQueue, ^{
        self->_repos[resolvedDid] = repo;
    });

    CID *root = repo.rootCID;
    NSData *rootData = root ? [root bytes] : [NSData data];

    PDSDatabaseRepo *repoInfo = [[PDSDatabaseRepo alloc] init];
    repoInfo.ownerDid = resolvedDid;
    repoInfo.rootCid = rootData;
    repoInfo.createdAt = [NSDate date];
    repoInfo.updatedAt = [NSDate date];

    [_userDatabasePool transactWithDid:resolvedDid block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        [store createRepo:repoInfo error:nil];
    } error:nil];

    return @{
        @"did": resolvedDid,
        @"handle": handle,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken,
    };
}

- (NSString *)generatePlcIdentifier {
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *identifier = [NSMutableString stringWithCapacity:24];
    for (int i = 0; i < 24; i++) {
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [identifier appendFormat:@"%C", c];
    }
    return [NSString stringWithFormat:@"did:plc:%@", identifier];
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                  password:(NSString *)password
                                     error:(NSError **)error {
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByHandle:handle error:&dbError];
    
    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorAccountNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return nil;
    }
    
    if (![self verifyPassword:password hash:account.passwordHash salt:account.passwordSalt]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid password"}];
        }
        return nil;
    }
    
    NSString *accessToken = [[NSUUID UUID] UUIDString];
    NSString *refreshToken = [[NSUUID UUID] UUIDString];
    
    account.accessJwt = [accessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [refreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_serviceDatabases updateAccount:account error:nil];
    [_serviceDatabases storeRefreshToken:refreshToken forAccount:account.did error:nil];
    
    return @{
        @"did": account.did,
        @"handle": account.handle,
        @"accessJwt": accessToken,
        @"refreshJwt": refreshToken,
    };
}

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken error:(NSError **)error {
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByRefreshToken:refreshToken error:&dbError];
    
    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid refresh token"}];
        }
        return nil;
    }
    
    NSString *newAccessToken = [[NSUUID UUID] UUIDString];
    NSString *newRefreshToken = [[NSUUID UUID] UUIDString];
    
    account.accessJwt = [newAccessToken dataUsingEncoding:NSUTF8StringEncoding];
    account.refreshJwt = [newRefreshToken dataUsingEncoding:NSUTF8StringEncoding];
    [_serviceDatabases updateAccount:account error:nil];
    [_serviceDatabases storeRefreshToken:newRefreshToken forAccount:account.did error:nil];
    
    return @{
        @"accessJwt": newAccessToken,
        @"refreshJwt": newRefreshToken,
    };
}

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error {
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByDid:did error:&dbError];
    
    if (!account) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorAccountNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account not found"}];
        }
        return NO;
    }
    
    if (![self verifyPassword:password hash:account.passwordHash salt:account.passwordSalt]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorUnauthorized
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid password"}];
        }
        return NO;
    }
    
    [_serviceDatabases deleteAccount:did error:nil];
    [_userDatabasePool evictStoreForDid:did];
    
    dispatch_sync(_repoQueue, ^{
        [self->_repos removeObjectForKey:did];
    });
    
    return YES;
}

#pragma mark - Repo Operations

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    return [_userDatabasePool getRepoRoot:did error:error];
}

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error {
    PDSActorStore *store = [_userDatabasePool storeForDid:did error:error];
    if (!store) return nil;
    return [store getRepoRootForDid:did error:error];
}

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    return NO;
}

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseRecord *record = [_userDatabasePool getRecord:uri forDid:did error:error];
    
    if (!record) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:PDSControllerErrorRecordNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
        }
        return nil;
    }
    
    return @{
        @"uri": record.uri,
        @"cid": record.cid,
        @"collection": record.collection,
        @"rkey": record.rkey
    };
}

- (nullable NSArray *)listRecords:(NSString *)collection 
                           forDid:(NSString *)did
                             limit:(NSUInteger)limit
                            cursor:(nullable NSString *)cursor
                            error:(NSError **)error {
    
    PDSActorStore *store = [_userDatabasePool storeForDid:did error:error];
    if (!store) return nil;
    
    NSArray<PDSDatabaseRecord *> *records = [store listRecordsForDid:did 
                                                          collection:collection
                                                                limit:limit
                                                               offset:0
                                                                error:error];
    
    NSMutableArray *result = [NSMutableArray array];
    for (PDSDatabaseRecord *record in records) {
        [result addObject:@{
            @"uri": record.uri,
            @"cid": record.cid,
            @"collection": record.collection,
            @"rkey": record.rkey
        }];
    }
    
    return result;
}

- (BOOL)putRecord:(NSString *)collection 
              rkey:(NSString *)rkey 
             value:(NSDictionary *)value 
            forDid:(NSString *)did
             error:(NSError **)error {
    
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    NSError *cidError;
    NSString *cidString = [self generateCIDForData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] 
                                             error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return NO;
    }
    
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = uri;
    record.did = did;
    record.collection = collection;
    record.rkey = rkey;
    record.cid = cidString;
    record.createdAt = [NSDate date];
    
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [_userDatabasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store putRecord:record forDid:did error:&blockError];
    } error:nil];

    if (error && blockError) {
        *error = blockError;
    }
    
    return success;
}

- (BOOL)deleteRecord:(NSString *)collection 
                 rkey:(NSString *)rkey 
               forDid:(NSString *)did
                error:(NSError **)error {
    
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    
    __block BOOL success = NO;
    __block NSError *blockError = nil;
    [_userDatabasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store deleteRecord:uri forDid:did error:&blockError];
    } error:nil];

    if (error && blockError) {
        *error = blockError;
    }
    
    return success;
}

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [_userDatabasePool storeForDid:did error:error];
    if (!store) return nil;
    
    return [store getBlockForCID:cid forDid:did error:error];
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData 
                              forDid:(NSString *)did 
                              mimeType:(NSString *)mimeType
                                 error:(NSError **)error {
    
    NSError *cidError;
    NSString *cidString = [self generateCIDForData:blobData error:&cidError];
    if (!cidString) {
        if (error) *error = cidError;
        return nil;
    }
    
    NSData *cidData = [self cidDataFromString:cidString];
    
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    block.cid = cidData;
    block.repoDid = did;
    block.blockData = blobData;
    block.contentType = mimeType;
    block.size = blobData.length;
    block.createdAt = [NSDate date];
    
    __block BOOL success = NO;
    [_userDatabasePool transactWithDid:did block:^(id<PDSActorStoreTransactor> transactor) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        success = [store putBlock:block forDid:did error:nil];
    } error:nil];
    
    if (!success) {
        if (error) {
            *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to store blob"}];
        }
        return nil;
    }
    
    return @{
        @"blob": @{
            @"$type": @"blob",
            @"ref": @{@"$link": cidString},
            @"mimeType": mimeType,
            @"size": @(blobData.length)
        }
    };
}

#pragma mark - Admin Operations

- (nullable NSArray *)getAllAccountsWithError:(NSError **)error {
    return [_userDatabasePool getAllAccountsWithError:error];
}

- (BOOL)takeDownAccount:(NSString *)did reason:(NSString *)reason error:(NSError **)error {
    return NO;
}

- (BOOL)reinstateAccount:(NSString *)did error:(NSError **)error {
    return NO;
}

#pragma mark - Moderation Operations

- (NSDictionary *)createModerationReport:(NSDictionary *)params error:(NSError **)error {
    // TODO: Implement moderation report creation
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)updateSubjectStatus:(NSDictionary *)subject
                              takedown:(NSDictionary *)takedown
                           deactivated:(NSDictionary *)deactivated
                                error:(NSError **)error {
    // TODO: Implement subject status updates
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)getSubjectStatus:(NSString *)did uri:(NSString *)uri blob:(NSString *)blob error:(NSError **)error {
    // TODO: Implement subject status retrieval
    return @{@"status": @"not_implemented"};
}

#pragma mark - Labeling Operations

- (NSArray *)queryLabels:(NSDictionary *)params error:(NSError **)error {
    // TODO: Implement label querying
    return @[@{@"status": @"not_implemented"}];
}

#pragma mark - Health & Metrics

- (NSDictionary<NSString *, id> *)getHealthCheck {
    return [[PDSHealthCheck sharedInstance] performHealthCheck];
}

- (NSDictionary<NSString *, id> *)getMetrics {
    NSMutableDictionary *metrics = [NSMutableDictionary dictionary];
    metrics[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    metrics[@"user_databases"] = [_userDatabasePool collectMetrics];
    metrics[@"service_databases"] = @{
        @"service_pool": [[_serviceDatabases servicePool] collectMetrics],
        @"did_cache_pool": [[_serviceDatabases didCachePool] collectMetrics],
        @"sequencer_pool": [[_serviceDatabases sequencerPool] collectMetrics]
    };
    return metrics;
}

#pragma mark - Helpers

- (nullable NSString *)generateCIDForData:(NSData *)data error:(NSError **)error {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    
    NSMutableData *multihash = [NSMutableData data];
    [multihash appendBytes:(uint8_t[]){0x12, 0x20} length:2];
    [multihash appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];
    
    NSMutableData *cidData = [NSMutableData data];
    [cidData appendBytes:(uint8_t[]){0x01, 0x71} length:2];
    [cidData appendData:multihash];
    
    NSString *base32 = [self base32Encode:cidData];
    return [NSString stringWithFormat:@"b%@", [base32 lowercaseString]];
}

- (NSData *)cidDataFromString:(NSString *)cidString {
    if (![cidString hasPrefix:@"b"]) {
        return nil;
    }
    NSString *base32 = [cidString substringFromIndex:1];
    return [self base32Decode:base32];
}

- (NSString *)base32Encode:(NSData *)data {
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString string];
    NSUInteger length = data.length;
    NSUInteger i = 0;
    
    while (i < length) {
        uint8_t byte = ((uint8_t *)data.bytes)[i++];
        [result appendFormat:@"%c", alphabet[byte >> 3]];
        uint8_t nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((byte & 0x07) << 2) | (nextByte >> 6)]];
        if (i >= length + 1) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 1) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((nextByte & 0x0F) << 1) | (nextByte >> 7)]];
        if (i >= length) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 2) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[nextByte & 0x1F]];
    }
    
    return result;
}

- (NSData *)base32Decode:(NSString *)base32 {
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableData *result = [NSMutableData data];
    NSUInteger length = base32.length;
    
    NSMutableData *buffer = [NSMutableData dataWithLength:8];
    int bufferBits = 0;
    int bufferValue = 0;
    
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [base32 characterAtIndex:i];
        if (c == ' ' || c == '\n' || c == '\r' || c == '\t') continue;
        
        int val = -1;
        for (int j = 0; j < 32; j++) {
            if (alphabet[j] == c) {
                val = j;
                break;
            }
        }
        
        if (val < 0) continue;
        
        bufferValue = (bufferValue << 5) | val;
        bufferBits += 5;
        
        while (bufferBits >= 8) {
            bufferBits -= 8;
            uint8_t byte = (bufferValue >> bufferBits) & 0xFF;
            [result appendBytes:&byte length:1];
        }
    }
    
    return result;
}

#pragma mark - Legacy Account Operations (for backward compatibility)

- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                              handle:(NSString *)handle
                                                  did:(NSString *)did
                                                 error:(NSError **)error {
    return [self createAccountForEmail:identifier
                              password:password
                               handle:handle ?: identifier
                                   did:did ?: [NSString stringWithFormat:@"did:web:%@", identifier]
                                  error:error];
}

- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                    error:(NSError **)error {
    return [self refreshAccessToken:refreshToken error:error];
}

#pragma mark - Legacy Repo Operations (for backward compatibility)

- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error {
    NSData *root = [self getRepoRoot:repo error:error];
    if (!root) return nil;
    
    return @{
        @"did": repo,
        @"root": [root base64EncodedStringWithOptions:0]
    };
}

- (nullable NSData *)getRepoDataForDid:(NSString *)did error:(NSError **)error {
    return [self getRepoContents:did since:nil error:error];
}

- (nullable NSString *)getRepoHeadForDid:(NSString *)did error:(NSError **)error {
    NSData *root = [self getRepoRoot:did error:error];
    if (!root) return nil;
    return [self base32Encode:root];
}

#pragma mark - Legacy Record Operations (for backward compatibility)

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                    collection:(NSString *)collection
                                       record:(NSDictionary *)record
                                        error:(NSError **)error {
    NSString *rkey = [TID tid].stringValue;
    BOOL success = [self putRecord:collection
                              rkey:rkey
                             value:record
                            forDid:did
                             error:error];
    if (!success) return nil;

    NSData *recordData = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    CID *cid = [CID sha256:recordData];
    
    return @{
        @"uri": [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey],
        @"cid": cid.stringValue ?: @"bafkreiplaceholder"
    };
}

- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                 collection:(NSString *)collection
                                      rkey:(NSString *)rkey
                                     error:(NSError **)error {
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    return [self getRecord:uri forDid:did error:error];
}

- (nullable NSArray *)listRecordsForDid:(NSString *)did
                              collection:(NSString *)collection
                                   limit:(NSUInteger)limit
                                  cursor:(nullable NSString *)cursor
                                   error:(NSError **)error {
    return [self listRecords:collection forDid:did limit:limit cursor:cursor error:error];
}

- (BOOL)deleteRecordForDid:(NSString *)did
                 collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error {
    return [self deleteRecord:collection rkey:rkey forDid:did error:error];
}

- (BOOL)putRecordForDid:(NSString *)did
              collection:(NSString *)collection
                   rkey:(NSString *)rkey
                 record:(NSDictionary *)record
                  error:(NSError **)error {
    return [self putRecord:collection rkey:rkey value:record forDid:did error:error];
}

#pragma mark - Legacy Blob Operations (for backward compatibility)

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData 
                             mimeType:(NSString *)mimeType 
                                  did:(NSString *)did
                                error:(NSError **)error {
    return [self uploadBlob:blobData forDid:did mimeType:mimeType error:error];
}

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cid 
                                      did:(NSString *)did
                                    error:(NSError **)error {
    NSData *cidData = [self cidDataFromString:cid];
    if (!cidData) {
        if (error) *error = [NSError errorWithDomain:PDSControllerErrorDomain
                                                code:PDSControllerErrorBlobNotFound
                                            userInfo:@{NSLocalizedDescriptionKey: @"Invalid CID format"}];
        return nil;
    }
    NSData *blob = [self getBlob:cidData forDid:did error:error];
    if (!blob) return nil;
    return @{@"blob": @{@"mimeType": @"application/octet-stream", @"size": @(blob.length)}};
}

- (nullable NSArray *)listBlobsForDID:(NSString *)did 
                                limit:(NSUInteger)limit 
                               cursor:(nullable NSString *)cursor
                                error:(NSError **)error {
    return @[];
}

#pragma mark - Write Operations (for backward compatibility)

- (nullable NSDictionary *)applyWrites:(NSArray *)writes 
                                 repo:(NSString *)repo 
                             validate:(BOOL)validate 
                           swapCommit:(nullable NSString *)swapCommit
                                error:(NSError **)error {
    for (NSDictionary *write in writes) {
        NSString *action = write[@"action"];
        NSDictionary *record = write[@"record"];
        NSString *collection = write[@"collection"];
        NSString *rkey = write[@"rkey"];
        
        if ([action isEqualToString:@"create"] || [action isEqualToString:@"update"]) {
            if (![self putRecord:collection rkey:rkey value:record forDid:repo error:error]) {
                return nil;
            }
        } else if ([action isEqualToString:@"delete"]) {
            if (![self deleteRecord:collection rkey:rkey forDid:repo error:error]) {
                return nil;
            }
        }
    }
    return @{@"commit": @{@"root": @"newroot"}};
}

@end
