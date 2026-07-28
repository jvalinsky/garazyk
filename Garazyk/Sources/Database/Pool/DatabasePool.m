// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "DatabasePool.h"
#import "Compat/PDSTypes.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Core/ATProtoValidator.h"
#import "Debug/GZLogger.h"
#import <sqlite3.h>

NSString * const PDSDatabasePoolErrorDomain = @"com.atproto.pds.databasepool";

// Queue-specific key for re-entrancy detection in dealloc
static void * const kDatabasePoolQueueKey = (void *)&kDatabasePoolQueueKey;

@interface PDSDatabasePool ()
- (instancetype)initWithDbDirectory:(NSString *)dbDirectory
                            maxSize:(NSUInteger)maxSize
                   evictionInterval:(NSTimeInterval)evictionInterval
                      idleThreshold:(NSTimeInterval)idleThreshold;
- (nullable PDSActorStore *)storeForDid:(NSString *)did
                            retainForUse:(BOOL)retainForUse
                                   error:(NSError **)error;
- (void)releaseStoreUseForDid:(NSString *)did store:(PDSActorStore *)store;
@property (nonatomic, copy, readwrite) NSString *dbDirectory;
@property (nonatomic, assign, readwrite) NSUInteger maxSize;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSActorStore *> *stores;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastAccessTime;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *activeUseCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *pendingOpenGroups;
@property (nonatomic, strong) NSMutableSet<NSString *> *knownDids;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t poolQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t evictionQueue;
@property (nonatomic, PDS_GCD_STRONG) dispatch_source_t evictionTimer;
@property (nonatomic, assign) NSTimeInterval evictionIdleThreshold;
@property (nonatomic, assign, readwrite) NSUInteger openFileHandleCount;

@end

@implementation PDSDatabasePool

- (instancetype)initWithDbDirectory:(NSString *)dbDirectory maxSize:(NSUInteger)maxSize {
    return [self initWithDbDirectory:dbDirectory
                             maxSize:maxSize
                    evictionInterval:60.0
                       idleThreshold:300.0];
}

- (instancetype)initWithDbDirectory:(NSString *)dbDirectory
                            maxSize:(NSUInteger)maxSize
                   evictionInterval:(NSTimeInterval)evictionInterval
                      idleThreshold:(NSTimeInterval)idleThreshold {
    self = [super init];
    if (self) {
        _dbDirectory = [dbDirectory copy];
        _maxSize = maxSize;
        _stores = [NSMutableDictionary dictionary];
        _lastAccessTime = [NSMutableDictionary dictionary];
        _activeUseCounts = [NSMutableDictionary dictionary];
        _pendingOpenGroups = [NSMutableDictionary dictionary];
        _poolQueue = dispatch_queue_create("com.atproto.pds.databasepool", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_poolQueue, kDatabasePoolQueueKey, kDatabasePoolQueueKey, NULL);
        _evictionQueue = dispatch_queue_create("com.atproto.pds.databasepool.eviction", DISPATCH_QUEUE_SERIAL);
        _openFileHandleCount = 0;
        _evictionIdleThreshold = idleThreshold;
        _knownDids = [NSMutableSet set];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dbDirectory]) {
            NSError *error = nil;
            [fm createDirectoryAtPath:dbDirectory withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                GZ_LOG_DB_ERROR(@"Failed to create database directory: %@ (error: %@)", dbDirectory, error);
            }
        }
        
        _evictionTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _evictionQueue);
        if (_evictionTimer) {
            dispatch_source_set_timer(_evictionTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(evictionInterval * NSEC_PER_SEC)),
                                      (uint64_t)(evictionInterval * NSEC_PER_SEC),
                                      0);
            __weak typeof(self) weakSelf = self;
            dispatch_source_set_event_handler(_evictionTimer, ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf evictUnusedStores];
            });
            dispatch_resume(_evictionTimer);
        }
    }
    return self;
}

