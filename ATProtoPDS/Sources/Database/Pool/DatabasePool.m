#import "DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import <sqlite3.h>

NSString * const PDSDatabasePoolErrorDomain = @"com.atproto.pds.databasepool";

@interface PDSDatabasePool ()

@property (nonatomic, copy, readwrite) NSString *dbDirectory;
@property (nonatomic, assign, readwrite) NSUInteger maxSize;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSActorStore *> *stores;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastAccessTime;
@property (nonatomic, strong) dispatch_queue_t poolQueue;
@property (nonatomic, strong) dispatch_queue_t evictionQueue;
@property (nonatomic, strong) NSTimer *evictionTimer;
@property (nonatomic, assign, readwrite) NSUInteger openFileHandleCount;

@end

@implementation PDSDatabasePool

- (instancetype)initWithDbDirectory:(NSString *)dbDirectory maxSize:(NSUInteger)maxSize {
    self = [super init];
    if (self) {
        _dbDirectory = [dbDirectory copy];
        _maxSize = maxSize;
        _stores = [NSMutableDictionary dictionary];
        _lastAccessTime = [NSMutableDictionary dictionary];
        _poolQueue = dispatch_queue_create("com.atproto.pds.databasepool", DISPATCH_QUEUE_SERIAL);
        _evictionQueue = dispatch_queue_create("com.atproto.pds.databasepool.eviction", DISPATCH_QUEUE_SERIAL);
        _openFileHandleCount = 0;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dbDirectory]) {
            NSError *error = nil;
            [fm createDirectoryAtPath:dbDirectory withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSLog(@"[PDSDatabasePool] Failed to create db directory: %@", error);
            }
        }
        
        _evictionTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                          target:self
                                                        selector:@selector(evictionTimerFired:)
                                                        userInfo:nil
                                                         repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [self.evictionTimer invalidate];
    [self closeAll];
}

#pragma mark - Store Management

- (NSString *)dbPathForDid:(NSString *)did {
    NSString *didPrefix = [did substringToIndex:MIN(2, did.length)];
    NSString *prefixDir = [self.dbDirectory stringByAppendingPathComponent:didPrefix];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:prefixDir]) {
        [fm createDirectoryAtPath:prefixDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return [prefixDir stringByAppendingPathComponent:did];
}

- (nullable PDSActorStore *)storeForDid:(NSString *)did error:(NSError **)error {
    __block PDSActorStore *store = nil;
    
    dispatch_sync(self.poolQueue, ^{
        store = self.stores[did];
        
        if (store) {
            self.lastAccessTime[did] = [NSDate date];
            return;
        }
        
        if (self.stores.count >= self.maxSize) {
            [self evictLRUStore];
        }
        
        NSString *dbPath = [self dbPathForDid:did];
        NSError *openError = nil;
        store = [PDSActorStore storeWithDid:did dbPath:dbPath error:&openError];
        
        if (store) {
            self.stores[did] = store;
            self.lastAccessTime[did] = [NSDate date];
            self.openFileHandleCount++;
        } else {
            if (error) {
                *error = openError;
            }
        }
    });
    
    return store;
}

- (void)evictionTimerFired:(NSTimer *)timer {
    dispatch_async(self.evictionQueue, ^{
        [self evictUnusedStores];
    });
}

- (void)evictUnusedStores {
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-300];
    
    dispatch_sync(self.poolQueue, ^{
        NSMutableArray<NSString *> *toEvict = [NSMutableArray array];
        
        for (NSString *did in self.lastAccessTime) {
            NSDate *lastAccess = self.lastAccessTime[did];
            if ([lastAccess compare:cutoff] == NSOrderedAscending) {
                [toEvict addObject:did];
            }
        }
        
        for (NSString *did in toEvict) {
            [self evictStoreForDidInternal:did];
        }
    });
}

- (void)evictLRUStore {
    if (self.lastAccessTime.count == 0) {
        return;
    }
    
    NSString *lruDid = nil;
    NSDate *lruTime = [NSDate distantFuture];
    
    for (NSString *did in self.lastAccessTime) {
        NSDate *accessTime = self.lastAccessTime[did];
        if ([accessTime compare:lruTime] == NSOrderedAscending) {
            lruTime = accessTime;
            lruDid = did;
        }
    }
    
    if (lruDid) {
        [self evictStoreForDidInternal:lruDid];
    }
}

