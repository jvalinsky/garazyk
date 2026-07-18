// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"

@interface PDSDatabaseOAuthClientsTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseOAuthClientsTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"oauthclients_test_%@", [[NSUUID UUID] UUIDString]]]];
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

#pragma mark - Create & Get (Legacy)

- (void)testCreateAndGetClient {
    NSDictionary *client = @{
        @"client_id": @"test-client-1",
        @"client_name": @"Test App",
        @"redirect_uris": @[@"https://example.com/callback"],
    };

    NSError *error = nil;
    BOOL created = [self.database createClient:client error:&error];
    XCTAssertTrue(created, @"createClient should succeed");
    XCTAssertNil(error);

    NSDictionary *fetched = [self.database getClientWithID:@"test-client-1" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched[@"client_name"], @"Test App");
}

- (void)testGetClientNotFound {
    NSError *error = nil;
    NSDictionary *fetched = [self.database getClientWithID:@"nonexistent-client" error:&error];
    XCTAssertNil(fetched, @"Should return nil for nonexistent client");
    XCTAssertNil(error);
}

#pragma mark - OAuth Client

- (void)testCreateAndGetOAuthClient {
    NSDictionary *client = @{
        @"client_id": @"oauth-client-1",
        @"client_name": @"OAuth Test App",
        @"redirect_uris": @[@"https://example.com/callback"],
    };

    NSError *error = nil;
    BOOL created = [self.database createOAuthClient:client error:&error];
    XCTAssertTrue(created, @"createOAuthClient should succeed");
    XCTAssertNil(error);

    NSDictionary *fetched = [self.database getOAuthClientWithID:@"oauth-client-1" error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(fetched);
    XCTAssertEqualObjects(fetched[@"client_name"], @"OAuth Test App");
}

- (void)testGetOAuthClientNotFound {
    NSError *error = nil;
    NSDictionary *fetched = [self.database getOAuthClientWithID:@"nonexistent-oauth" error:&error];
    XCTAssertNil(fetched, @"Should return nil for nonexistent OAuth client");
    XCTAssertNil(error);
}

#pragma mark - Seed Test Client

- (void)testSeedTestClient {
    NSError *error = nil;
    BOOL seeded = [self.database seedTestClient:&error];
    XCTAssertTrue(seeded, @"seedTestClient should succeed");
    XCTAssertNil(error);
}

#pragma mark - List All

- (void)testGetAllOAuthClients {
    NSDictionary *client1 = @{
        @"client_id": @"list-client-1",
        @"client_name": @"App One",
        @"redirect_uris": @[@"https://a.example.com/callback"],
    };
    NSDictionary *client2 = @{
        @"client_id": @"list-client-2",
        @"client_name": @"App Two",
        @"redirect_uris": @[@"https://b.example.com/callback"],
    };
    [self.database createOAuthClient:client1 error:nil];
    [self.database createOAuthClient:client2 error:nil];

    NSError *error = nil;
    NSArray<NSDictionary *> *all = [self.database getAllOAuthClientsWithError:&error];
    XCTAssertNil(error);
    XCTAssertGreaterThanOrEqual(all.count, 2);
}

#pragma mark - Delete

- (void)testDeleteOAuthClient {
    NSDictionary *client = @{
        @"client_id": @"del-client-1",
        @"client_name": @"Delete Me",
        @"redirect_uris": @[@"https://example.com/callback"],
    };
    [self.database createOAuthClient:client error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteOAuthClientWithID:@"del-client-1" error:&error];
    XCTAssertTrue(deleted, @"deleteOAuthClientWithID should succeed");
    XCTAssertNil(error);

    NSDictionary *fetched = [self.database getOAuthClientWithID:@"del-client-1" error:nil];
    XCTAssertNil(fetched, @"Client should be gone after deletion");
}

- (void)testDeleteOAuthClientNotFound {
    NSError *error = nil;
    BOOL deleted = [self.database deleteOAuthClientWithID:@"nonexistent-del" error:&error];
    XCTAssertFalse(deleted, @"Deleting nonexistent client should return NO");
}

@end
