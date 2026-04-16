#import "Sync/Relay/RelayRepoStateManager.h"

@interface RelayRepoStateManager ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoRoots;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *repoRevs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoSeqs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *repoStatuses;

@end

@implementation RelayRepoStateManager {
    dispatch_queue_t _stateQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _repoRoots = [NSMutableDictionary dictionary];
        _repoRevs = [NSMutableDictionary dictionary];
        _repoSeqs = [NSMutableDictionary dictionary];
        _repoStatuses = [NSMutableDictionary dictionary];
        _stateQueue = dispatch_queue_create("com.atproto.relay.state", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)handleCommitForRepo:(NSString *)repoDID
                         root:(NSString *)rootCID
                           rev:(NSString *)rev
                           seq:(int64_t)seq {
    dispatch_async(_stateQueue, ^{
        self.repoRoots[repoDID] = rootCID;
        self.repoRevs[repoDID] = rev;
        self.repoSeqs[repoDID] = @(seq);
        self.repoStatuses[repoDID] = @(RelayRepoStatusActive);
    });
}

- (void)handleIdentityEventForRepo:(NSString *)repoDID {
    dispatch_async(_stateQueue, ^{
        self.repoStatuses[repoDID] = @(RelayRepoStatusDesynchronized);
    });
}

- (void)handleAccountEventForRepo:(NSString *)repoDID status:(RelayRepoStatus)status {
    dispatch_async(_stateQueue, ^{
        self.repoStatuses[repoDID] = @(status);
    });
}

- (void)handleTombstoneForRepo:(NSString *)repoDID {
    dispatch_async(_stateQueue, ^{
        [self.repoRoots removeObjectForKey:repoDID];
        [self.repoRevs removeObjectForKey:repoDID];
        [self.repoSeqs removeObjectForKey:repoDID];
        self.repoStatuses[repoDID] = @(RelayRepoStatusTombstoned);
    });
}

- (nullable NSString *)rootCIDForRepo:(NSString *)repoDID {
    __block NSString *root;
    dispatch_sync(_stateQueue, ^{
        root = self.repoRoots[repoDID];
    });
    return root;
}

- (nullable NSString *)revForRepo:(NSString *)repoDID {
    __block NSString *rev;
    dispatch_sync(_stateQueue, ^{
        rev = self.repoRevs[repoDID];
    });
    return rev;
}

- (int64_t)cursorForRepo:(NSString *)repoDID {
    __block int64_t cursor = -1;
    dispatch_sync(_stateQueue, ^{
        NSNumber *seq = self.repoSeqs[repoDID];
        if (seq) {
            cursor = seq.longLongValue;
        }
    });
    return cursor;
}

- (RelayRepoStatus)statusForRepo:(NSString *)repoDID {
    __block RelayRepoStatus status = RelayRepoStatusDesynchronized;
    dispatch_sync(_stateQueue, ^{
        NSNumber *s = self.repoStatuses[repoDID];
        if (s) {
            status = s.integerValue;
        }
    });
    return status;
}

- (NSArray<NSString *> *)allRepos {
    __block NSArray *repos;
    dispatch_sync(_stateQueue, ^{
        repos = [self.repoRoots allKeys];
    });
    return repos;
}

- (NSUInteger)repoCount {
    __block NSUInteger count;
    dispatch_sync(_stateQueue, ^{
        count = self.repoRoots.count;
    });
    return count;
}

- (void)persistState {
    // Would persist to SQLite for crash recovery
    // Implementation depends on database layer
}

- (BOOL)loadState:(NSError **)error {
    // Would load from SQLite on startup
    // Implementation depends on database layer
    return YES;
}

@end