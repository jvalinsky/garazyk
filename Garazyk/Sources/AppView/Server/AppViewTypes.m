/*!
 @file AppViewTypes.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/AppViewTypes.h"

#pragma mark - AppViewRepoSyncState

@implementation AppViewRepoSyncState

- (instancetype)initWithDID:(NSString *)did {
    self = [super init];
    if (self) {
        _did        = [did copy];
        _status     = AppViewRepoSyncStatusPending;
        _errorCount = 0;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    AppViewRepoSyncState *copy = [[AppViewRepoSyncState allocWithZone:zone] initWithDID:_did];
    copy.status        = _status;
    copy.lastRev       = _lastRev;
    copy.lastBackfillAt = _lastBackfillAt;
    copy.errorCount    = _errorCount;
    copy.lastError     = _lastError;
    return copy;
}

@end

#pragma mark - AppViewCheckpoint

@implementation AppViewCheckpoint

- (instancetype)initWithRelayURL:(NSString *)relayURL seq:(int64_t)seq {
    self = [super init];
    if (self) {
        _relayURL = [relayURL copy];
        _seq      = seq;
        _savedAt  = [NSDate date];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    AppViewCheckpoint *copy = [[AppViewCheckpoint allocWithZone:zone]
        initWithRelayURL:_relayURL seq:_seq];
    copy.savedAt = _savedAt;
    return copy;
}

@end

#pragma mark - AppViewPendingDelta

@implementation AppViewPendingDelta

- (instancetype)initWithDID:(NSString *)did
                        seq:(int64_t)seq
                  commitCID:(NSString *)commitCID
                        rev:(NSString *)rev
                rawEnvelope:(NSData *)rawEnvelope {
    self = [super init];
    if (self) {
        _did         = [did copy];
        _seq         = seq;
        _commitCID   = [commitCID copy];
        _rev         = [rev copy];
        _rawEnvelope = rawEnvelope;
        _enqueuedAt  = [NSDate date];
    }
    return self;
}

@end

#pragma mark - AppViewRelevanceMembership

@implementation AppViewRelevanceMembership

- (instancetype)initWithDID:(NSString *)did
                     reason:(AppViewRelevanceReason)reason
                  expiresAt:(nullable NSDate *)expiresAt {
    self = [super init];
    if (self) {
        _did       = [did copy];
        _reason    = reason;
        _expiresAt = expiresAt;
        _addedAt   = [NSDate date];
    }
    return self;
}

- (BOOL)isValid {
    if (_expiresAt == nil) return YES;
    return [_expiresAt timeIntervalSinceNow] > 0;
}

@end
