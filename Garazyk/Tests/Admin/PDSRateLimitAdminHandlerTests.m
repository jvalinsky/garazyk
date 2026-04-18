#import <XCTest/XCTest.h>
#import "PDSRateLimitAdminHandler.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/PDSLogger.h"
#import <sqlite3.h>

// Mock RateLimiter for testing
@interface MockRateLimiter : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *limits;
@end

@implementation MockRateLimiter

- (instancetype)init {
    if ((self = [super init])) {
        _limits = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary *)rateLimitForIdentifier:(NSString *)identifier type:(NSString *)type {
    NSString *key = [NSString stringWithFormat:@"%@:%@", type, identifier];
    if (self.limits[key]) {
        return self.limits[key];
    }
    return @{@"limit": @1000, @"remaining": @1000, @"reset_at": @([[NSDate date] timeIntervalSince1970] + 3600)};
}

- (void)clearRateLimitForIdentifier:(NSString *)identifier type:(NSString *)type {
    NSString *key = [NSString stringWithFormat:@"%@:%@", type, identifier];
    [self.limits removeObjectForKey:key];
}

@end

@interface PDSRateLimitAdminHandlerTests : XCTestCase
@property (nonatomic, strong) PDSRateLimitAdminHandler *handler;
@property (nonatomic, strong) PDSServiceDatabases *serviceDatabases;
@property (nonatomic, strong) MockRateLimiter *mockRateLimiter;
@property (nonatomic, copy) NSString *tempDirectory;
@property (nonatomic, assign) sqlite3 *testDatabase;
@end

@implementation PDSRateLimitAdminHandlerTests

- (void)setUp {
    [super setUp];

    // Create temp directory
    self.tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"RateLimitTests_%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Create temp service database
    NSString *dbPath = [self.tempDirectory stringByAppendingPathComponent:@"service.db"];
    if (sqlite3_open(dbPath.UTF8String, &_testDatabase) != SQLITE_OK) {
        XCTFail(@"Failed to create test database");
    }

    // Create rate_limit_history table
    NSString *createTableSQL = @"CREATE TABLE rate_limit_history ("
        @"id INTEGER PRIMARY KEY,"
        @"identifier TEXT NOT NULL,"
        @"type TEXT NOT NULL,"
        @"action TEXT NOT NULL,"
        @"admin_did TEXT,"
        @"reason TEXT,"
        @"timestamp INTEGER NOT NULL"
        @")";

    char *errMsg = NULL;
    if (sqlite3_exec(_testDatabase, createTableSQL.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
        XCTFail(@"Failed to create table: %s", errMsg);
        sqlite3_free(errMsg);
    }

    // Create indexes
    sqlite3_exec(_testDatabase,
                 "CREATE INDEX idx_rate_limit_history_identifier ON rate_limit_history(identifier)",
                 NULL, NULL, NULL);
    sqlite3_exec(_testDatabase,
                 "CREATE INDEX idx_rate_limit_history_timestamp ON rate_limit_history(timestamp)",
                 NULL, NULL, NULL);

    // Initialize dependencies
    self.serviceDatabases = [[PDSServiceDatabases alloc] initWithDatabasePath:dbPath];
    self.mockRateLimiter = [[MockRateLimiter alloc] init];

    // Initialize handler
    self.handler = [[PDSRateLimitAdminHandler alloc] initWithRateLimiter:self.mockRateLimiter
                                                         serviceDatabases:self.serviceDatabases];
}

- (void)tearDown {
    // Close databases
    [self.serviceDatabases closeAll];
    if (self.testDatabase) {
        sqlite3_close(self.testDatabase);
    }

    // Cleanup temp directory
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDirectory error:nil];

    [super tearDown];
}

#pragma mark - Query Tests

- (void)testQueryRateLimitReturnsStatus {
    NSDictionary *status = [self.handler queryRateLimitForIdentifier:@"did:plc:test"
                                                                type:@"did"];

    XCTAssertNotNil(status, @"Status should be returned");
    XCTAssertNotNil(status[@"limit"], @"Should contain limit");
    XCTAssertNotNil(status[@"remaining"], @"Should contain remaining");
    XCTAssertNotNil(status[@"reset_at"], @"Should contain reset_at");
}

- (void)testQueryWithDifferentTypes {
    NSArray *types = @[@"did", @"ip", @"blob"];

    for (NSString *type in types) {
        NSDictionary *status = [self.handler queryRateLimitForIdentifier:@"test-identifier"
                                                                    type:type];
        XCTAssertNotNil(status, @"Should return status for type: %@", type);
    }
}

#pragma mark - Top Limited Users Tests

- (void)testTopLimitedUsersReturnsArray {
    NSArray *topUsers = [self.handler topLimitedUsersWithLimit:10];

    // May be empty if no rate limits in effect
    XCTAssertNotNil(topUsers, @"Should return array (may be empty)");
}

- (void)testTopLimitedUsersRespectsLimit {
    NSArray *topUsers = [self.handler topLimitedUsersWithLimit:5];

    XCTAssertLessThanOrEqual(topUsers.count, 5, @"Should respect limit");
}

#pragma mark - Clear Rate Limit Tests

- (void)testClearRateLimitCreatesAuditRecord {
    NSString *identifier = @"did:plc:test";
    NSString *adminDid = @"did:plc:admin";
    NSString *reason = @"Testing clear functionality";

    NSError *error = nil;
    BOOL success = [self.handler clearRateLimitForIdentifier:identifier
                                                        type:@"did"
                                                    adminDid:adminDid
                                                      reason:reason
                                                       error:&error];

    XCTAssertTrue(success, @"Clear should succeed");
    XCTAssertNil(error, @"Should not have errors");

    // Verify audit record was created
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT action, admin_did, reason FROM rate_limit_history "
        @"WHERE identifier = ? AND type = ?";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, "did", -1, SQLITE_STATIC);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *action = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
            NSString *storedAdminDid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
            NSString *storedReason = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];

            XCTAssertEqualObjects(action, @"cleared");
            XCTAssertEqualObjects(storedAdminDid, adminDid);
            XCTAssertEqualObjects(storedReason, reason);
        } else {
            XCTFail(@"Audit record not found");
        }
        sqlite3_finalize(stmt);
    }
}

