// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "AppView/Server/AppViewDatabase.h"
#import "AppView/Server/Hooks/AppViewIndexHook.h"
#import "AppView/Server/Hooks/AppViewIndexHookRegistry.h"
#import "AppView/Server/Hooks/AppViewSearchIndexHook.h"
#import "AppView/Server/Hooks/AppViewWebhookHook.h"

#pragma mark - Mock Hook

@interface GZTestHook : NSObject <AppViewIndexHook>
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy, nullable) NSArray<NSString *> *hookCollections;
@property (nonatomic, assign) NSUInteger indexCallCount;
@property (nonatomic, assign) NSUInteger deleteCallCount;
@property (nonatomic, copy, nullable) NSString *lastIndexedURI;
@property (nonatomic, copy, nullable) NSString *lastDeletedURI;
@end

@implementation GZTestHook

- (instancetype)initWithIdentifier:(NSString *)identifier collections:(nullable NSArray<NSString *> *)collections {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _hookCollections = [collections copy];
    }
    return self;
}

- (NSString *)hookIdentifier {
    return self.identifier;
}

- (nullable NSArray<NSString *> *)collections {
    return self.hookCollections;
}

- (void)didIndexRecord:(NSDictionary *)record
                   uri:(NSString *)uri
                    did:(NSString *)did
            collection:(NSString *)collection {
    self.indexCallCount++;
    self.lastIndexedURI = uri;
}

- (void)didDeleteRecordWithURI:(NSString *)uri
                           did:(NSString *)did
                    collection:(NSString *)collection {
    self.deleteCallCount++;
    self.lastDeletedURI = uri;
}

@end

#pragma mark - Tests

@interface AppViewHookTests : XCTestCase
@property (nonatomic, strong) GZAppViewDatabase *database;
@end

@implementation AppViewHookTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [[GZAppViewDatabase alloc] initInMemoryWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create in-memory database: %@", error);
    BOOL migrated = [self.database runMigrations:&error];
    XCTAssertTrue(migrated, @"Failed to run migrations: %@", error);
}

- (void)tearDown {
    self.database = nil;
    [super tearDown];
}

#pragma mark - GZAppViewIndexHookRegistry

- (void)testRegistryInstantiation {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    XCTAssertNotNil(registry);
}

- (void)testRegistryStartsEmpty {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    XCTAssertEqual(registry.registeredHookCount, 0);
}

- (void)testRegistryRegisterHook {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *hook = [[GZTestHook alloc] initWithIdentifier:@"test-hook" collections:nil];
    [registry registerHook:hook];
    XCTAssertEqual(registry.registeredHookCount, 1);
}

- (void)testRegistryRegisterMultipleHooks {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:nil]];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-b" collections:nil]];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-c" collections:nil]];
    XCTAssertEqual(registry.registeredHookCount, 3);
}

- (void)testRegistryUnregisterHook {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:nil]];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-b" collections:nil]];
    [registry unregisterHook:@"hook-a"];
    XCTAssertEqual(registry.registeredHookCount, 1);
}

- (void)testRegistryUnregisterNonexistentIsNoop {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:nil]];
    [registry unregisterHook:@"hook-ghost"];
    XCTAssertEqual(registry.registeredHookCount, 1);
}

- (void)testRegistryRegisterNilHookIsNoop {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:nil];
    XCTAssertEqual(registry.registeredHookCount, 0);
}

