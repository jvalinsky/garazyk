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
@property (nonatomic, strong) AppViewDatabase *database;
@end

@implementation AppViewHookTests

- (void)setUp {
    [super setUp];
    NSError *error = nil;
    self.database = [[AppViewDatabase alloc] initInMemoryWithError:&error];
    XCTAssertNotNil(self.database, @"Failed to create in-memory database: %@", error);
    BOOL migrated = [self.database runMigrations:&error];
    XCTAssertTrue(migrated, @"Failed to run migrations: %@", error);
}

- (void)tearDown {
    self.database = nil;
    [super tearDown];
}

#pragma mark - AppViewIndexHookRegistry

- (void)testRegistryInstantiation {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    XCTAssertNotNil(registry);
}

- (void)testRegistryStartsEmpty {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    XCTAssertEqual(registry.registeredHookCount, 0);
}

- (void)testRegistryRegisterHook {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    GZTestHook *hook = [[GZTestHook alloc] initWithIdentifier:@"test-hook" collections:nil];
    [registry registerHook:hook];
    XCTAssertEqual(registry.registeredHookCount, 1);
}

- (void)testRegistryRegisterMultipleHooks {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:nil]];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-b" collections:nil]];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-c" collections:nil]];
    XCTAssertEqual(registry.registeredHookCount, 3);
}

- (void)testRegistryUnregisterHook {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:nil]];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-b" collections:nil]];
    [registry unregisterHook:@"hook-a"];
    XCTAssertEqual(registry.registeredHookCount, 1);
}

- (void)testRegistryUnregisterNonexistentIsNoop {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:[[GZTestHook alloc] initWithIdentifier:@"hook-a" collections:nil]];
    [registry unregisterHook:@"hook-ghost"];
    XCTAssertEqual(registry.registeredHookCount, 1);
}

- (void)testRegistryRegisterNilHookIsNoop {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
    [registry registerHook:nil];
    XCTAssertEqual(registry.registeredHookCount, 0);
}

- (void)testRegistryFireDidIndexRecordCallsMatchingHooks {
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
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
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
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
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
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
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
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
    AppViewIndexHookRegistry *registry = [[AppViewIndexHookRegistry alloc] initWithDatabase:self.database];
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

#pragma mark - AppViewSearchIndexHook

- (void)testSearchIndexHookInstantiation {
    AppViewSearchIndexHook *hook = [[AppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertNotNil(hook);
}

- (void)testSearchIndexHookConformsToIndexHookProtocol {
    AppViewSearchIndexHook *hook = [[AppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertTrue([hook conformsToProtocol:@protocol(AppViewIndexHook)]);
}

- (void)testSearchIndexHookIdentifier {
    AppViewSearchIndexHook *hook = [[AppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertEqualObjects([hook hookIdentifier], @"search-index");
}

- (void)testSearchIndexHookCollectionsReturnsNil {
    AppViewSearchIndexHook *hook = [[AppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://search.example.com"];
    XCTAssertNil([hook collections]);
}

- (void)testSearchIndexHookDidIndexRecordDoesNotCrash {
    AppViewSearchIndexHook *hook = [[AppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://localhost:1"];
    XCTAssertNoThrow([hook didIndexRecord:@{@"text": @"hello"}
                                uri:@"at://did:plc:x/app.bsky.feed.post/1"
                                 did:@"did:plc:x"
                         collection:@"app.bsky.feed.post"]);
}

- (void)testSearchIndexHookDidDeleteDoesNotCrash {
    AppViewSearchIndexHook *hook = [[AppViewSearchIndexHook alloc] initWithSearchEndpoint:@"https://localhost:1"];
    XCTAssertNoThrow([hook didDeleteRecordWithURI:@"at://did:plc:x/app.bsky.feed.post/1"
                                              did:@"did:plc:x"
                                       collection:@"app.bsky.feed.post"]);
}

#pragma mark - AppViewWebhookHook

- (void)testWebhookHookInstantiation {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"];
    XCTAssertNotNil(hook);
}

- (void)testWebhookHookInstantiationWithCollections {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"
                                                                  collections:@[@"app.bsky.feed.post"]];
    XCTAssertNotNil(hook);
}

- (void)testWebhookHookConformsToIndexHookProtocol {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"];
    XCTAssertTrue([hook conformsToProtocol:@protocol(AppViewIndexHook)]);
}

- (void)testWebhookHookIdentifierContainsURL {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://myhook.example.com/push"];
    NSString *identifier = [hook hookIdentifier];
    XCTAssertTrue([identifier hasPrefix:@"webhook-"]);
    XCTAssertTrue([identifier containsString:@"myhook.example.com"]);
}

- (void)testWebhookHookCollectionsReturnsConfiguredCollections {
    NSArray *collections = @[@"app.bsky.feed.post", @"app.bsky.graph.follow"];
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"
                                                                  collections:collections];
    XCTAssertEqualObjects([hook collections], collections);
}

- (void)testWebhookHookCollectionsReturnsNilWhenNotConfigured {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://webhook.example.com"];
    XCTAssertNil([hook collections]);
}

- (void)testWebhookHookDidIndexRecordDoesNotCrash {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://localhost:1"];
    XCTAssertNoThrow([hook didIndexRecord:@{@"text": @"hello"}
                                uri:@"at://did:plc:x/app.bsky.feed.post/1"
                                 did:@"did:plc:x"
                         collection:@"app.bsky.feed.post"]);
}

- (void)testWebhookHookDidDeleteDoesNotCrash {
    AppViewWebhookHook *hook = [[AppViewWebhookHook alloc] initWithWebhookURL:@"https://localhost:1"];
    XCTAssertNoThrow([hook didDeleteRecordWithURI:@"at://did:plc:x/app.bsky.feed.post/1"
                                              did:@"did:plc:x"
                                       collection:@"app.bsky.feed.post"]);
}

@end
