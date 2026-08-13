// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoCAObjectLifecycle.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "Core/CID.h"

@interface ATProtoCAObjectLifecycleTests : XCTestCase
@property (nonatomic, copy) NSString *tempRoot;
@property (nonatomic, strong) ATProtoCAObjectStore *store;
@property (nonatomic, strong) ATProtoCAObjectLifecycle *lifecycle;
@property (nonatomic, strong) NSDate *fakeNow;
@end

@implementation ATProtoCAObjectLifecycleTests

- (void)setUp {
    [super setUp];
    self.tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"ca-life-%@", NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    self.store = [[ATProtoCAObjectStore alloc] initWithRootDirectory:self.tempRoot error:&error];
    XCTAssertNotNil(self.store);
    self.lifecycle = [[ATProtoCAObjectLifecycle alloc] initWithObjectStore:self.store error:&error];
    XCTAssertNotNil(self.lifecycle);
    self.fakeNow = [NSDate dateWithTimeIntervalSince1970:1700000000.0];
    __weak typeof(self) weakSelf = self;
    self.lifecycle.nowProvider = ^{
        return weakSelf.fakeNow;
    };
    self.lifecycle.sweepEnabled = YES;
    self.lifecycle.gracePeriodSeconds = 60 * 60;
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempRoot error:nil];
    [super tearDown];
}

- (ATProtoCID *)putBytes:(NSString *)text {
    NSError *error = nil;
    ATProtoCID *cid = [self.store putData:[text dataUsingEncoding:NSUTF8StringEncoding]
                              expectedCID:nil
                                  profile:ATProtoCAObjectDigestProfileSHA256
                                    error:&error];
    XCTAssertNotNil(cid);
    return cid;
}

- (void)testGracePeriodClampsToOneHour {
    XCTAssertEqual([ATProtoCAObjectLifecycle clampedGracePeriodSeconds:1], 60 * 60);
    XCTAssertEqual([ATProtoCAObjectLifecycle clampedGracePeriodSeconds:60 * 60], 60 * 60);
    XCTAssertEqual([ATProtoCAObjectLifecycle clampedGracePeriodSeconds:7 * 60 * 60], 7 * 60 * 60);
    self.lifecycle.gracePeriodSeconds = 30;
    XCTAssertEqual(self.lifecycle.gracePeriodSeconds, 60 * 60);
}

- (void)testSharedObjectSurvivesPartialRetractAndUnsharedReclaimsAfterGrace {
    ATProtoCID *shared = [self putBytes:@"shared-rendition"];
    ATProtoCID *onlyA = [self putBytes:@"only-manifest-a"];
    ATProtoCID *onlyB = [self putBytes:@"only-manifest-b"];
    ATProtoCID *manifestA = [self putBytes:@"manifest-a-drisl"];
    ATProtoCID *manifestB = [self putBytes:@"manifest-b-drisl"];

    NSError *error = nil;
    BOOL publishedA = [self.lifecycle publishManifestCID:manifestA
                                   referencedObjectCIDs:@[shared, onlyA]
                                                  error:&error];
    XCTAssertTrue(publishedA);
    BOOL publishedB = [self.lifecycle publishManifestCID:manifestB
                                   referencedObjectCIDs:@[shared, onlyB]
                                                  error:&error];
    XCTAssertTrue(publishedB);

    NSInteger sharedCount = [self.lifecycle refcountForCID:shared error:&error];
    NSInteger onlyACount = [self.lifecycle refcountForCID:onlyA error:&error];
    NSInteger onlyBCount = [self.lifecycle refcountForCID:onlyB error:&error];
    XCTAssertEqual(sharedCount, 2);
    XCTAssertEqual(onlyACount, 1);
    XCTAssertEqual(onlyBCount, 1);

    BOOL retractedA = [self.lifecycle retractManifestCID:manifestA error:&error];
    XCTAssertTrue(retractedA);
    sharedCount = [self.lifecycle refcountForCID:shared error:&error];
    onlyACount = [self.lifecycle refcountForCID:onlyA error:&error];
    onlyBCount = [self.lifecycle refcountForCID:onlyB error:&error];
    XCTAssertEqual(sharedCount, 1);
    XCTAssertEqual(onlyACount, 0);
    XCTAssertEqual(onlyBCount, 1);

    NSInteger deleted = [self.lifecycle sweepWithError:&error];
    XCTAssertEqual(deleted, 0);
    XCTAssertNotNil([self.store dataForCID:onlyA error:&error]);
    XCTAssertNotNil([self.store dataForCID:shared error:&error]);

    self.fakeNow = [self.fakeNow dateByAddingTimeInterval:(60 * 60) + 1];
    deleted = [self.lifecycle sweepWithError:&error];
    XCTAssertEqual(deleted, 2);
    XCTAssertNil([self.store dataForCID:onlyA error:&error]);
    XCTAssertNil([self.store dataForCID:manifestA error:&error]);
    XCTAssertNotNil([self.store dataForCID:shared error:&error]);
    XCTAssertNotNil([self.store dataForCID:onlyB error:&error]);
    XCTAssertNotNil([self.store dataForCID:manifestB error:&error]);

    BOOL retractedB = [self.lifecycle retractManifestCID:manifestB error:&error];
    XCTAssertTrue(retractedB);
    sharedCount = [self.lifecycle refcountForCID:shared error:&error];
    XCTAssertEqual(sharedCount, 0);
    deleted = [self.lifecycle sweepWithError:&error];
    XCTAssertEqual(deleted, 0);
    self.fakeNow = [self.fakeNow dateByAddingTimeInterval:(60 * 60) + 1];
    deleted = [self.lifecycle sweepWithError:&error];
    XCTAssertEqual(deleted, 3);
    XCTAssertNil([self.store dataForCID:shared error:&error]);
}

- (void)testSweepDisabledDeletesNothing {
    self.lifecycle.sweepEnabled = NO;
    ATProtoCID *obj = [self putBytes:@"orphan-candidate"];
    ATProtoCID *manifest = [self putBytes:@"manifest-orphan"];
    NSError *error = nil;
    BOOL published = [self.lifecycle publishManifestCID:manifest referencedObjectCIDs:@[obj] error:&error];
    XCTAssertTrue(published);
    BOOL retracted = [self.lifecycle retractManifestCID:manifest error:&error];
    XCTAssertTrue(retracted);
    self.fakeNow = [self.fakeNow dateByAddingTimeInterval:(60 * 60) + 1];
    NSInteger deleted = [self.lifecycle sweepWithError:&error];
    XCTAssertEqual(deleted, 0);
    XCTAssertNotNil([self.store dataForCID:obj error:&error]);
    XCTAssertNotNil([self.store dataForCID:manifest error:&error]);
}

@end
