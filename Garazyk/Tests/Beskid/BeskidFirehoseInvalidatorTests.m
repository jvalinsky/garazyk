// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Beskid/BeskidConfiguration.h"
#import "Beskid/BeskidDatabase.h"
#import "Beskid/BeskidFirehoseInvalidator.h"
#import "Beskid/BeskidMetrics.h"
#import "Sync/Firehose/Firehose.h"

static NSString *BeskidInvalidatorTestDBPath(NSString *name) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"garazyk-beskid-invalidator-%@-%@", name, NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                     error:nil];
    return [dir stringByAppendingPathComponent:@"test.db"];
}

static GZBeskidDatabase *BeskidInvalidatorOpenDB(XCTestCase *testCase) {
    NSError *error = nil;
    GZBeskidDatabase *db = [[GZBeskidDatabase alloc] initWithPath:BeskidInvalidatorTestDBPath(testCase.name)
                                                            error:&error];
    XCTAssertNotNil(db, @"open db: %@", error);
    XCTAssertTrue([db runMigrations:&error], @"migrate db: %@", error);
    return db;
}

static GZBeskidFirehoseInvalidator *BeskidMakeInvalidator(GZBeskidDatabase *db, GZBeskidMetrics *metrics) {
    GZBeskidConfiguration *config = [GZBeskidConfiguration defaultConfiguration];
    config.firehoseEnabled = YES;
    config.firehoseURL = @"ws://127.0.0.1:2587";
    return [[GZBeskidFirehoseInvalidator alloc] initWithDatabase:db metrics:metrics configuration:config];
}

@interface BeskidFirehoseInvalidatorTests : XCTestCase
@property (nonatomic, strong) GZBeskidDatabase *db;
@property (nonatomic, strong) GZBeskidMetrics *metrics;
@property (nonatomic, strong) GZBeskidFirehoseInvalidator *invalidator;
@end

@implementation BeskidFirehoseInvalidatorTests

- (void)setUp {
    [super setUp];
    self.db = BeskidInvalidatorOpenDB(self);
    self.metrics = [[GZBeskidMetrics alloc] init];
    self.db.metrics = self.metrics;
    self.invalidator = BeskidMakeInvalidator(self.db, self.metrics);
}

- (void)tearDown {
    [self.db close];
    self.invalidator = nil;
    self.metrics = nil;
    self.db = nil;
    [super tearDown];
}

- (void)testCommitEventInvalidatesKnownRecordKey {
    NSError *error = nil;
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": @"cached"};
    XCTAssertTrue([self.db saveRecord:record
                                  did:@"did:plc:alice"
                           collection:@"app.bsky.feed.post"
                                 rkey:@"3jzfc2jmkm7s2"
                                  cid:@"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"
                                  ttl:3600
                                error:&error], @"seed record: %@", error);

    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:alice";
    event.seq = 42;
    event.ops = @[@{@"action": @"update", @"path": @"app.bsky.feed.post/3jzfc2jmkm7s2"}];
    [self.invalidator handleCommitEvent:event];

    NSDictionary *cached = [self.db recordByURI:@"at://did:plc:alice/app.bsky.feed.post/3jzfc2jmkm7s2"
                                            cid:nil
                                          error:nil];
    XCTAssertNil(cached);
    NSDictionary *snapshot = [self.metrics snapshotDictionary];
    XCTAssertEqual([snapshot[@"firehose"][@"invalidationsCommit"] longLongValue], 1);
    XCTAssertEqual([snapshot[@"firehose"][@"receivedCommit"] longLongValue], 1);
    XCTAssertEqual([snapshot[@"firehose"][@"appliedPrecise"] longLongValue], 1);
    XCTAssertGreaterThanOrEqual([snapshot[@"firehose"][@"purgeLatencyMaxMs"] longLongValue], (int64_t)0);
}

- (void)testCommitEventConservativeFallbackDeletesAllRecordsForDID {
    NSError *error = nil;
    NSDictionary *record = @{@"$type": @"app.bsky.feed.post", @"text": @"one"};
    XCTAssertTrue([self.db saveRecord:record
                                  did:@"did:plc:bob"
                           collection:@"app.bsky.feed.post"
                                 rkey:@"abc"
                                  cid:@"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"
                                  ttl:3600
                                error:&error]);
    XCTAssertTrue([self.db saveRecord:@{@"text": @"two"}
                                  did:@"did:plc:bob"
                           collection:@"app.bsky.feed.like"
                                 rkey:@"def"
                                  cid:@"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"
                                  ttl:3600
                                error:&error]);

    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = @"did:plc:bob";
    event.seq = 7;
    event.ops = @[@{@"action": @"update"}];
    [self.invalidator handleCommitEvent:event];

    XCTAssertNil([self.db recordByURI:@"at://did:plc:bob/app.bsky.feed.post/abc" cid:nil error:nil]);
    XCTAssertNil([self.db recordByURI:@"at://did:plc:bob/app.bsky.feed.like/def" cid:nil error:nil]);
    NSDictionary *snapshot = [self.metrics snapshotDictionary];
    XCTAssertEqual([snapshot[@"firehose"][@"appliedFallback"] longLongValue], 1);
    XCTAssertEqual([snapshot[@"firehose"][@"receivedCommit"] longLongValue], 1);
}

