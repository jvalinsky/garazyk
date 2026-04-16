/*!
 @file AppViewRelevanceSet.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Relevance/AppViewRelevanceSet.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Compat/PDSTypes.h"
#import "Debug/PDSLogger.h"

@interface AppViewRelevanceSet ()
@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) NSArray<NSString *> *seedDIDs;
@property (nonatomic, strong) NSArray<NSString *> *allowlist;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue; // Protects writes
@end

@implementation AppViewRelevanceSet

- (instancetype)initWithDatabase:(AppViewDatabase *)database
                        seedDIDs:(NSArray<NSString *> *)seedDIDs
                       allowlist:(NSArray<NSString *> *)allowlist
                        ttlHours:(NSUInteger)ttlHours {
    self = [super init];
    if (!self) return nil;
    _database  = database;
    _seedDIDs  = [seedDIDs copy];
    _allowlist = [allowlist copy];
    _ttlHours  = ttlHours > 0 ? ttlHours : 168;
    _queue     = dispatch_queue_create("dev.garazyk.appview.relevance", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)rebuild {
    // Insert all permanent members
    NSMutableArray<NSString *> *permanent = [NSMutableArray array];
    [permanent addObjectsFromArray:_seedDIDs];
    [permanent addObjectsFromArray:_allowlist];

    dispatch_async(_queue, ^{
        for (NSString *did in self.seedDIDs) {
            AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
                initWithDID:did reason:AppViewRelevanceReasonSeed expiresAt:nil];
            [self.database upsertRelevanceMembership:m error:nil];
        }
        for (NSString *did in self.allowlist) {
            AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
                initWithDID:did reason:AppViewRelevanceReasonAllowlist expiresAt:nil];
            [self.database upsertRelevanceMembership:m error:nil];
        }
        PDS_LOG_INFO(@"[AppViewRelevanceSet] Rebuilt with %lu seeds + %lu allowlist entries",
                     (unsigned long)self.seedDIDs.count,
                     (unsigned long)self.allowlist.count);
    });
}

- (BOOL)isDIDRelevant:(NSString *)did {
    return [_database isDIDRelevant:did];
}

- (void)addDID:(NSString *)did reason:(AppViewRelevanceReason)reason {
    dispatch_async(_queue, ^{
        [self _addDIDOnQueue:did reason:reason];
    });
}

- (void)addDIDs:(NSArray<NSString *> *)dids reason:(AppViewRelevanceReason)reason {
    dispatch_async(_queue, ^{
        for (NSString *did in dids) {
            [self _addDIDOnQueue:did reason:reason];
        }
    });
}

- (void)_addDIDOnQueue:(NSString *)did reason:(AppViewRelevanceReason)reason {
    BOOL permanent = (reason == AppViewRelevanceReasonSeed ||
                      reason == AppViewRelevanceReasonAllowlist);
    NSDate *expires = permanent ? nil
        : [NSDate dateWithTimeIntervalSinceNow:self.ttlHours * 3600.0];

    AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
        initWithDID:did reason:reason expiresAt:expires];
    [self.database upsertRelevanceMembership:m error:nil];
}

- (void)expandFromFollowsOf:(NSString *)did {
    // Expansion is driven by the graph indexer when it processes follow records.
    // This method is a hook for on-demand expansion from the query path.
    PDS_LOG_DEBUG(@"[AppViewRelevanceSet] expandFromFollowsOf: %@", did);
}

- (void)recordInteraction:(NSString *)actorDID withDID:(NSString *)targetDID {
    if (![self isDIDRelevant:actorDID]) return;
    [self addDID:targetDID reason:AppViewRelevanceReasonRecentInteraction];
}

- (NSInteger)pruneExpired {
    NSError *err = nil;
    NSInteger pruned = [_database pruneExpiredRelevanceMemberships:&err];
    if (err) PDS_LOG_WARN(@"[AppViewRelevanceSet] Prune error: %@", err.localizedDescription);
    PDS_LOG_INFO(@"[AppViewRelevanceSet] Pruned %ld expired memberships.", (long)pruned);
    return pruned;
}

- (NSArray<NSString *> *)allRelevantDIDs {
    NSError *err = nil;
    return [_database loadAllRelevantDIDs:&err] ?: @[];
}

@end
