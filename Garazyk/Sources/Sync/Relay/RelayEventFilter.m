#import "Sync/Relay/RelayEventFilter.h"

@interface RelayEventFilter ()

@property (nonatomic, strong, readwrite, nullable) NSSet<NSString *> *allowedCollections;
@property (nonatomic, strong, readwrite, nullable) NSSet<NSString *> *allowedRepos;
@property (nonatomic, strong, readwrite, nullable) NSSet<NSString *> *blockedActors;

@end

@implementation RelayEventFilter

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithAllowedCollections:(nullable NSArray<NSString *> *)collections
                          allowedRepos:(nullable NSArray<NSString *> *)repos
                          blockedActors:(nullable NSArray<NSString *> *)actors {
    self = [super init];
    if (self) {
        _allowedCollections = collections ? [NSSet setWithArray:collections] : nil;
        _allowedRepos = repos ? [NSSet setWithArray:repos] : nil;
        _blockedActors = actors ? [NSSet setWithArray:actors] : nil;
    }
    return self;
}

- (void)setAllowedCollections:(nullable NSSet<NSString *> *)collections {
    _allowedCollections = collections;
}

- (void)setAllowedRepos:(nullable NSSet<NSString *> *)repos {
    _allowedRepos = repos;
}

- (void)setBlockedActors:(nullable NSSet<NSString *> *)actors {
    _blockedActors = actors;
}

- (void)clearFilters {
    self.allowedCollections = nil;
    self.allowedRepos = nil;
    self.blockedActors = nil;
}

- (BOOL)shouldForwardCollection:(NSString *)collection {
    if (!self.allowedCollections || self.allowedCollections.count == 0) {
        return YES;
    }
    return [self.allowedCollections containsObject:collection];
}

- (BOOL)shouldForwardRepo:(NSString *)repoDID {
    if (!self.allowedRepos || self.allowedRepos.count == 0) {
        return YES;
    }
    return [self.allowedRepos containsObject:repoDID];
}

- (BOOL)shouldForwardActor:(NSString *)actorDID {
    if (!self.blockedActors || self.blockedActors.count == 0) {
        return YES;
    }
    return ![self.blockedActors containsObject:actorDID];
}

- (BOOL)shouldForwardEventWithRepo:(NSString *)repoDID
                      andCollection:(nullable NSString *)collection
                         andActor:(nullable NSString *)actorDID {
    // Check repo first
    if (repoDID && ![self shouldForwardRepo:repoDID]) {
        return NO;
    }
    
    // Check collection
    if (collection && ![self shouldForwardCollection:collection]) {
        return NO;
    }
    
    // Check actor (blocked list)
    if (actorDID && ![self shouldForwardActor:actorDID]) {
        return NO;
    }
    
    return YES;
}

@end