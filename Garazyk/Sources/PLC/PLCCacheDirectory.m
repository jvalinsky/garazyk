// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCCacheDirectory.h"
#import "Compat/PDSTypes.h"

NSTimeInterval const PLCCacheDefaultTTL = 300.0;
NSUInteger const PLCCacheDefaultCapacity = 1000;

@interface ATProtoPLCCacheEntry : NSObject
@property (nonatomic, strong) NSArray<ATProtoPLCOperation *> *operations;
@property (nonatomic, strong) NSDate *createdAt;
@end

@implementation ATProtoPLCCacheEntry
@end

@interface ATProtoPLCCacheDirectory ()
@property (nonatomic, strong, readwrite) id<PLCStore> innerStore;
@property (nonatomic, strong) NSCache<NSString *, ATProtoPLCCacheEntry *> *operationCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *cachedDIDs;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t cacheQueue;
@property (nonatomic, assign) NSUInteger hitCount;
@property (nonatomic, assign) NSUInteger missCount;
@end

@implementation ATProtoPLCCacheDirectory

- (instancetype)initWithStore:(id<PLCStore>)store {
    self = [super init];
    if (self) {
        _innerStore = store;
        _operationCache = [[NSCache alloc] init];
        _operationCache.countLimit = PLCCacheDefaultCapacity;
        _cachedDIDs = [NSMutableSet set];
        _cacheQueue = dispatch_queue_create("com.atproto.pds.plc.cachedirectory", DISPATCH_QUEUE_SERIAL);
        _ttl = PLCCacheDefaultTTL;
        _maxEntries = PLCCacheDefaultCapacity;
        _hitCount = 0;
        _missCount = 0;
    }
    return self;
}

- (void)setMaxEntries:(NSUInteger)maxEntries {
    _maxEntries = maxEntries;
    if (maxEntries > 0) {
        self.operationCache.countLimit = maxEntries;
    }
}

#pragma mark - PLCStore Protocol

- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error {
    return [self.innerStore getAllDIDsWithError:error];
}

- (nullable ATProtoPLCOperation *)getLatestOperationForDID:(NSString *)did error:(NSError **)error {
    return [self.innerStore getLatestOperationForDID:did error:error];
}

- (NSInteger)operationCountForDid:(NSString *)did error:(NSError **)error {
    return [self.innerStore operationCountForDid:did error:error];
}

- (NSInteger)nullifiedOperationCountForDid:(NSString *)did error:(NSError **)error {
    return [self.innerStore nullifiedOperationCountForDid:did error:error];
}

- (NSUInteger)uniqueDIDCountWithError:(NSError **)error {
    return [self.innerStore uniqueDIDCountWithError:error];
}

- (NSUInteger)totalOperationCountWithError:(NSError **)error {
    return [self.innerStore totalOperationCountWithError:error];
}

- (nullable NSArray<ATProtoPLCOperation *> *)exportOperationsAfter:(nullable NSDate *)after
                                                      count:(NSUInteger)count
                                                      error:(NSError **)error {
    return [self.innerStore exportOperationsAfter:after count:count error:error];
}

- (nullable NSArray<ATProtoPLCOperation *> *)exportOperationsAfterSequence:(NSNumber *)sequence
                                                              count:(NSUInteger)count
                                                              error:(NSError **)error {
    return [self.innerStore exportOperationsAfterSequence:sequence count:count error:error];
}

- (nullable NSArray<ATProtoPLCOperation *> *)getHistoryForDID:(NSString *)did
                                      includeNullified:(BOOL)includeNullified
                                                 error:(NSError **)error {
    if (includeNullified) {
        return [self.innerStore getHistoryForDID:did includeNullified:YES error:error];
    }

    __block NSArray<ATProtoPLCOperation *> *result = nil;
    __block BOOL isStale = NO;
    __block NSError *blockError = nil;
    
    dispatch_sync(self.cacheQueue, ^{
        ATProtoPLCCacheEntry *cached = [self.operationCache objectForKey:did];
        
        if (cached) {
            NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:cached.createdAt];
            if (age < self.ttl) {
                self.hitCount++;
                result = cached.operations;
                return;
            }
            isStale = YES;
        }
        
        self.missCount++;
        
        result = [self.innerStore getHistoryForDID:did includeNullified:NO error:&blockError];
        
        ATProtoPLCCacheEntry *entry = [[ATProtoPLCCacheEntry alloc] init];
        entry.operations = result ?: @[];
        entry.createdAt = [NSDate date];
        
        [self.operationCache setObject:entry forKey:did];
        [self.cachedDIDs addObject:did];
    });
    
    if (blockError && error) {
        *error = blockError;
    }
    
    if (isStale && result) {
        dispatch_async(self.cacheQueue, ^{
            ATProtoPLCCacheEntry *entry = [[ATProtoPLCCacheEntry alloc] init];
            entry.operations = result;
            entry.createdAt = [NSDate date];
            [self.operationCache setObject:entry forKey:did];
        });
    }
    
    return result;
}

- (BOOL)appendOperation:(ATProtoPLCOperation *)op
           nullifyCIDs:(NSArray<NSString *> *)nullified
                 error:(NSError **)error {
    BOOL success = [self.innerStore appendOperation:op nullifyCIDs:nullified error:error];
    
    if (success) {
        [self flushCacheForDID:op.did];
    }
    
    return success;
}

#pragma mark - Cache Management

- (void)flushCacheForDID:(NSString *)did {
    dispatch_async(self.cacheQueue, ^{
        [self.operationCache removeObjectForKey:did];
        [self.cachedDIDs removeObject:did];
    });
}

- (void)flushAllCaches {
    dispatch_async(self.cacheQueue, ^{
        [self.operationCache removeAllObjects];
        [self.cachedDIDs removeAllObjects];
    });
}

- (NSUInteger)cacheHitCount {
    __block NSUInteger count;
    dispatch_sync(self.cacheQueue, ^{
        count = self.hitCount;
    });
    return count;
}

- (NSUInteger)cacheMissCount {
    __block NSUInteger count;
    dispatch_sync(self.cacheQueue, ^{
        count = self.missCount;
    });
    return count;
}

@end
