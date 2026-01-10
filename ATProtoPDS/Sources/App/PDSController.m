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
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "App/PDSConfiguration.h"
#import "Services/PDSAccountService.h"
#import "Services/PDSRecordService.h"
#import "Services/PDSBlobService.h"
#import "Services/PDSRepositoryService.h"
#import <os/log.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>

NSString *const PDSControllerErrorDomain = @"com.atproto.pds.controller";
NSString *const kDefaultPlcServerURL = @"https://plc.directory";

@implementation PDSController {
    os_log_t _log;
    PDSServiceDatabases *_serviceDatabases;
    PDSDatabasePool *_userDatabasePool;
    PDSAccountService *_accountService;
    PDSRecordService *_recordService;
    PDSBlobService *_blobService;
    PDSRepositoryService *_repositoryService;
    NSMutableDictionary<NSString *, MST *> *_repos;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_collections;
    dispatch_queue_t _repoQueue;
    dispatch_queue_t _controllerQueue;
    SubscribeReposHandler *_subscribeReposHandler;
    HttpServer *_httpServer;
    XrpcDispatcher *_xrpcDispatcher;
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
        _accountService = [[PDSAccountService alloc] initWithDatabasePool:_userDatabasePool];
        _accountService.serviceDatabases = _serviceDatabases;
        _recordService = [[PDSRecordService alloc] initWithDatabasePool:_userDatabasePool];
        _blobService = [[PDSBlobService alloc] initWithDatabasePool:_userDatabasePool];
        _repositoryService = [[PDSRepositoryService alloc] initWithDatabasePool:_userDatabasePool];
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
    
    // Start HTTP server with XRPC handlers
    _httpServer = [HttpServer serverWithPort:2583];
    _xrpcDispatcher = [XrpcDispatcher sharedDispatcher];
    
    [XrpcMethodRegistry registerMethodsWithDispatcher:_xrpcDispatcher controller:self];
    
    [_httpServer addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
        [self->_xrpcDispatcher handleRequest:request response:response];
    }];
    
    [_httpServer addHandlerForPath:@"/xrpc/" handler:^(HttpRequest *request, HttpResponse *response) {
        [self->_xrpcDispatcher handleRequest:request response:response];
    }];
    
    NSError *httpError = nil;
    if (![_httpServer startWithError:&httpError]) {
        os_log_error(_log, "Failed to start HTTP server: %@", httpError);
        if (error) *error = httpError;
        return NO;
    }
    os_log_info(_log, "HTTP server started on port %lu", (unsigned long)_httpServer.port);
    
    // Start WebSocket handler for subscribeRepos
    NSError *streamingError = nil;
    _subscribeReposHandler = [[SubscribeReposHandler alloc] initWithController:self];
    
    if (![_subscribeReposHandler startOnPort:8081 error:&streamingError]) {
        os_log_error(_log, "Failed to start subscribeRepos WebSocket handler: %@", streamingError);
        if (error) *error = streamingError;
        return NO;
    }
    
    _running = YES;
    os_log_info(_log, "PDS server started successfully - XRPC at port 2583, WebSocket at port 8081");
    return YES;
}

- (void)stopServer {
    os_log_info(_log, "Stopping ATProto PDS server...");
    [_httpServer stop];
    [_subscribeReposHandler stop];
    [_userDatabasePool closeAll];
    [_serviceDatabases closeAll];
    _running = NO;
    os_log_info(_log, "PDS server stopped");
}

#pragma mark - Account Operations

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                           password:(NSString *)password
                                            handle:(NSString *)handle
                                                did:(nullable NSString *)did
                                               error:(NSError **)error {
    return [_accountService createAccountForEmail:email
                                         password:password
                                          handle:handle
                                              did:did
                                             error:error];
}

- (nullable NSDictionary *)loginWithHandle:(NSString *)handle
                                   password:(NSString *)password
                                      error:(NSError **)error {
    return [_accountService loginWithHandle:handle
                                  password:password
                                     error:error];
}

- (nullable NSDictionary *)refreshAccessToken:(NSString *)refreshToken error:(NSError **)error {
    return [_accountService refreshAccessToken:refreshToken error:error];
}

- (BOOL)deleteAccount:(NSString *)did password:(NSString *)password error:(NSError **)error {
    return [_accountService deleteAccount:did password:password error:error];
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

#pragma mark - Repo Operations

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    return [_repositoryService getRepoRoot:did error:error];
}

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error {
    return [_repositoryService getRepoContents:did since:sinceCid error:error];
}

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error {
    return [_repositoryService updateRepo:did commit:commitData error:error];
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

#pragma mark - Record Operations

- (nullable NSDictionary *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    return [_recordService getRecord:uri forDid:did error:error];
}

- (nullable NSArray *)listRecords:(NSString *)collection
                           forDid:(NSString *)did
                             limit:(NSUInteger)limit
                            cursor:(nullable NSString *)cursor
                            error:(NSError **)error {
    return [_recordService listRecords:collection forDid:did limit:limit cursor:cursor error:error];
}

- (BOOL)putRecord:(NSString *)collection
              rkey:(NSString *)rkey
             value:(NSDictionary *)value
            forDid:(NSString *)did
             error:(NSError **)error {
    return [_recordService putRecord:collection rkey:rkey value:value forDid:did error:error];
}

- (BOOL)deleteRecord:(NSString *)collection
                  rkey:(NSString *)rkey
                forDid:(NSString *)did
                 error:(NSError **)error {
    return [_recordService deleteRecord:collection rkey:rkey forDid:did error:error];
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

#pragma mark - Blob Operations

- (nullable NSData *)getBlob:(NSData *)cid forDid:(NSString *)did error:(NSError **)error {
    return [_blobService getBlob:cid forDid:did error:error];
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                               forDid:(NSString *)did
                              mimeType:(NSString *)mimeType
                                 error:(NSError **)error {
    return [_blobService uploadBlob:blobData forDid:did mimeType:mimeType error:error];
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
    return [_blobService getBlobWithCID:cid did:did error:error];
}

- (nullable NSArray *)listBlobsForDID:(NSString *)did
                               limit:(NSUInteger)limit
                              cursor:(nullable NSString *)cursor
                               error:(NSError **)error {
    return [_blobService listBlobsForDID:did limit:limit cursor:cursor error:error];
}

- (BOOL)deleteBlobWithCID:(NSString *)cid did:(NSString *)did error:(NSError **)error {
    return [_blobService deleteBlobWithCID:cid did:did error:error];
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

#pragma mark - Health & Metrics

- (NSDictionary<NSString *, id> *)getHealthCheck {
    return [[PDSHealthCheck sharedInstance] performHealthCheck];
}

- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error {
    return [_serviceDatabases serviceDatabaseWithError:error];
}

- (NSDictionary<NSString *, id> *)getMetrics {
    return @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"user_databases": [_userDatabasePool collectMetrics] ?: @{},
        @"service_databases": @{}
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

- (NSDictionary *)moderateAccount:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)moderateRecord:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

#pragma mark - Labeling Operations

- (NSDictionary *)createLabel:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

- (NSDictionary *)getLabels:(NSDictionary *)params error:(NSError **)error {
    return @{@"status": @"not_implemented"};
}

@end
