/*!
 @file AppViewRelevanceSetTests.m

 @abstract Tests for interest-graph relevance set: membership, TTL expiry,
 seed/allowlist permanence, and interaction expansion.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "AppViewServer/AppViewDatabase.h"
#import "AppViewServer/AppViewTypes.h"
#import "AppViewServer/Relevance/AppViewRelevanceSet.h"

@interface AppViewRelevanceSetTests : XCTestCase
@property (nonatomic, strong) AppViewDatabase *db;
@property (nonatomic, strong) AppViewRelevanceSet *relevanceSet;
@end

@implementation AppViewRelevanceSetTests

- (void)setUp {
    [super setUp];
    NSError *err = nil;
    self.db = [[AppViewDatabase alloc] initInMemoryWithError:&err];
    XCTAssertNotNil(self.db);
    [self.db runMigrations:&err];

    self.relevanceSet = [[AppViewRelevanceSet alloc]
        initWithDatabase:self.db
                seedDIDs:@[@"did:plc:seed1", @"did:plc:seed2"]
               allowlist:@[@"did:plc:allow1"]
                ttlHours:1];
}

- (void)tearDown {
    [self.db close];
    [super tearDown];
}

- (void)testRebuildSeedsAreRelevant {
    [self.relevanceSet rebuild];
    // Give background queue time
    [NSThread sleepForTimeInterval:0.05];

    XCTAssertTrue([self.relevanceSet isDIDRelevant:@"did:plc:seed1"]);
    XCTAssertTrue([self.relevanceSet isDIDRelevant:@"did:plc:seed2"]);
    XCTAssertTrue([self.relevanceSet isDIDRelevant:@"did:plc:allow1"]);
    XCTAssertFalse([self.relevanceSet isDIDRelevant:@"did:plc:unknown"]);
}

- (void)testAddDynamicMembership {
    [self.relevanceSet addDID:@"did:plc:dynamic" reason:AppViewRelevanceReasonFollowOfSeed];
    [NSThread sleepForTimeInterval:0.05];

    XCTAssertTrue([self.relevanceSet isDIDRelevant:@"did:plc:dynamic"]);
}

- (void)testInteractionExpansionOnlyForRelevantActor {
    // actorDID is not in R → should NOT add targetDID
    [self.relevanceSet recordInteraction:@"did:plc:outsider" withDID:@"did:plc:target"];
    [NSThread sleepForTimeInterval:0.05];
    XCTAssertFalse([self.relevanceSet isDIDRelevant:@"did:plc:target"],
                   @"Non-member actor should not expand relevance set");

    // Add actorDID to R first
    [self.relevanceSet addDID:@"did:plc:actor" reason:AppViewRelevanceReasonSeed];
    [NSThread sleepForTimeInterval:0.05];
    [self.relevanceSet recordInteraction:@"did:plc:actor" withDID:@"did:plc:target2"];
    [NSThread sleepForTimeInterval:0.05];
    XCTAssertTrue([self.relevanceSet isDIDRelevant:@"did:plc:target2"],
                  @"Member actor should expand relevance set via interaction");
}

- (void)testPruneExpired {
    // Add 3 entries with past expiry
    for (NSInteger i = 0; i < 3; i++) {
        NSString *did = [NSString stringWithFormat:@"did:plc:old%ld", (long)i];
        AppViewRelevanceMembership *m = [[AppViewRelevanceMembership alloc]
            initWithDID:did
                 reason:AppViewRelevanceReasonRecentInteraction
              expiresAt:[NSDate dateWithTimeIntervalSinceNow:-7200]];
        [self.db upsertRelevanceMembership:m error:nil];
    }

    NSInteger removed = [self.relevanceSet pruneExpired];
    XCTAssertEqual(removed, 3);
}

- (void)testAllRelevantDIDsAfterRebuild {
    [self.relevanceSet rebuild];
    [NSThread sleepForTimeInterval:0.05];

    NSArray<NSString *> *dids = [self.relevanceSet allRelevantDIDs];
    XCTAssertGreaterThanOrEqual(dids.count, 3u,
                                @"Should include at least seed1, seed2, allow1");
}

@end