- (void)dealloc {
    if (dispatch_get_specific(kDatabasePoolQueueKey)) {
        if (self.evictionTimer) {
            dispatch_source_cancel(self.evictionTimer);
            self.evictionTimer = nil;
        }
        // Already on pool queue — close stores directly to avoid deadlock
        [self closeAllNoSync];
    } else {
        [self closeAll];
    }
}

#pragma mark - Store Management

- (NSString *)dbPathForDid:(NSString *)did {
    if ([did isEqualToString:@"__service__"]) {
        return [self.dbDirectory stringByAppendingPathComponent:@"service.db"];
    }
    NSError *didError = nil;
    if (![ATProtoValidator validateDID:did error:&didError]) {
        GZ_LOG_DB_ERROR(@"Refusing to derive actor store path for invalid DID %@: %@", did, didError.localizedDescription);
        return nil;
    }

    // Shard by DID method and 2-char prefix of the method-specific identifier:
    // did:plc:z72i7h... → {dbDir}/plc/z7/did:plc:z72i7h...
    NSString *method = nil;
    NSString *identifier = nil;
    NSRange firstColon = [did rangeOfString:@":"];
    if (firstColon.location != NSNotFound) {
        NSRange rest = NSMakeRange(firstColon.location + 1, did.length - firstColon.location - 1);
        NSRange secondColon = [did rangeOfString:@":" options:0 range:rest];
        if (secondColon.location != NSNotFound) {
            method = [did substringWithRange:NSMakeRange(firstColon.location + 1,
                                                         secondColon.location - firstColon.location - 1)];
            identifier = [did substringFromIndex:secondColon.location + 1];
        }
    }

    NSString *prefixDir;
    if (method.length > 0 && identifier.length > 0) {
        NSString *prefix = [identifier substringToIndex:MIN(2, identifier.length)];
        NSString *methodDir = [self.dbDirectory stringByAppendingPathComponent:method];
        prefixDir = [methodDir stringByAppendingPathComponent:prefix];
    } else {
        NSString *prefix = [did substringToIndex:MIN(2, did.length)];
        prefixDir = [self.dbDirectory stringByAppendingPathComponent:prefix];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:prefixDir]) {
        [fm createDirectoryAtPath:prefixDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    return [prefixDir stringByAppendingPathComponent:did];
}

- (nullable PDSActorStore *)storeForDid:(NSString *)did error:(NSError **)error {
    return [self storeForDid:did retainForUse:NO error:error];
}

- (nullable PDSActorStore *)storeForDid:(NSString *)did
                            retainForUse:(BOOL)retainForUse
                                   error:(NSError **)error {
    if (did.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSDatabasePoolErrorDomain
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID for actor store path"}];
        }
        return nil;
    }

    __block PDSActorStore *store = nil;
    __block NSError *blockError = nil;
    __block dispatch_group_t openGroup = nil;
    __block BOOL shouldOpen = NO;

    dispatch_sync(self.poolQueue, ^{
        store = self.stores[did];

        if (store) {
            self.lastAccessTime[did] = [NSDate date];
            if (retainForUse) {
                self.activeUseCounts[did] = @([self.activeUseCounts[did] unsignedIntegerValue] + 1);
            }
            return;
        }

        id existingGroup = self.pendingOpenGroups[did];
        if (existingGroup) {
#if PDS_GCD_OBJC_SUPPORT
            openGroup = PDS_GCD_CAST(dispatch_group_t, existingGroup);
#else
            openGroup = (dispatch_group_t)[(NSValue *)existingGroup pointerValue];
            dispatch_retain(openGroup);
#endif
            return;
        }

        openGroup = dispatch_group_create();
        dispatch_group_enter(openGroup);
#if PDS_GCD_OBJC_SUPPORT
        self.pendingOpenGroups[did] = PDS_GCD_BRIDGE_ID(openGroup);
#else
        // libdispatch objects are C pointers on Linux. Wrapping the pointer
        // prevents Foundation collections from sending Objective-C retain
        // messages to a dispatch object.
        self.pendingOpenGroups[did] = [NSValue valueWithPointer:openGroup];
#endif
        shouldOpen = YES;
    });

    if (store) return store;
    if (!shouldOpen) {
        dispatch_group_wait(openGroup, DISPATCH_TIME_FOREVER);
#if !PDS_GCD_OBJC_SUPPORT
        dispatch_release(openGroup);
#endif
        return [self storeForDid:did retainForUse:retainForUse error:error];
    }

    NSString *dbPath = [self dbPathForDid:did];
    if (dbPath.length == 0) {
        blockError = [NSError errorWithDomain:PDSDatabasePoolErrorDomain
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID for actor store path"}];
    } else {
        GZ_LOG_DB_DEBUG(@"Opening store at path: %@ (exists: %d)", dbPath,
                         [[NSFileManager defaultManager] fileExistsAtPath:dbPath]);
        store = [PDSActorStore storeWithDid:did dbPath:dbPath error:&blockError];
    }

    if (store) store.masterSecret = self.masterSecret;
    dispatch_sync(self.poolQueue, ^{
        [self.pendingOpenGroups removeObjectForKey:did];
        if (store) {
            if (self.stores.count >= self.maxSize) {
                [self evictLRUStore];
            }
            self.stores[did] = store;
            self.lastAccessTime[did] = [NSDate date];
            self.openFileHandleCount++;
            [self.knownDids addObject:did];
            if (retainForUse) {
                self.activeUseCounts[did] = @1;
            }
        } else {
            GZ_LOG_DB_ERROR(@"Failed to open store for %@: %@", did, blockError);
        }
        dispatch_group_leave(openGroup);
    });
#if !PDS_GCD_OBJC_SUPPORT
    dispatch_release(openGroup);
#endif

    if (error && blockError) {
        *error = blockError;
    }

    return store;
}

- (void)releaseStoreUseForDid:(NSString *)did store:(PDSActorStore *)store {
    dispatch_sync(self.poolQueue, ^{
        if (self.stores[did] != store) return;
        NSUInteger active = [self.activeUseCounts[did] unsignedIntegerValue];
        if (active <= 1) {
            [self.activeUseCounts removeObjectForKey:did];
        } else {
            self.activeUseCounts[did] = @(active - 1);
        }
    });
}

- (void)evictUnusedStores {
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-self.evictionIdleThreshold];
    
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
        if ([self.activeUseCounts[did] unsignedIntegerValue] == 0 &&
            [accessTime compare:lruTime] == NSOrderedAscending) {
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
    if (!store || [self.activeUseCounts[did] unsignedIntegerValue] > 0) return;

    [self.stores removeObjectForKey:did];
    [self.lastAccessTime removeObjectForKey:did];
    [self.knownDids removeObject:did];
    [self.activeUseCounts removeObjectForKey:did];
    if (self.openFileHandleCount > 0) self.openFileHandleCount--;
    dispatch_async(self.evictionQueue, ^{
        [store close];
    });
}

- (void)closeAll {
    if (self.evictionTimer) {
        dispatch_source_cancel(self.evictionTimer);
        self.evictionTimer = nil;
    }
    dispatch_sync(self.poolQueue, ^{
        [self closeAllNoSync];
    });
}

/// Close all stores without synchronizing on poolQueue.
/// Must be called with poolQueue already held, or from dealloc when
/// re-entrancy is detected via dispatch_get_specific.
- (void)closeAllNoSync {
    for (NSString *did in self.stores) {
        PDSActorStore *store = self.stores[did];
        [store close];
    }
    [self.stores removeAllObjects];
    [self.lastAccessTime removeAllObjects];
    [self.activeUseCounts removeAllObjects];
    [self.knownDids removeAllObjects];
    self.openFileHandleCount = 0;
}

#pragma mark - Transaction Support

- (void)transactWithDid:(NSString *)did 
                  block:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block 
                  error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did retainForUse:YES error:error];
    if (!store) {
        return;
    }
    
    [store transactWithBlock:block error:error];
    [self releaseStoreUseForDid:did store:store];
}