- (void)evictStoreForDid:(NSString *)did {
    dispatch_sync(self.poolQueue, ^{
        [self evictStoreForDidInternal:did];
    });
}

- (void)evictStoreForDidInternal:(NSString *)did {
    PDSActorStore *store = self.stores[did];
    if (store) {
        [store close];
        [self.stores removeObjectForKey:did];
        [self.lastAccessTime removeObjectForKey:did];
        self.openFileHandleCount--;
    }
}

- (void)closeAll {
    dispatch_sync(self.poolQueue, ^{
        for (NSString *did in self.stores) {
            PDSActorStore *store = self.stores[did];
            [store close];
        }
        [self.stores removeAllObjects];
        [self.lastAccessTime removeAllObjects];
        self.openFileHandleCount = 0;
    });
}

#pragma mark - Transaction Support

- (void)transactWithDid:(NSString *)did 
                  block:(void (^)(id<PDSActorStoreTransactor> transactor))block 
                  error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return;
    }
    
    [store transactWithBlock:block error:error];
}

- (BOOL)readWithDid:(NSString *)did 
              block:(id<PDSActorStoreReader> (^)(void))block 
              error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return NO;
    }
    
    return [store readWithBlock:block error:error];
}

#pragma mark - Convenience Methods

- (nullable PDSDatabaseAccount *)getAccount:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return nil;
    }
    return [store getAccountForDid:did error:error];
}

- (nullable PDSDatabaseRepo *)getRepo:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return nil;
    }
    return [store getRepoForDid:did error:error];
}

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return nil;
    }
    return [store getRepoRootForDid:did error:error];
}

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return nil;
    }
    return [store getRecord:uri forDid:did error:error];
}

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *dirError = nil;
    NSArray<NSString *> *prefixDirs = [fm contentsOfDirectoryAtPath:self.dbDirectory error:&dirError];
    
    if (dirError) {
        if (error) *error = dirError;
        return @[];
    }
    
    for (NSString *prefixDir in prefixDirs) {
        NSString *fullPath = [self.dbDirectory stringByAppendingPathComponent:prefixDir];
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:fullPath error:nil];
        
        for (NSString *file in files) {
            if ([file hasPrefix:@"did:"]) {
                NSString *did = file;
                PDSDatabaseAccount *account = [self getAccount:did error:nil];
                if (account) {
                    [accounts addObject:account];
                }
            }
        }
    }
    
    return accounts;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    NSMutableArray<PDSDatabaseRepo *> *repos = [NSMutableArray array];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *prefixDirs = [fm contentsOfDirectoryAtPath:self.dbDirectory error:nil];
    
    for (NSString *prefixDir in prefixDirs) {
        NSString *fullPath = [self.dbDirectory stringByAppendingPathComponent:prefixDir];
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:fullPath error:nil];
        
        for (NSString *file in files) {
            if ([file hasPrefix:@"did:"]) {
                NSString *did = file;
                PDSDatabaseRepo *repo = [self getRepo:did error:nil];
                if (repo) {
                    [repos addObject:repo];
                }
            }
        }
    }
    
    return repos;
}

#pragma mark - Metrics

- (NSDictionary<NSString *, id> *)collectMetrics {
    __block NSDictionary *metrics = nil;
    
    dispatch_sync(self.poolQueue, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        m[@"max_size"] = @(self.maxSize);
        m[@"current_size"] = @(self.stores.count);
        m[@"open_file_handles"] = @(self.openFileHandleCount);
        
        NSMutableDictionary *stores = [NSMutableDictionary dictionary];
        for (NSString *did in self.stores) {
            PDSActorStore *store = self.stores[did];
            NSDate *lastAccess = self.lastAccessTime[did];
            stores[did] = @{
                @"is_open": @(store.isOpen),
                @"db_path": store.dbPath ?: @"",
                @"last_access": lastAccess ?: [NSDate distantPast]
            };
        }
        m[@"stores"] = stores;
        
        metrics = [m copy];
    });
    
    return metrics;
}

- (NSUInteger)currentSize {
    __block NSUInteger size = 0;
    dispatch_sync(self.poolQueue, ^{
        size = self.stores.count;
    });
    return size;
}

@end
