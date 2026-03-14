// Tests for PDSSchemaManager: schema SQL content and singleton behaviour.

#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "Database/Schema/PDSSchemaManager.h"

@interface PDSSchemaManagerTests : XCTestCase
@property (nonatomic, strong) PDSSchemaManager *manager;
@end

@implementation PDSSchemaManagerTests

- (void)setUp {
    [super setUp];
    self.manager = [PDSSchemaManager sharedManager];
    XCTAssertNotNil(self.manager);
}

#pragma mark - Singleton

- (void)testSharedManagerReturnsSameInstance {
    PDSSchemaManager *a = [PDSSchemaManager sharedManager];
    PDSSchemaManager *b = [PDSSchemaManager sharedManager];
    XCTAssertEqual(a, b, @"sharedManager must return the same instance");
}

#pragma mark - Service Schema

- (void)testServiceSchemaContainsAccountsTable {
    NSString *sql = [self.manager serviceSchemaSQL];
    XCTAssertTrue([sql containsString:@"accounts"],
                  @"Service schema must reference an accounts table");
    XCTAssertTrue([sql containsString:@"CREATE TABLE"],
                  @"Service schema must contain CREATE TABLE statements");
}

- (void)testServiceSchemaContainsJWTSigningKeys {
    NSString *sql = [self.manager serviceSchemaSQL];
    XCTAssertTrue([sql containsString:@"jwt_signing_keys"],
                  @"Service schema must contain jwt_signing_keys table");
}

- (void)testServiceJWTSigningKeysSchemaHasCreateTable {
    NSString *sql = [self.manager serviceJWTSigningKeysTableSchema];
    XCTAssertTrue([sql containsString:@"CREATE TABLE"],
                  @"JWT signing keys schema must be a CREATE TABLE statement");
}

- (void)testServiceAccountsSchemaHasCreateTable {
    NSString *sql = [self.manager serviceAccountsTableSchema];
    XCTAssertTrue([sql containsString:@"CREATE TABLE"],
                  @"Accounts schema must be a CREATE TABLE statement");
}

- (void)testServiceRefreshTokensSchemaNonEmpty {
    NSString *sql = [self.manager serviceRefreshTokensTableSchema];
    XCTAssertGreaterThan(sql.length, (NSUInteger)0,
                         @"Refresh tokens schema must not be empty");
}

- (void)testServiceInviteCodesSchemaNonEmpty {
    NSString *sql = [self.manager serviceInviteCodesTableSchema];
    XCTAssertGreaterThan(sql.length, (NSUInteger)0,
                         @"Invite codes schema must not be empty");
}

#pragma mark - Actor Store Schema

- (void)testActorStoreSchemaContainsRecordsTable {
    NSString *sql = [self.manager actorStoreSchemaSQL];
    XCTAssertTrue([sql containsString:@"records"],
                  @"Actor store schema must contain records table");
}

- (void)testActorStoreSchemaContainsBlocksTable {
    NSString *sql = [self.manager actorStoreSchemaSQL];
    XCTAssertTrue([sql containsString:@"blocks"],
                  @"Actor store schema must contain blocks table");
}

- (void)testActorStoreSchemaContainsCreateTable {
    NSString *sql = [self.manager actorStoreSchemaSQL];
    XCTAssertTrue([sql containsString:@"CREATE TABLE"],
                  @"Actor store schema must contain at least one CREATE TABLE");
}

- (void)testActorStoreRecordsSchemaHasCreateTable {
    NSString *sql = [self.manager actorStoreRecordsTableSchema];
    XCTAssertTrue([sql containsString:@"CREATE TABLE"],
                  @"Records table schema must be a CREATE TABLE statement");
}

- (void)testActorStoreBlocksSchemaHasCreateTable {
    NSString *sql = [self.manager actorStoreBlocksTableSchema];
    XCTAssertTrue([sql containsString:@"CREATE TABLE"],
                  @"Blocks table schema must be a CREATE TABLE statement");
}

- (void)testActorStoreBlobsSchemaNonEmpty {
    NSString *sql = [self.manager actorStoreBlobsTableSchema];
    XCTAssertGreaterThan(sql.length, (NSUInteger)0,
                         @"Blobs schema must not be empty");
}

- (void)testActorStoreRepoRootSchemaNonEmpty {
    NSString *sql = [self.manager actorStoreRepoRootTableSchema];
    XCTAssertGreaterThan(sql.length, (NSUInteger)0,
                         @"Repo root schema must not be empty");
}

#pragma mark - Legacy convenience methods

- (void)testLegacyAccountsTableSchemaIsNonEmpty {
    NSString *sql = [self.manager accountsTableSchema];
    XCTAssertGreaterThan(sql.length, (NSUInteger)0);
}

- (void)testLegacyInviteCodesTableSchemaIsNonEmpty {
    NSString *sql = [self.manager inviteCodesTableSchema];
    XCTAssertGreaterThan(sql.length, (NSUInteger)0);
}

@end
