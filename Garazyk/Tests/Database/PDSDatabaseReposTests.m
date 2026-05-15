// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseReposTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseReposTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"repos_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];
    self.database = [PDSDatabase databaseAtURL:dbURL];
    NSError *error = nil;
    XCTAssertTrue([self.database openWithError:&error], @"Failed to open database: %@", error);
    XCTAssertNil(error);
}

- (void)tearDown {
    [self.database close];
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Helper

- (PDSDatabaseRepo *)testRepoWithOwnerDid:(NSString *)ownerDid {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = ownerDid;
    repo.rootCid = [@"bafyreitestrootcid" dataUsingEncoding:NSUTF8StringEncoding];
    repo.createdAt = [NSDate date];
    repo.updatedAt = [NSDate date];
    return repo;
}

#pragma mark - Create

- (void)testCreateRepo {
    PDSDatabaseRepo *repo = [self testRepoWithOwnerDid:@"did:plc:repo1"];
    NSError *error = nil;
    BOOL created = [self.database createRepo:repo error:&error];
    XCTAssertTrue(created, @"createRepo should succeed");
    XCTAssertNil(error);
}

#pragma mark - Read

- (void)testGetRepoForDid {
    PDSDatabaseRepo *repo = [self testRepoWithOwnerDid:@"did:plc:repo2"];
    [self.database createRepo:repo error:nil];

    NSError *error = nil;
    PDSDatabaseRepo *found = [self.database getRepoForDid:@"did:plc:repo2" error:&error];
    XCTAssertNotNil(found, @"Should find repo by DID");
    XCTAssertNil(error);
    XCTAssertEqualObjects(found.ownerDid, @"did:plc:repo2");
}

- (void)testGetRepoForDidNotFound {
    NSError *error = nil;
    PDSDatabaseRepo *found = [self.database getRepoForDid:@"did:plc:nonexistent" error:&error];
    XCTAssertNil(found, @"Should return nil for nonexistent repo");
    XCTAssertNil(error);
}

- (void)testGetAllRepos {
    [self.database createRepo:[self testRepoWithOwnerDid:@"did:plc:allrepo1"] error:nil];
    [self.database createRepo:[self testRepoWithOwnerDid:@"did:plc:allrepo2"] error:nil];

    NSError *error = nil;
    NSArray<PDSDatabaseRepo *> *repos = [self.database getAllReposWithError:&error];
    XCTAssertGreaterThanOrEqual(repos.count, 2);
    XCTAssertNil(error);
}

#pragma mark - Update

- (void)testUpdateRepoRoot {
    PDSDatabaseRepo *repo = [self testRepoWithOwnerDid:@"did:plc:updaterepo"];
    [self.database createRepo:repo error:nil];

    NSData *newRootCid = [@"bafyreinewrootcid123" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL updated = [self.database updateRepoRoot:@"did:plc:updaterepo"
                                          rootCid:newRootCid
                                            error:&error];
    XCTAssertTrue(updated);
    XCTAssertNil(error);

    PDSDatabaseRepo *found = [self.database getRepoForDid:@"did:plc:updaterepo" error:nil];
    XCTAssertNotNil(found);
    XCTAssertEqualObjects(found.rootCid, newRootCid);
}

#pragma mark - Delete

- (void)testDeleteRepo {
    PDSDatabaseRepo *repo = [self testRepoWithOwnerDid:@"did:plc:deleterepo"];
    [self.database createRepo:repo error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteRepo:@"did:plc:deleterepo" error:&error];
    XCTAssertTrue(deleted);
    XCTAssertNil(error);

    PDSDatabaseRepo *found = [self.database getRepoForDid:@"did:plc:deleterepo" error:nil];
    XCTAssertNil(found, @"Repo should be gone after deletion");
}

@end