- (void)testIdentityEventDeletesCachedIdentity {
    NSError *error = nil;
    XCTAssertTrue([self.db saveIdentity:@"did:plc:carol"
                                 handle:@"carol.test"
                            pdsEndpoint:@"https://pds.example"
                             signingKey:@"key"
                            rawDocument:@{@"id": @"did:plc:carol"}
                                    ttl:86400
                                  error:&error]);

    ATProtoFirehoseIdentityEvent *event = [ATProtoFirehoseIdentityEvent eventWithDid:@"did:plc:carol"];
    event.seq = 99;
    [self.invalidator handleIdentityEvent:event];

    XCTAssertNil([self.db identityForDID:@"did:plc:carol" error:nil]);
    NSDictionary *snapshot = [self.metrics snapshotDictionary];
    XCTAssertEqual([snapshot[@"firehose"][@"invalidationsIdentity"] longLongValue], 1);
}

- (void)testAccountTakedownPurgesRecordsAndIdentity {
    NSError *error = nil;
    XCTAssertTrue([self.db saveRecord:@{@"text": @"stale"}
                                  did:@"did:plc:dave"
                           collection:@"app.bsky.feed.post"
                                 rkey:@"xyz"
                                  cid:@"bafyreifzjut3te2nhyekklss27nh3k72ysco7y32koao5eei66wof36n5e"
                                  ttl:3600
                                error:&error]);
    XCTAssertTrue([self.db saveIdentity:@"did:plc:dave"
                                 handle:@"dave.test"
                            pdsEndpoint:@"https://pds.example"
                             signingKey:@"key"
                            rawDocument:@{@"id": @"did:plc:dave"}
                                    ttl:86400
                                  error:&error]);

    ATProtoFirehoseAccountEvent *event = [ATProtoFirehoseAccountEvent eventWithDid:@"did:plc:dave"
                                                                            active:NO
                                                                            status:@"takendown"];
    event.seq = 100;
    [self.invalidator handleAccountEvent:event];

    XCTAssertNil([self.db recordByURI:@"at://did:plc:dave/app.bsky.feed.post/xyz" cid:nil error:nil]);
    XCTAssertNil([self.db identityForDID:@"did:plc:dave" error:nil]);
    NSDictionary *snapshot = [self.metrics snapshotDictionary];
    XCTAssertEqual([snapshot[@"firehose"][@"invalidationsAccount"] longLongValue], 1);
}

- (void)testCommitInvalidationThenReseedServesUpdatedRecord {
    NSError *error = nil;
    NSString *did = @"did:plc:erin";
    NSString *collection = @"app.bsky.feed.post";
    NSString *rkey = @"3jzfc2jmkm7s2";
    NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    NSString *path = [NSString stringWithFormat:@"%@/%@", collection, rkey];
    NSDictionary *stale = @{@"$type": collection, @"text": @"stale"};
    NSDictionary *fresh = @{@"$type": collection, @"text": @"fresh"};

    XCTAssertTrue([self.db saveRecord:stale
                                  did:did
                           collection:collection
                                 rkey:rkey
                                  cid:@"bafyreistale000000000000000000000000000000000000000000000000"
                                  ttl:3600
                                error:&error], @"seed stale: %@", error);

    ATProtoFirehoseCommitEvent *event = [[ATProtoFirehoseCommitEvent alloc] init];
    event.repo = did;
    event.seq = 50;
    event.ops = @[@{@"action": @"update", @"path": path}];
    [self.invalidator handleCommitEvent:event];

    NSDictionary *afterInvalidate = [self.db recordByURI:uri cid:nil error:nil];
    XCTAssertNil(afterInvalidate);

    XCTAssertTrue([self.db saveRecord:fresh
                                  did:did
                           collection:collection
                                 rkey:rkey
                                  cid:@"bafyreifresh000000000000000000000000000000000000000000000000"
                                  ttl:3600
                                error:&error], @"reseed fresh: %@", error);
    NSDictionary *cached = [self.db recordByURI:uri cid:nil error:nil];
    XCTAssertNotNil(cached);
    XCTAssertEqualObjects(cached[@"value"][@"text"], @"fresh");
}

- (void)testFirehoseDisabledByDefault {
    GZBeskidConfiguration *config = [GZBeskidConfiguration defaultConfiguration];
    XCTAssertFalse(config.firehoseEnabled);
    XCTAssertEqualObjects(config.firehoseURL, @"ws://127.0.0.1:2587");
}

@end