- (void)readWithDid:(NSString *)did 
              block:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block 
              error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did retainForUse:YES error:error];
    if (!store) {
        return;
    }
    
    [store readWithBlock:block error:error];
    [self releaseStoreUseForDid:did store:store];
}

#pragma mark - Convenience Methods

- (nullable PDSDatabaseAccount *)getAccount:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did retainForUse:YES error:error];
    if (!store) {
        return nil;
    }
    PDSDatabaseAccount *account = [store getAccountForDid:did error:error];
    [self releaseStoreUseForDid:did store:store];
    return account;
}

- (nullable PDSDatabaseRepo *)getRepo:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did retainForUse:YES error:error];
    if (!store) {
        return nil;
    }
    PDSDatabaseRepo *repo = [store getRepoForDid:did error:error];
    [self releaseStoreUseForDid:did store:store];
    return repo;
}

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did retainForUse:YES error:error];
    if (!store) {
        return nil;
    }
    NSData *root = [store getRepoRootForDid:did error:error];
    [self releaseStoreUseForDid:did store:store];
    return root;
}

- (nullable PDSDatabaseRecord *)getRecord:(NSString *)uri forDid:(NSString *)did error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did retainForUse:YES error:error];
    if (!store) {
        return nil;
    }
    PDSDatabaseRecord *record = [store getRecord:uri forDid:did error:error];
    [self releaseStoreUseForDid:did store:store];
    return record;
}