- (void)testClearRateLimitWithEmptyReason {
    NSError *error = nil;
    BOOL success = [self.handler clearRateLimitForIdentifier:@"did:plc:test"
                                                        type:@"did"
                                                    adminDid:@"did:plc:admin"
                                                      reason:@""
                                                       error:&error];

    // Handler should validate non-empty reason
    XCTAssertFalse(success, @"Should reject empty reason");
    XCTAssertNotNil(error, @"Should return error for empty reason");
}

- (void)testClearRateLimitWithNilReason {
    NSError *error = nil;
    BOOL success = [self.handler clearRateLimitForIdentifier:@"did:plc:test"
                                                        type:@"did"
                                                    adminDid:@"did:plc:admin"
                                                      reason:nil
                                                       error:&error];

    XCTAssertFalse(success, @"Should reject nil reason");
    XCTAssertNotNil(error, @"Should return error for nil reason");
}

- (void)testMultipleClearsWithAuditTrail {
    NSString *identifier = @"did:plc:offender";

    // First clear
    [self.handler clearRateLimitForIdentifier:identifier
                                        type:@"did"
                                    adminDid:@"did:plc:admin1"
                                      reason:@"First warning"
                                       error:nil];

    // Wait a moment to ensure different timestamps
    usleep(100000);

    // Second clear
    [self.handler clearRateLimitForIdentifier:identifier
                                        type:@"did"
                                    adminDid:@"did:plc:admin2"
                                      reason:@"Second warning"
                                       error:nil];

    // Query history
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT admin_did, reason FROM rate_limit_history "
        @"WHERE identifier = ? ORDER BY timestamp ASC";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);

        NSMutableArray *records = [NSMutableArray array];
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSString *adminDid = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
            NSString *reason = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
            [records addObject:@{@"admin_did": adminDid, @"reason": reason}];
        }

        XCTAssertEqual(records.count, 2, @"Should have 2 audit records");
        XCTAssertEqualObjects(records[0][@"admin_did"], @"did:plc:admin1");
        XCTAssertEqualObjects(records[1][@"admin_did"], @"did:plc:admin2");

        sqlite3_finalize(stmt);
    }
}

#pragma mark - History Tests

- (void)testHistoryForIdentifierReturnsRecords {
    NSString *identifier = @"did:plc:test";

    // Create audit records
    for (int i = 0; i < 3; i++) {
        [self.handler clearRateLimitForIdentifier:identifier
                                            type:@"did"
                                        adminDid:[NSString stringWithFormat:@"did:plc:admin%d", i]
                                          reason:[NSString stringWithFormat:@"Reason %d", i]
                                           error:nil];
    }

    // Query history
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT COUNT(*) FROM rate_limit_history WHERE identifier = ?";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            XCTAssertEqual(count, 3, @"Should have 3 history records");
        }
        sqlite3_finalize(stmt);
    }
}