- (void)testRegistryFireDidIndexRecordCallsMatchingHooks {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *hookA = [[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:@[@"app.bsky.feed.post"]];
    GZTestHook *hookB = [[GZTestHook alloc] initWithIdentifier:@"hook-b" collections:@[@"app.bsky.graph.follow"]];
    [registry registerHook:hookA];
    [registry registerHook:hookB];

    NSDictionary *record = @{@"text": @"hello"};
    [registry fireDidIndexRecord:record
                             uri:@"at://did:plc:x/app.bsky.feed.post/1"
                              did:@"did:plc:x"
                      collection:@"app.bsky.feed.post"];

    // Allow async dispatch
    XCTestExpectation *exp = [self expectationWithDescription:@"hooks fire"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(hookA.indexCallCount, 1);
        XCTAssertEqual(hookB.indexCallCount, 0);
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testRegistryFireDidDeleteCallsMatchingHooks {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *hookFeed = [[GZTestHook alloc] initWithIdentifier:@"hook-feed" collections:@[@"app.bsky.feed.post"]];
    [registry registerHook:hookFeed];

    [registry fireDidDeleteRecordWithURI:@"at://did:plc:x/app.bsky.feed.post/1"
                                    did:@"did:plc:x"
                             collection:@"app.bsky.feed.post"];

    XCTestExpectation *exp = [self expectationWithDescription:@"delete hook fires"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(hookFeed.deleteCallCount, 1);
        XCTAssertEqualObjects(hookFeed.lastDeletedURI, @"at://did:plc:x/app.bsky.feed.post/1");
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testRegistryFireDoesNotCallNonMatchingHooks {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *hook = [[GZTestHook alloc] initWithIdentifier:@"hook-follow" collections:@[@"app.bsky.graph.follow"]];
    [registry registerHook:hook];

    [registry fireDidIndexRecord:@{@"subject": @"did:plc:t"}
                       uri:@"at://did:plc:x/app.bsky.feed.post/1"
                        did:@"did:plc:x"
                collection:@"app.bsky.feed.post"];

    XCTestExpectation *exp = [self expectationWithDescription:@"hook not called"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(hook.indexCallCount, 0);
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testRegistryNilCollectionsHookFiresForAllCollections {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *wildcard = [[GZTestHook alloc] initWithIdentifier:@"wildcard" collections:nil];
    [registry registerHook:wildcard];

    [registry fireDidIndexRecord:@{@"text": @"hi"}
                       uri:@"at://did:plc:x/app.bsky.feed.post/1"
                        did:@"did:plc:x"
                collection:@"app.bsky.feed.post"];

    XCTestExpectation *exp = [self expectationWithDescription:@"wildcard fires"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(wildcard.indexCallCount, 1);
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

- (void)testRegistryUnregisterBeforeFireDoesNotCall {
    GZAppViewIndexHookRegistry *registry = [[GZAppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *hook = [[GZTestHook alloc] initWithIdentifier:@"ephemeral" collections:nil];
    [registry registerHook:hook];
    [registry unregisterHook:@"ephemeral"];

    [registry fireDidIndexRecord:@{@"text": @"gone"}
                       uri:@"at://did:plc:x/app.bsky.feed.post/1"
                        did:@"did:plc:x"
                collection:@"app.bsky.feed.post"];

    XCTestExpectation *exp = [self expectationWithDescription:@"unregistered hook not called"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(hook.indexCallCount, 0);
        [exp fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

#pragma mark - GZAppViewSearchIndexHook

- (void)testSearchIndexHookInstantiation {
    GZAppViewSearchIndexHook *hook = [[GZAppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertNotNil(hook);
}

- (void)testSearchIndexHookConformsToIndexHookProtocol {
    GZAppViewSearchIndexHook *hook = [[GZAppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertTrue([hook conformsToProtocol:@protocol(AppViewIndexHook)]);
}

- (void)testSearchIndexHookIdentifier {
    GZAppViewSearchIndexHook *hook = [[GZAppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertEqualObjects([hook hookIdentifier], @"search-index");
}

- (void)testSearchIndexHookCollectionsReturnsNil {
    GZAppViewSearchIndexHook *hook = [[GZAppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertNil([hook collections]);
}

- (void)testSearchIndexHookDidIndexRecordDoesNotCrash {
    GZAppViewSearchIndexHook *hook = [[GZAppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://localhost:1"];
    XCTAssertNoThrow([hook didIndexRecord:@{@"text": @"hello"}
                                uri:@"at://did:plc:x/app.bsky.feed.post/1"
                                 did:@"did:plc:x"
                         collection:@"app.bsky.feed.post"]);
}

- (void)testSearchIndexHookDidDeleteDoesNotCrash {
    GZAppViewSearchIndexHook *hook = [[GZAppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://localhost:1"];
    XCTAssertNoThrow([hook didDeleteRecordWithURI:@"at://did:plc:x/app.bsky.feed.post/1"
                                              did:@"did:plc:x"
                                       collection:@"app.bsky.feed.post"]);
}

#pragma mark - GZAppViewWebhookHook

- (void)testWebhookHookInstantiation {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"];
    XCTAssertNotNil(hook);
}

- (void)testWebhookHookInstantiationWithCollections {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"
                                                                  collections:@[@"app.bsky.feed.post"]];
    XCTAssertNotNil(hook);
}

- (void)testWebhookHookConformsToIndexHookProtocol {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"];
    XCTAssertTrue([hook conformsToProtocol:@protocol(AppViewIndexHook)]);
}

- (void)testWebhookHookIdentifierContainsURL {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://myhook.example.com/push"];
    NSString *identifier = [hook hookIdentifier];
    XCTAssertTrue([identifier hasPrefix:@"webhook-"]);
    XCTAssertTrue([identifier containsString:@"myhook.example.com"]);
}

- (void)testWebhookHookCollectionsReturnsConfiguredCollections {
    NSArray *collections = @[@"app.bsky.feed.post", @"app.bsky.graph.follow"];
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"
                                                                  collections:collections];
    XCTAssertEqualObjects([hook collections], collections);
}

- (void)testWebhookHookCollectionsReturnsNilWhenNotConfigured {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"];
    XCTAssertNil([hook collections]);
}

- (void)testWebhookHookDidIndexRecordDoesNotCrash {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://localhost:1"];
    XCTAssertNoThrow([hook didIndexRecord:@{@"text": @"hello"}
                                uri:@"at://did:plc:x/app.bsky.feed.post/1"
                                 did:@"did:plc:x"
                         collection:@"app.bsky.feed.post"]);
}

- (void)testWebhookHookDidDeleteDoesNotCrash {
    GZAppViewWebhookHook *hook = [[GZAppViewWebhookHook alloc] initWithWebhookURL:@"https://localhost:1"];
    XCTAssertNoThrow([hook didDeleteRecordWithURI:@"at://did:plc:x/app.bsky.feed.post/1"
                                              did:@"did:plc:x"
                                       collection:@"app.bsky.feed.post"]);
}

@end
