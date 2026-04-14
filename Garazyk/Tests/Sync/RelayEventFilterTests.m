#import <XCTest/XCTest.h>
#import "Sync/RelayEventFilter.h"

@interface RelayEventFilterTests : XCTestCase
@end

@implementation RelayEventFilterTests

- (void)testDefaultFilterAllowsAll {
    RelayEventFilter *filter = [[RelayEventFilter alloc] initWithAllowedCollections:nil allowedRepos:nil blockedActors:nil];
    XCTAssertTrue([filter shouldForwardCollection:@"app.bsky.feed.post"]);
    XCTAssertTrue([filter shouldForwardCollection:@"app.bsky.actor.profile"]);
}

- (void)testAllowListFilters {
    RelayEventFilter *filter = [[RelayEventFilter alloc] initWithAllowedCollections:@[@"app.bsky.feed.post", @"app.bsky.feed.like"] allowedRepos:nil blockedActors:nil];
    XCTAssertTrue([filter shouldForwardCollection:@"app.bsky.feed.post"]);
    XCTAssertTrue([filter shouldForwardCollection:@"app.bsky.feed.like"]);
    XCTAssertFalse([filter shouldForwardCollection:@"app.bsky.actor.profile"]);
}

- (void)testDenyListFilters {
    RelayEventFilter *filter = [[RelayEventFilter alloc] initWithAllowedCollections:nil allowedRepos:nil blockedActors:@[@"did:plc:blocked"]];
    XCTAssertTrue([filter shouldForwardActor:@"did:plc:other"]);
    XCTAssertFalse([filter shouldForwardActor:@"did:plc:blocked"]);
}

- (void)testRepoFilter {
    RelayEventFilter *filter = [[RelayEventFilter alloc] initWithAllowedCollections:nil allowedRepos:@[@"did:plc:allowed"] blockedActors:nil];
    XCTAssertTrue([filter shouldForwardRepo:@"did:plc:allowed"]);
    XCTAssertFalse([filter shouldForwardRepo:@"did:plc:other"]);
}

- (void)testEventFilterCombines {
    RelayEventFilter *filter = [[RelayEventFilter alloc] initWithAllowedCollections:@[@"app.bsky.feed.post"] allowedRepos:@[@"did:plc:allowed"] blockedActors:nil];
    XCTAssertTrue([filter shouldForwardEventWithRepo:@"did:plc:allowed" andCollection:@"app.bsky.feed.post" andActor:nil]);
    XCTAssertFalse([filter shouldForwardEventWithRepo:@"did:plc:other" andCollection:@"app.bsky.feed.post" andActor:nil]);
}

@end