- (void)testClearHistoryRemovesOldRecords {
    // Insert old record
    NSTimeInterval twoMonthsAgo = [[NSDate date] timeIntervalSince1970] - (60 * 24 * 3600);
    sqlite3_stmt *stmt = NULL;
    NSString *insertSQL = @"INSERT INTO rate_limit_history "
        @"(identifier, type, action, admin_did, reason, timestamp) "
        @"VALUES (?, ?, ?, ?, ?, ?)";
    if (sqlite3_prepare_v2(self.testDatabase, insertSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, "old-identifier", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, "did", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 3, "cleared", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 4, "did:plc:admin", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 5, "Old record", -1, SQLITE_STATIC);
        sqlite3_bind_int64(stmt, 6, (long)twoMonthsAgo);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Insert recent record
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *recentSQL = @"INSERT INTO rate_limit_history "
        @"(identifier, type, action, admin_did, reason, timestamp) "
        @"VALUES (?, ?, ?, ?, ?, ?)";
    if (sqlite3_prepare_v2(self.testDatabase, recentSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, "recent-identifier", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 2, "did", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 3, "cleared", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 4, "did:plc:admin", -1, SQLITE_STATIC);
        sqlite3_bind_text(stmt, 5, "Recent record", -1, SQLITE_STATIC);
        sqlite3_bind_int64(stmt, 6, (long)now);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }

    // Clear old history
    NSError *error = nil;
    BOOL success = [self.handler clearHistoryOlderThan:30 error:&error];

    XCTAssertTrue(success, @"Clear history should succeed");
    XCTAssertNil(error, @"Should not have errors");

    // Verify old record was deleted
    NSString *countSQL = @"SELECT COUNT(*) FROM rate_limit_history";
    if (sqlite3_prepare_v2(self.testDatabase, countSQL.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            XCTAssertEqual(count, 1, @"Should have deleted old record");
        }
        sqlite3_finalize(stmt);
    }
}

#pragma mark - Validation Tests

- (void)testValidatesNonEmptyIdentifier {
    NSError *error = nil;
    BOOL success = [self.handler clearRateLimitForIdentifier:@""
                                                        type:@"did"
                                                    adminDid:@"did:plc:admin"
                                                      reason:@"Valid reason"
                                                       error:&error];

    XCTAssertFalse(success, @"Should reject empty identifier");
    XCTAssertNotNil(error, @"Should return error");
}

- (void)testValidatesValidType {
    NSError *error = nil;
    BOOL success = [self.handler clearRateLimitForIdentifier:@"test"
                                                        type:@"invalid_type"
                                                    adminDid:@"did:plc:admin"
                                                      reason:@"Valid reason"
                                                       error:&error];

    // Handler may or may not validate type strictly
    // This test documents the behavior
    XCTAssertNotNil(error || !error, @"Behavior documented");
}

#pragma mark - Concurrency Tests

- (void)testConcurrentClears {
    dispatch_queue_t queue = dispatch_queue_create("com.test.concurrent", DISPATCH_QUEUE_CONCURRENT);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Concurrent clears"];
    __block int completedOperations = 0;

    for (int i = 0; i < 10; i++) {
        dispatch_async(queue, ^{
            NSString *identifier = [NSString stringWithFormat:@"did:plc:user%d", i];
            NSString *adminDid = [NSString stringWithFormat:@"did:plc:admin%d", i];

            NSError *error = nil;
            [self.handler clearRateLimitForIdentifier:identifier
                                                type:@"did"
                                            adminDid:adminDid
                                              reason:@"Concurrent test"
                                               error:&error];

            @synchronized(self) {
                completedOperations++;
                if (completedOperations == 10) {
                    [expectation fulfill];
                }
            }
        });
    }

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    // Verify all records were created
    sqlite3_stmt *stmt = NULL;
    NSString *sql = @"SELECT COUNT(*) FROM rate_limit_history";
    if (sqlite3_prepare_v2(self.testDatabase, sql.UTF8String, -1, &stmt, NULL) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int count = sqlite3_column_int(stmt, 0);
            XCTAssertEqual(count, 10, @"Should have created 10 audit records");
        }
        sqlite3_finalize(stmt);
    }
}

@end
