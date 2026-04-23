#import <XCTest/XCTest.h>
#import <sqlite3.h>
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"

@interface ServiceDatabasesPruningTests : XCTestCase
@property (nonatomic, strong) PDSServiceDatabases *dbs;
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation ServiceDatabasesPruningTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    self.dbs = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDir 
                                               serviceMaxSize:5 
                                             didCacheMaxSize:5 
                                           sequencerMaxSize:5];
}

- (void)tearDown {
    [self.dbs closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testPruneEvents {
    // Insert some events with manual timestamps?
    // The `persistEvent` method uses `[NSDate date]`, so we can't easily backdate without mocking or SQL.
    // We will use SQL injection via `executeSQL` (private) or just expose a helper.
    // Wait, `executeSQL` is private in .m file but we can validly use `persistEvent` if we mock NSDate or sleep?
    // Sleep is bad.
    // We can use the pool directly to insert backdated events.
    
    // We access servicePool publicly.
    PDSDatabasePool *pool = self.dbs.servicePool;
    
    // Insert OLD event (yesterday)
    NSDate *yesterday = [NSDate dateWithTimeIntervalSinceNow:-86400];
    [pool transactWithDid:@"__service__" block:^(id transactor, NSError **err) {
        // We need to execute raw SQL. PDSActorStore exposes `db` property?
        // PDSActorStore.h... let's assume we can cast to it and access db if public, or use prepareStatement.
        // `PDSActorStore` has `prepareStatement:error:`.
        id store = transactor;
        if ([store respondsToSelector:@selector(prepareStatement:error:)]) {
            // Need to cast to something that responds.
            // Using performSelector or dynamic lookup.
            // Or just assume `persistEvent` works and we modify `created_at`? No.
            
            // Let's rely on `executeSQL` being available on `ServiceDatabases`? No it's private.
            
            // Let's use `createAccount`? No, we need `events`.
            
            // Okay, let's use `dbs` private method if we can via category or KVC.
            // Or just manually insert via `sqlite3` if we can get the path.
            // `dbFilePath` is `tempDir/service/service.db`.
        }
    } error:nil];
    
    // Better approach: Use the pool transactor to insert events with manual timestamps.
    NSDate *now = [NSDate date];
    [self.dbs.sequencerPool transactWithDid:@"__service__" block:^(id transactor, NSError **err) {
        PDSActorStore *store = (PDSActorStore *)transactor;
        sqlite3 *db = store.db;
        
        char *errMsg = NULL;
        NSString *sql = [NSString stringWithFormat:@"INSERT INTO events (seq, event_type, event_data, created_at) VALUES (1, 'test', 'data', %f)", yesterday.timeIntervalSince1970];
        if (sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
            XCTFail(@"Failed to insert old event: %s", errMsg);
            sqlite3_free(errMsg);
        }

        NSString *sql2 = [NSString stringWithFormat:@"INSERT INTO events (seq, event_type, event_data, created_at) VALUES (2, 'test', 'data', %f)", now.timeIntervalSince1970];
        if (sqlite3_exec(db, sql2.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
            XCTFail(@"Failed to insert new event: %s", errMsg);
            sqlite3_free(errMsg);
        }
    } error:nil];
    
    // Verify count is 2
    NSArray *events = [self.dbs getEventsSince:0 limit:10 error:nil];
    XCTAssertEqual(events.count, 2);
    
    // Prune events older than 1 hour ago
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-3600];
    NSError *error = nil;
    BOOL success = [self.dbs pruneEventsBefore:cutoff error:&error];
    
    XCTAssertTrue(success, @"Pruning failed: %@", error);
    
    // Verify count is 1
    events = [self.dbs getEventsSince:0 limit:10 error:nil];
    XCTAssertEqual(events.count, 1);
    XCTAssertEqual([events.firstObject[@"seq"] intValue], 2);
}

@end
