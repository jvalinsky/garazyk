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

@interface PDSDatabasePoolTimerProxy : NSObject
@property (nonatomic, weak) id pool;
@end

@implementation PDSDatabasePoolTimerProxy
- (void)evictionTimerFired:(NSTimer *)timer {
    [self.pool performSelector:@selector(evictionTimerFired:) withObject:timer];
}
@end

@interface PDSDatabasePool ()
- (void)evictionTimerFired:(NSTimer *)timer;
@property (nonatomic, copy, readwrite) NSString *dbDirectory;
@property (nonatomic, assign, readwrite) NSUInteger maxSize;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSActorStore *> *stores;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastAccessTime;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t poolQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t evictionQueue;
@property (nonatomic, strong) NSTimer *evictionTimer;
@property (nonatomic, assign, readwrite) NSUInteger openFileHandleCount;

@end

@implementation PDSDatabasePool

- (void)evictionTimerFired:(NSTimer *)timer {
    dispatch_async(self.evictionQueue, ^{
        [self evictUnusedStores];
    });
}

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
                GZ_LOG_DB_ERROR(@"Failed to create database directory: %@ (error: %@)", dbDirectory, error);
            }
        }
        
        PDSDatabasePoolTimerProxy *proxy = [[PDSDatabasePoolTimerProxy alloc] init];
        proxy.pool = self;
        _evictionTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                          target:proxy
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
    __block PDSActorStore *store = nil;
    __block NSError *blockError = nil;
    __block NSString *dbPath = nil;

    dispatch_sync(self.poolQueue, ^{
        store = self.stores[did];

        if (store) {
            self.lastAccessTime[did] = [NSDate date];
            return;
        }

        if (self.stores.count >= self.maxSize) {
            [self evictLRUStore];
        }

        dbPath = [self dbPathForDid:did];
        if (dbPath.length == 0) {
            blockError = [NSError errorWithDomain:PDSDatabasePoolErrorDomain
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID for actor store path"}];
            return;
        }
        GZ_LOG_DB_DEBUG(@"Opening store at path: %@ (exists: %d)", dbPath,
                         [[NSFileManager defaultManager] fileExistsAtPath:dbPath]);

        store = [PDSActorStore storeWithDid:did dbPath:dbPath error:&blockError];

        if (store) {
            store.masterSecret = self.masterSecret;
            self.stores[did] = store;
            self.lastAccessTime[did] = [NSDate date];
            self.openFileHandleCount++;
        } else {
            GZ_LOG_DB_ERROR(@"Failed to open store for %@: %@", did, blockError);
        }
    });

    if (error && blockError) {
        *error = blockError;
    }

    return store;
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
    [self.evictionTimer invalidate];
    self.evictionTimer = nil;
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
                  block:(void (^)(id<PDSActorStoreTransactor> transactor, NSError **error))block 
                  error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return;
    }
    
    [store transactWithBlock:block error:error];
}

- (void)readWithDid:(NSString *)did 
              block:(void (^)(id<PDSActorStoreReader> reader, NSError **error))block 
              error:(NSError **)error {
    PDSActorStore *store = [self storeForDid:did error:error];
    if (!store) {
        return;
    }
    
    [store readWithBlock:block error:error];
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
