// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/AdminUI/PLCAdminSnapshot.h"

#import "PLC/PLCMetrics.h"
#import "PLC/PLCOperation.h"
#import "PLC/PLCStore.h"
#import "PLC/PLCSyncEngine.h"
#import "Compat/PDSTypes.h"

static const NSUInteger PLCAdminSnapshotAuditLimit = 50;

static NSString *PLCAdminSyncStateName(PLCSyncState state) {
    switch (state) {
        case PLCSyncStateIdle: return @"idle";
        case PLCSyncStateBackfilling: return @"backfilling";
        case PLCSyncStateLiveSyncing: return @"active";
        case PLCSyncStatePaused: return @"paused";
        case PLCSyncStateError: return @"failed";
    }
    return @"unknown";
}

@interface GZPLCAdminSnapshot ()
@property(nonatomic, strong) id<PLCStore> store;
@property(nonatomic, strong, nullable) ATProtoPLCSyncEngine *syncEngine;
@property(nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t snapshotQueue;
@property(nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *adminAudit;
@end

@implementation GZPLCAdminSnapshot

- (instancetype)initWithStore:(id<PLCStore>)store syncEngine:(ATProtoPLCSyncEngine *)syncEngine {
    self = [super init];
    if (self) {
        _store = store;
        _syncEngine = syncEngine;
        _snapshotQueue = dispatch_queue_create("com.atproto.plc.admin.snapshot", DISPATCH_QUEUE_SERIAL);
        _adminAudit = [NSMutableArray array];
    }
    return self;
}

- (BOOL)isReplica {
    return self.syncEngine != nil;
}

- (NSDictionary<NSString *, id> *)snapshot {
    __block NSDictionary<NSString *, id> *result = nil;
    dispatch_sync(self.snapshotQueue, ^{
        NSError *didError = nil;
        NSUInteger didCount = [self.store uniqueDIDCountWithError:&didError];
        NSError *operationsError = nil;
        NSUInteger operationCount = [self.store totalOperationCountWithError:&operationsError];
        NSDictionary *metrics = [[ATProtoPLCMetrics sharedMetrics] snapshot];
        NSMutableDictionary<NSString *, id> *snapshot = [@{
            @"mode": self.isReplica ? @"replica" : @"primary",
            @"health": (didError || operationsError) ? @"degraded" : @"ok",
            @"didTotal": @(didCount),
            @"operationTotal": @(operationCount),
            @"metrics": metrics,
            @"adminAudit": [self.adminAudit copy],
        } mutableCopy];
        if (didError || operationsError) {
            snapshot[@"error"] = (didError ?: operationsError).localizedDescription ?: @"PLC store unavailable";
        }
        if (self.syncEngine) {
            snapshot[@"replication"] = @{
                @"state": PLCAdminSyncStateName(self.syncEngine.state),
                @"cursor": @(self.syncEngine.currentCursor),
                @"lastSync": self.syncEngine.lastSyncDate ?: [NSNull null],
                @"ingested": @(self.syncEngine.totalOperationsIngested),
                @"failed": @(self.syncEngine.totalOperationsFailed),
                @"workers": @(self.syncEngine.numWorkers),
                @"batchSize": @(self.syncEngine.batchSize),
            };
        }
        result = [snapshot copy];
    });
    return result;
}

- (void)recordAdminAction:(NSString *)action succeeded:(BOOL)succeeded error:(NSError *)error {
    dispatch_sync(self.snapshotQueue, ^{
        [self.adminAudit addObject:@{
            @"action": action ?: @"",
            @"succeeded": @(succeeded),
            @"timestamp": [NSDate date],
            @"error": error.localizedDescription ?: @"",
        }];
        if (self.adminAudit.count > PLCAdminSnapshotAuditLimit) {
            [self.adminAudit removeObjectAtIndex:0];
        }
    });
}

- (NSDictionary<NSString *, id> *)directoryEntryForDID:(NSString *)did {
    if (did.length == 0 || did.length > 2048 || ![did hasPrefix:@"did:"]) {
        return @{@"error": @"invalid_did", @"message": @"A bounded DID is required"};
    }
    __block NSDictionary<NSString *, id> *result = nil;
    dispatch_sync(self.snapshotQueue, ^{
        NSError *error = nil;
        NSInteger operationCount = [self.store operationCountForDid:did error:&error];
        if (operationCount < 0) {
            result = @{@"error": @"lookup_failed", @"message": error.localizedDescription ?: @"Directory lookup failed"};
            return;
        }
        NSError *nullifiedError = nil;
        NSInteger nullifiedCount = [self.store nullifiedOperationCountForDid:did error:&nullifiedError];
        NSError *latestError = nil;
        ATProtoPLCOperation *latest = [self.store getLatestOperationForDID:did error:&latestError];
        if (nullifiedCount < 0 || latestError) {
            NSError *lookupError = nullifiedError ?: latestError;
            result = @{@"error": @"lookup_failed", @"message": lookupError.localizedDescription ?: @"Directory lookup failed"};
            return;
        }
        result = @{
            @"did": did,
            @"operationChainLength": @(operationCount),
            @"nullifiedOperations": @(MAX(nullifiedCount, 0)),
            @"currentOperation": latest ? @{ @"type": latest.data[@"type"] ?: @"", @"cid": latest.cid ?: @"" } : @{},
            @"verification": @{ @"status": @"recorded", @"failures": [[ATProtoPLCMetrics sharedMetrics] snapshot][@"verificationFailures"] ?: @0 },
        };
    });
    return result;
}

- (BOOL)performReplicaAction:(NSString *)action error:(NSError **)error {
    NSError *actionError = nil;
    BOOL succeeded = NO;
    if (!self.syncEngine) {
        actionError = [NSError errorWithDomain:@"GZPLCAdminSnapshot" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Replica actions are unavailable in primary mode"}];
    } else if ([action isEqualToString:@"pause"]) {
        [self.syncEngine pause];
        succeeded = YES;
    } else if ([action isEqualToString:@"resume"]) {
        [self.syncEngine resume];
        succeeded = YES;
    } else if ([action isEqualToString:@"sync-once"]) {
        succeeded = [self.syncEngine syncOnceWithError:&actionError];
    } else {
        actionError = [NSError errorWithDomain:@"GZPLCAdminSnapshot" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Unknown replica action"}];
    }
    [self recordAdminAction:action succeeded:succeeded error:actionError];
    if (error) *error = actionError;
    return succeeded;
}

@end
