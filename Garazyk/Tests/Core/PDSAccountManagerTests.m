// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAccountManagerTests.m
 @abstract Unit tests for PDSSQLiteAccountRepository (formerly PDSAccountManager).
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <XCTest/XCTest.h>
#import "Core/Repositories/PDSSQLiteAccountRepository.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/PDSDatabase.h"
#import "Core/ATProtoError.h"

@interface PDSAccountManagerTests : XCTestCase {
    NSString *_tempDir;
    PDSDatabasePool *_pool;
    id<PDSAccountRepository> _manager;
}
@end

@implementation PDSAccountManagerTests

- (void)setUp {
    [super setUp];
    _tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    _pool = [[PDSDatabasePool alloc] initWithDbDirectory:_tempDir maxSize:1];
    _manager = [[PDSSQLiteAccountRepository alloc] initWithServicePool:_pool];
}

- (void)tearDown {
    [_pool closeAll];
    [[NSFileManager defaultManager] removeItemAtPath:_tempDir error:nil];
    [super tearDown];
}

- (void)testCreateAndRetrieveAccount {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:test1";
    account.handle = @"test1.bsky.social";
    account.email = @"test1@example.com";
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;
    
    NSError *error = nil;
    BOOL success = [_manager saveAccount:account error:&error];
    XCTAssertTrue(success, @"Failed to save account: %@", error);
    
    PDSDatabaseAccount *retrieved = [_manager accountForDid:@"did:plc:test1" error:&error];
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved.did, account.did);
    XCTAssertEqualObjects(retrieved.handle, account.handle);
    XCTAssertEqualObjects(retrieved.email, account.email);
}

- (void)testRetrieveAccountByHandleReturnsExpectedDid {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = @"did:plc:test2";
    account.handle = @"test2.bsky.social";
    [_manager saveAccount:account error:nil];
    
    PDSDatabaseAccount *retrieved = [_manager accountForHandle:@"test2.bsky.social" error:nil];
    XCTAssertNotNil(retrieved);
    XCTAssertEqualObjects(retrieved.did, @"did:plc:test2");
}

- (void)testListAccounts {
    for (int i = 0; i < 5; i++) {
        PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
        account.did = [NSString stringWithFormat:@"did:plc:a%d", i];
        account.handle = [NSString stringWithFormat:@"user%d.test", i];
        [_manager saveAccount:account error:nil];
    }
    
    NSArray *accounts = [_manager listAccountsWithLimit:2 cursor:nil error:nil];
    XCTAssertEqual(accounts.count, 2);
    XCTAssertEqualObjects(((PDSDatabaseAccount *)accounts[0]).did, @"did:plc:a0");
    
    NSString *nextCursor = ((PDSDatabaseAccount *)accounts[1]).did;
    NSArray *nextPage = [_manager listAccountsWithLimit:2 cursor:nextCursor error:nil];
    XCTAssertEqual(nextPage.count, 2);
    XCTAssertEqualObjects(((PDSDatabaseAccount *)nextPage[0]).did, @"did:plc:a2");
}

@end
