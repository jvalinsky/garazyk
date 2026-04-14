#import "Sync/RelayEventFilter.h"

@interface RelayEventFilter ()

@property (nonatomic, strong, readwrite, nullable) NSSet<NSString *> *allowedCollections;
@property (nonatomic, strong, readwrite, nullable) NSSet<NSString *> *allowedRepos;
@property (nonatomic, strong, readwrite, nullable) NSSet<NSString *> *blockedActors;

@end

@implementation RelayEventFilter

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

- (void)setAllowedCollections:(nullable NSArray<NSString *> *)collections {
    self.allowedCollections = collections ? [NSSet setWithArray:collections] : nil;
}

- (void)setAllowedRepos:(nullable NSArray<NSString *> *)repos {
    self.allowedRepos = repos ? [NSSet setWithArray:repos] : nil;
}

- (void)setBlockedActors:(nullable NSArray<NSString *> *)actors {
    self.blockedActors = actors ? [NSSet setWithArray:actors] : nil;
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