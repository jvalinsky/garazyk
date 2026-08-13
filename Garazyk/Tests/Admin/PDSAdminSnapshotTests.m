// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

#import "Admin/AdminUI/PDSAdminSnapshot.h"
#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"

NS_ASSUME_NONNULL_BEGIN

@interface GZFakePDSAdminStatsSource : NSObject
@property (nonatomic, copy) NSDictionary *stats;
@end

@implementation GZFakePDSAdminStatsSource
- (nullable NSDictionary *)getServerStatsWithError:(NSError * _Nullable * _Nullable)error {
    (void)error;
    return self.stats;
}
@end

@interface PDSAdminSnapshotTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong, nullable) PDSDatabase *database;
@property (nonatomic, strong, nullable) PDSDatabasePool *pool;
@end

@implementation PDSAdminSnapshotTests

- (void)setUp {
    [super setUp];
    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"service.sqlite"];
    self.database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"%@", error);

    [self.database executeParameterizedUpdate:
     @"CREATE TABLE IF NOT EXISTS refresh_tokens ("
     @"token TEXT PRIMARY KEY, account_did TEXT NOT NULL,"
     @"session_id TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL,"
     @"expires_at REAL NOT NULL, next_token TEXT DEFAULT NULL)"
                                      params:@[]
                                       error:nil];

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [self.database executeParameterizedUpdate:
     @"INSERT INTO refresh_tokens (token, account_did, session_id, created_at, expires_at) "
     @"VALUES (?, ?, ?, ?, ?)"
                                      params:@[@"tok1", @"did:plc:a", @"sess1", @(now), @(now + 3600)]
                                       error:nil];
    [self.database executeParameterizedUpdate:
     @"INSERT INTO refresh_tokens (token, account_did, session_id, created_at, expires_at, next_token) "
     @"VALUES (?, ?, ?, ?, ?, ?)"
                                      params:@[@"tok2", @"did:plc:a", @"sess2", @(now), @(now + 3600), @"tok3"]
                                       error:nil];

    NSString *poolDir = [self.testDirectory stringByAppendingPathComponent:@"actors"];
    [[NSFileManager defaultManager] createDirectoryAtPath:poolDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:poolDir maxSize:8];
}

- (void)tearDown {
    [self.database close];
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

- (void)testSnapshotIncludesHealthSessionsPoolAndDatabaseWithoutStoresMap {
    GZFakePDSAdminStatsSource *stats = [[GZFakePDSAdminStatsSource alloc] init];
    stats.stats = @{
        @"accounts_total": @1,
        @"repos_total": @1,
        @"records_total": @0,
        @"blobs_total": @0,
        @"blobs_size_bytes": @0,
        @"reports_open": @0,
    };

    GZPDSAdminSnapshot *snap =
        [[GZPDSAdminSnapshot alloc] initWithDatabase:self.database
                                     adminStatsSource:stats
                                     userDatabasePool:self.pool
                                     serviceDatabases:nil
                               subscribeReposHandler:nil
                                            startedAt:[NSDate dateWithTimeIntervalSinceNow:-30]];
    NSDictionary *value = [snap snapshot];
    XCTAssertEqualObjects(value[@"health"], @"ok");
    XCTAssertGreaterThanOrEqual([value[@"uptimeSeconds"] longLongValue], 29);
    XCTAssertEqualObjects(value[@"accounts_total"], @1);
    XCTAssertEqualObjects(value[@"sessions_active"], @1);

    NSDictionary *pool = value[@"pool"];
    XCTAssertEqualObjects(pool[@"maxSize"], @8);
    XCTAssertEqualObjects(pool[@"cachedStores"], @0);
    XCTAssertNil(pool[@"stores"], @"Must not expose per-DID pool inventory on overview poll");

    NSDictionary *database = value[@"database"];
    XCTAssertTrue([database[@"storageBytes"] longLongValue] > 0);
    XCTAssertNotNil(database[@"journalMode"]);

    NSDictionary *sequencer = value[@"sequencer"];
    XCTAssertNotNil(sequencer[@"healthStatus"]);
}

- (void)testRenderServerStatsPartialIncludesSnapshotSections {
    NSDictionary *result = @{
        @"health": @"ok",
        @"uptimeSeconds": @12,
        @"accounts_total": @3,
        @"repos_total": @2,
        @"records_total": @10,
        @"blobs_total": @1,
        @"blobs_size_bytes": @100,
        @"reports_open": @0,
        @"sessions_active": @4,
        @"httpRequestsPerSecond": @1.5,
        @"sequencer": @{@"currentSeq": @99, @"subscriberCount": @2, @"healthStatus": @"healthy"},
        @"pool": @{@"cachedStores": @1, @"maxSize": @8, @"openFileHandles": @1},
        @"database": @{@"storageBytes": @(1024 * 1024), @"journalMode": @"wal"},
    };
    NSString *html = [GZAdminUIPDSPack renderServerStatsPartial:result];
    XCTAssertTrue([html containsString:@"Health"]);
    XCTAssertTrue([html containsString:@"Active sessions"]);
    XCTAssertTrue([html containsString:@"Sequencer head"]);
    XCTAssertTrue([html containsString:@"Actor DB pool"]);
    XCTAssertTrue([html containsString:@"Service DB"]);
    XCTAssertTrue([html containsString:@"wal"]);
}

@end

NS_ASSUME_NONNULL_END
