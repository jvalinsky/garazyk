#import "PDSSyncService.h"
#import "PDSRepositoryService.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import <os/log.h>

@interface PDSSyncService ()

#if defined(GNUSTEP)
@property (nonatomic, assign) os_log_t log;
#else
@property (nonatomic, strong) os_log_t log;
#endif

@end

@implementation PDSSyncService

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool 
                   repositoryService:(PDSRepositoryService *)repositoryService {
    self = [super init];
    if (self) {
        _databasePool = databasePool;
        _repositoryService = repositoryService;
        _log = os_log_create("com.atproto.pds", "sync");
        PDS_LOG_INFO_C(PDSLogComponentSync, @"PDSSyncService initialized");
    }
    return self;
}

#pragma mark - Sync Operations

- (nullable NSData *)getRepo:(NSString *)did since:(nullable NSString *)since error:(NSError **)error {
    PDS_LOG_SYNC_DEBUG(@"Sync: getRepo for DID: %@ since: %@", did, since);
    
    // Implementation will leverage PDSRepositoryService to generate CAR data
    NSData *sinceCid = nil;
    if (since) {
        // TODO: Convert string CID to NSData
    }
    
    return [self.repositoryService getRepoContents:did since:sinceCid error:error];
}

- (nullable NSArray<NSData *> *)getBlocks:(NSString *)did cids:(NSArray<NSString *> *)cids error:(NSError **)error {
    PDS_LOG_SYNC_DEBUG(@"Sync: getBlocks for DID: %@, count: %lu", did, (unsigned long)cids.count);
    
    // Implementation will iterate CIDs and fetch blocks from the repository database
    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:cids.count];
    // TODO: Implement block retrieval loop
    
    return [blocks copy];
}

- (nullable NSDictionary *)getLatestCommit:(NSString *)did error:(NSError **)error {
    PDS_LOG_SYNC_DEBUG(@"Sync: getLatestCommit for DID: %@", did);
    
    NSData *rootData = [self.repositoryService getRepoRoot:did error:error];
    if (!rootData) return nil;
    
    // TODO: Extract CID and Rev from commit data
    return @{
        @"cid": @"bafkreiplaceholder",
        @"rev": @"3jplaceholder"
    };
}

- (nullable NSArray<NSDictionary *> *)listReposWithLimit:(NSUInteger)limit 
                                                 cursor:(nullable NSString *)cursor 
                                                  error:(NSError **)error {
    PDS_LOG_SYNC_DEBUG(@"Sync: listRepos limit: %lu cursor: %@", (unsigned long)limit, cursor);
    
    // Leverage serviceDatabases to query the accounts table
    return [self.serviceDatabases getAllAccountsWithError:error];
}

@end
