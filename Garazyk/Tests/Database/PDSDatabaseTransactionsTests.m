// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseTransactionsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseTransactionsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"txn_test_%@", [[NSUUID UUID] UUIDString]]]];
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

#pragma mark - Basic Transaction Lifecycle

- (void)testBeginCommitTransaction {
    NSError *error = nil;
    BOOL began = [self.database beginTransactionWithError:&error];
    XCTAssertTrue(began);
    XCTAssertNil(error);

    BOOL committed = [self.database commitTransactionWithError:&error];
    XCTAssertTrue(committed);
    XCTAssertNil(error);
}

- (void)testBeginRollbackTransaction {
    NSError *error = nil;
    BOOL began = [self.database beginTransactionWithError:&error];
    XCTAssertTrue(began);
    XCTAssertNil(error);

    BOOL rolledBack = [self.database rollbackTransactionWithError:&error];
    XCTAssertTrue(rolledBack);
    XCTAssertNil(error);
}

- (void)testTransactionIsAtomic {
    NSString *did = @"did:plc:txnatomic";
    NSString *handle = @"atomic.test";

    NSError *begError = nil;
    XCTAssertTrue([self.database beginTransactionWithError:&begError]);
    XCTAssertNil(begError);

    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.status = @"active";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    [self.database createAccount:account error:nil];

    NSError *rbError = nil;
    XCTAssertTrue([self.database rollbackTransactionWithError:&rbError]);
    XCTAssertNil(rbError);

    PDSDatabaseAccount *found = [self.database getAccountByDid:did error:nil];
    XCTAssertNil(found, @"Account should not exist after rollback");
}

#pragma mark - transactWithBlock

- (void)testTransactWithBlockCommits {
    NSString *did = @"did:plc:txnblock1";
    NSString *handle = @"block1.test";

    NSError *error = nil;
    BOOL result = [self.database transactWithBlock:^(NSError **innerError) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = did;
        account.handle = handle;
        account.status = @"active";
        account.createdAt = [[NSDate date] timeIntervalSince1970];
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        BOOL created = [self.database createAccount:account error:innerError];
        if (!created) return;
    } error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);

    PDSDatabaseAccount *found = [self.database getAccountByDid:did error:nil];
    XCTAssertNotNil(found, @"Account should exist after transactWithBlock commit");
}

- (void)testTransactWithBlockRollsBackOnError {
    NSString *did = @"did:plc:txnrb1";
    NSString *handle = @"rollback1.test";

    NSError *outerError = nil;
    NSError *injectedError = [NSError errorWithDomain:@"TestError" code:42 userInfo:nil];
    BOOL result = [self.database transactWithBlock:^(NSError **innerError) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = did;
        account.handle = handle;
        account.status = @"active";
        account.createdAt = [[NSDate date] timeIntervalSince1970];
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        [self.database createAccount:account error:nil];
        if (innerError) *innerError = injectedError;
    } error:&outerError];

    XCTAssertFalse(result, @"Transaction should fail when block sets error");
    XCTAssertNotNil(outerError);

    PDSDatabaseAccount *found = [self.database getAccountByDid:did error:nil];
    XCTAssertNil(found, @"Account should not exist after rollback");
}

#pragma mark - performTransaction

- (void)testPerformTransactionCommits {
    NSString *did = @"did:plc:perftxn1";
    NSString *handle = @"perf1.test";

    NSError *error = nil;
    BOOL result = [self.database performTransaction:^BOOL(PDSDatabase *db, NSError **innerError) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = did;
        account.handle = handle;
        account.status = @"active";
        account.createdAt = [[NSDate date] timeIntervalSince1970];
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        return [db createAccount:account error:innerError];
    } error:&error];

    XCTAssertTrue(result);
    XCTAssertNil(error);

    PDSDatabaseAccount *found = [self.database getAccountByDid:did error:nil];
    XCTAssertNotNil(found, @"Account should exist after performTransaction commit");
}

- (void)testPerformTransactionRollsBackWhenBlockReturnsNo {
    NSString *did = @"did:plc:perfrb1";
    NSString *handle = @"perfrb1.test";

    NSError *error = nil;
    BOOL result = [self.database performTransaction:^BOOL(PDSDatabase *db, NSError **innerError) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = did;
        account.handle = handle;
        account.status = @"active";
        account.createdAt = [[NSDate date] timeIntervalSince1970];
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        [db createAccount:account error:nil];
        return NO;
    } error:&error];

    XCTAssertFalse(result, @"Transaction should fail when block returns NO");

    PDSDatabaseAccount *found = [self.database getAccountByDid:did error:nil];
    XCTAssertNil(found, @"Account should not exist after rollback");
}

@end
