// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCMockStore.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCMetrics.h"
#import "Compat/PDSTypes.h"

@interface ATProtoPLCMockStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<ATProtoPLCOperation *> *> *storage;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property (nonatomic, assign) NSInteger nextSequence;
@end

@implementation ATProtoPLCMockStore

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.atproto.pds.plcmockstore", DISPATCH_QUEUE_SERIAL);
        _nextSequence = 1;
    }
    return self;
}

- (nullable NSArray<ATProtoPLCOperation *> *)getHistoryForDID:(NSString *)did
                                      includeNullified:(BOOL)includeNullified
                                                 error:(NSError **)error {
    __block NSArray<ATProtoPLCOperation *> *history = nil;
    dispatch_sync(self.queue, ^{
        NSArray<ATProtoPLCOperation *> *stored = self.storage[did];
        if (!includeNullified && stored.count > 0) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(ATProtoPLCOperation *op, NSDictionary *bindings) {
                return !op.nullified;
            }];
            history = [stored filteredArrayUsingPredicate:predicate];
        } else {
            history = stored;
        }
    });
    
    if (history) {
        [[ATProtoPLCMetrics sharedMetrics] recordMemcacheHit];
    } else {
        [[ATProtoPLCMetrics sharedMetrics] recordMemcacheMiss];
    }
    
    return history ?: @[];
}

- (BOOL)appendOperation:(ATProtoPLCOperation *)op
           nullifyCIDs:(NSArray<NSString *> *)nullified
                 error:(NSError **)error {
    if (!op.did) {
        if (error) {
            *error = [NSError errorWithDomain:@"PLCMockStore" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Operation missing DID"}];
        }
        return NO;
    }

    dispatch_sync(self.queue, ^{
        NSMutableArray<ATProtoPLCOperation *> *history = self.storage[op.did];
        if (!history) {
            history = [NSMutableArray array];
            self.storage[op.did] = history;
        }
        if (!op.createdAt) {
            op.createdAt = [NSDate date];
        }
        if (!op.sequence) {
            op.sequence = @(self.nextSequence++);
        } else if (op.sequence.integerValue >= self.nextSequence) {
            self.nextSequence = op.sequence.integerValue + 1;
        }
        if (!op.cid) {
            NSError *cidError = nil;
            op.cid = [ATProtoPLCOperation calculateCIDForOperation:[op toDictionary] error:&cidError];
        }
        op.nullified = NO;
        if (nullified.count > 0) {
            NSSet<NSString *> *nullifiedSet = [NSSet setWithArray:nullified];
            for (ATProtoPLCOperation *existing in history) {
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

- (nullable ATProtoPLCOperation *)getLatestOperationForDID:(NSString *)did error:(NSError **)error {
    __block ATProtoPLCOperation *op = nil;
    dispatch_sync(self.queue, ^{
        NSArray<ATProtoPLCOperation *> *history = self.storage[did];
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

- (NSInteger)operationCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    dispatch_sync(self.queue, ^{
        count = self.storage[did].count;
    });
    return count;
}

- (NSInteger)nullifiedOperationCountForDid:(NSString *)did error:(NSError **)error {
    __block NSInteger count = 0;
    dispatch_sync(self.queue, ^{
        for (ATProtoPLCOperation *operation in self.storage[did]) {
            if (operation.nullified) count++;
        }
    });
    return count;
}

- (NSUInteger)uniqueDIDCountWithError:(NSError **)error {
    __block NSUInteger count = 0;
    dispatch_sync(self.queue, ^{
        count = self.storage.count;
    });
    return count;
}

- (NSUInteger)totalOperationCountWithError:(NSError **)error {
    __block NSUInteger count = 0;
    dispatch_sync(self.queue, ^{
        for (NSArray<ATProtoPLCOperation *> *operations in self.storage.allValues) {
            count += operations.count;
        }
    });
    return count;
}

- (nullable NSArray<ATProtoPLCOperation *> *)exportOperationsAfter:(nullable NSDate *)after
                                                      count:(NSUInteger)count
                                                      error:(NSError **)error {
    __block NSArray<ATProtoPLCOperation *> *result = nil;
    dispatch_sync(self.queue, ^{
        NSMutableArray<ATProtoPLCOperation *> *allOps = [NSMutableArray array];
        for (NSArray<ATProtoPLCOperation *> *didOps in self.storage.allValues) {
            [allOps addObjectsFromArray:didOps];
        }
        
        if (after) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(ATProtoPLCOperation *op, NSDictionary *bindings) {
                return [op.createdAt compare:after] == NSOrderedDescending;
            }];
            [allOps filterUsingPredicate:predicate];
        }
        
        [allOps sortUsingComparator:^NSComparisonResult(ATProtoPLCOperation *op1, ATProtoPLCOperation *op2) {
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

- (nullable NSArray<ATProtoPLCOperation *> *)exportOperationsAfterSequence:(NSNumber *)sequence
                                                              count:(NSUInteger)count
                                                              error:(NSError **)error {
    __block NSArray<ATProtoPLCOperation *> *result = nil;
    dispatch_sync(self.queue, ^{
        NSMutableArray<ATProtoPLCOperation *> *allOps = [NSMutableArray array];
        for (NSArray<ATProtoPLCOperation *> *didOps in self.storage.allValues) {
            [allOps addObjectsFromArray:didOps];
        }
        NSInteger cursor = sequence.integerValue;
        [allOps filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ATProtoPLCOperation *op, NSDictionary *bindings) {
            return op.sequence.integerValue > cursor;
        }]];
        [allOps sortUsingComparator:^NSComparisonResult(ATProtoPLCOperation *op1, ATProtoPLCOperation *op2) {
            return [op1.sequence compare:op2.sequence];
        }];
        result = (allOps.count > count) ? [allOps subarrayWithRange:NSMakeRange(0, count)] : [allOps copy];
    });
    return result ?: @[];
}

@end
