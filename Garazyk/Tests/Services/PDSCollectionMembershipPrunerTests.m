// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSCollectionMembershipPruner.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Services/PDS/PDSRecordService.h"

@interface PDSCollectionMembershipPrunerTests : XCTestCase
@property (nonatomic, copy) NSString *tempDir;
@property (nonatomic, strong) PDSServiceDatabases *sdb;
@property (nonatomic, strong) PDSDatabasePool *pool;
@end

@implementation PDSCollectionMembershipPrunerTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    self.sdb = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDir
                                               serviceMaxSize:5
                                             didCacheMaxSize:5
                                           sequencerMaxSize:5];
    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.tempDir maxSize:5];
}

- (void)tearDown {
    [self.sdb closeAll];
    [self.pool closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testPruneNowRemovesStaleEntries {
    NSString *collection = @"app.bsky.feed.post";
    NSString *activeDid = @"did:web:active.example.com";
    NSString *staleDid = @"did:web:stale.example.com";

    // Upsert both DIDs into the collection_membership index.
    NSError *error = nil;
    XCTAssertTrue([self.sdb upsertCollectionMembership:collection forDID:activeDid error:&error], @"Failed upserting activeDid: %@", error);
    XCTAssertTrue([self.sdb upsertCollectionMembership:collection forDID:staleDid error:&error], @"Failed upserting staleDid: %@", error);
    XCTAssertEqual([self.sdb collectionMembershipCountWithError:&error], 2);

    // Create actor store and record for activeDid so hasRecordsForCollection: returns YES.
    PDSActorStore *store = [self.pool storeForDid:activeDid error:&error];
    XCTAssertNotNil(store, @"Failed to create actor store: %@", error);
    PDSRecordService *recordService = [[PDSRecordService alloc] initWithDatabasePool:self.pool];
    recordService.serviceDatabases = self.sdb;
    
    NSDictionary *record = @{@"$type": collection, @"text": @"Hello active world", @"createdAt": [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]]};
    XCTAssertTrue([recordService putRecord:collection
                                      rkey:@"post1"
                                     value:record
                                    forDid:activeDid
                            validationMode:PDSValidationModeOff
                                     error:&error], @"Failed putting record: %@", error);

    // Initialize pruner and trigger pruneNow.
    PDSCollectionMembershipPruner *pruner = [[PDSCollectionMembershipPruner alloc] initWithServiceDatabases:self.sdb
                                                                                           userDatabasePool:self.pool
                                                                                          intervalInSeconds:300.0];
    XCTAssertNotNil(pruner);
    [pruner pruneNow];

    // Since pruneNow runs asynchronously on its internal queue, wait for it using an expectation with a predicate or block.
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        NSInteger count = [self.sdb collectionMembershipCountWithError:nil];
        return count == 1;
    }];
    [self expectationForPredicate:predicate evaluatedWithObject:self.sdb handler:nil];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    NSArray<NSString *> *remainingDIDs = [self.sdb listDIDsByCollection:collection cursor:nil limit:10 error:&error];
    XCTAssertEqual(remainingDIDs.count, 1);
    XCTAssertEqualObjects(remainingDIDs.firstObject, activeDid);
}

- (void)testPrunerStartAndStopLifecycle {
    NSString *collection = @"app.bsky.feed.post";
    NSString *staleDid = @"did:web:stale-lifecycle.example.com";

    NSError *error = nil;
    XCTAssertTrue([self.sdb upsertCollectionMembership:collection forDID:staleDid error:&error]);
    XCTAssertEqual([self.sdb collectionMembershipCountWithError:&error], 1);

    PDSCollectionMembershipPruner *pruner = [[PDSCollectionMembershipPruner alloc] initWithServiceDatabases:self.sdb
                                                                                           userDatabasePool:self.pool
                                                                                          intervalInSeconds:300.0];
    [pruner start];

    // start triggers an immediate initial prune on its serial queue.
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [self.sdb collectionMembershipCountWithError:nil] == 0;
    }];
    [self expectationForPredicate:predicate evaluatedWithObject:self.sdb handler:nil];
    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    [pruner stop];
    // Subsequent calls after stop should be safe.
    [pruner stop];
}

@end
