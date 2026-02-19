#import "PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCMetrics.h"

@interface PLCMockStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<PLCOperation *> *> *storage;
#if defined(GNUSTEP) || defined(LINUX)
@property (nonatomic, assign) dispatch_queue_t queue;
#else
@property (nonatomic, strong) dispatch_queue_t queue;
#endif
@end

@implementation PLCMockStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.atproto.pds.plcmockstore", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (nullable NSArray<PLCOperation *> *)getHistoryForDID:(NSString *)did
                                      includeNullified:(BOOL)includeNullified
                                                 error:(NSError **)error {
    __block NSArray<PLCOperation *> *history = nil;
    dispatch_sync(self.queue, ^{
        NSArray<PLCOperation *> *stored = self.storage[did];
        if (!includeNullified && stored.count > 0) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PLCOperation *op, NSDictionary *bindings) {
                return !op.nullified;
            }];
            history = [stored filteredArrayUsingPredicate:predicate];
        } else {
            history = stored;
        }
    });
    
    if (history) {
        [[PLCMetrics sharedMetrics] recordMemcacheHit];
    } else {
        [[PLCMetrics sharedMetrics] recordMemcacheMiss];
    }
    
    return history ?: @[];
}

- (BOOL)appendOperation:(PLCOperation *)op
           nullifyCIDs:(NSArray<NSString *> *)nullified
                 error:(NSError **)error {
    if (!op.did) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCMockStore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Operation missing DID"}];
        }
        return NO;
    }

    dispatch_sync(self.queue, ^{
        NSMutableArray<PLCOperation *> *history = self.storage[op.did];
        if (!history) {
            history = [NSMutableArray array];
            self.storage[op.did] = history;
        }
        if (!op.createdAt) {
            op.createdAt = [NSDate date];
        }
        if (!op.cid) {
            NSError *cidError = nil;
            op.cid = [PLCOperation calculateCIDForOperation:[op toDictionary] error:&cidError];
        }
        op.nullified = NO;
        if (nullified.count > 0) {
            NSSet<NSString *> *nullifiedSet = [NSSet setWithArray:nullified];
            for (PLCOperation *existing in history) {
                if (existing.cid && [nullifiedSet containsObject:existing.cid]) {
                    existing.nullified = YES;
                }
            }
        }
        [history addObject:op];
    });

    return YES;
}

- (nullable NSArray<NSString *> *)getAllDIDsWithError:(NSError **)error {
    __block NSArray<NSString *> *keys = nil;
    dispatch_sync(self.queue, ^{
        keys = [self.storage.allKeys copy];
    });
    return keys ?: @[];
}

- (nullable PLCOperation *)getLatestOperationForDID:(NSString *)did error:(NSError **)error {
    __block PLCOperation *op = nil;
    dispatch_sync(self.queue, ^{
        NSArray<PLCOperation *> *history = self.storage[did];
        if (history && history.count > 0) {
            // Find last non-nullified operation? Spec says "latest operation", usually implies valid chain tip.
            // But log/last usually returns just the last entry.
            // Let's return the absolute last entry regardless of nullification status for now,
            // as that's what "log" implies (append-only).
            op = history.lastObject;
        }
    });
    return op;
}

- (nullable NSArray<PLCOperation *> *)exportOperationsAfter:(nullable NSDate *)after
                                                      count:(NSUInteger)count
                                                      error:(NSError **)error {
    __block NSArray<PLCOperation *> *result = nil;
    dispatch_sync(self.queue, ^{
        NSMutableArray<PLCOperation *> *allOps = [NSMutableArray array];
        for (NSArray<PLCOperation *> *didOps in self.storage.allValues) {
            [allOps addObjectsFromArray:didOps];
        }
        
        if (after) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(PLCOperation *op, NSDictionary *bindings) {
                return [op.createdAt compare:after] == NSOrderedDescending;
            }];
            [allOps filterUsingPredicate:predicate];
        }
        
        [allOps sortUsingComparator:^NSComparisonResult(PLCOperation *op1, PLCOperation *op2) {
            NSComparisonResult timeResult = [op1.createdAt compare:op2.createdAt];
            if (timeResult == NSOrderedSame) {
                return [op1.cid compare:op2.cid]; // Fallback sort
            }
            return timeResult;
        }];
        
        if (allOps.count > count) {
            result = [allOps subarrayWithRange:NSMakeRange(0, count)];
        } else {
            result = [allOps copy];
        }
    });
    return result ?: @[];
}

@end