- (NSArray<PDSDatabaseAccount *> *)getAllAccountsWithError:(NSError **)error {
    NSMutableArray<PDSDatabaseAccount *> *accounts = [NSMutableArray array];
    [self enumerateDidFiles:^(NSString *did) {
        PDSDatabaseAccount *account = [self getAccount:did error:nil];
        if (account) {
            [accounts addObject:account];
        }
    }];
    return accounts;
}

- (NSArray<PDSDatabaseRepo *> *)getAllReposWithError:(NSError **)error {
    NSMutableArray<PDSDatabaseRepo *> *repos = [NSMutableArray array];
    [self enumerateDidFiles:^(NSString *did) {
        PDSDatabaseRepo *repo = [self getRepo:did error:nil];
        if (repo) {
            [repos addObject:repo];
        }
    }];
    return repos;
}

// Walks {dbDir}/{method}/{prefix}/{did} looking for files starting with "did:".
// The open-store cache is not an inventory: it contains only stores that have
// been opened since this pool was created and must never determine an
// enumeration result.
- (void)enumerateDidFiles:(void (^)(NSString *did))block {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *methodDirs = [fm contentsOfDirectoryAtPath:self.dbDirectory error:nil];
    for (NSString *methodEntry in methodDirs) {
        NSString *methodPath = [self.dbDirectory stringByAppendingPathComponent:methodEntry];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:methodPath isDirectory:&isDir] || !isDir) continue;

        NSArray<NSString *> *prefixDirs = [fm contentsOfDirectoryAtPath:methodPath error:nil];
        for (NSString *prefixEntry in prefixDirs) {
            NSString *prefixPath = [methodPath stringByAppendingPathComponent:prefixEntry];
            if (![fm fileExistsAtPath:prefixPath isDirectory:&isDir] || !isDir) continue;

            NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:prefixPath error:nil];
            for (NSString *file in files) {
                if ([file hasSuffix:@"-shm"] || [file hasSuffix:@"-wal"] || [file hasSuffix:@"-journal"]) {
                    continue;
                }
                if ([file hasPrefix:@"did:"]) {
                    block(file);
                }
            }
        }
    }
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
                @"last_access": @((lastAccess ?: [NSDate distantPast]).timeIntervalSince1970)
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
