// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Germ/Server/Services/GermMailboxService.h"
#import "Germ/Server/Config/GermMailboxSchemaManager.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Debug/PDSLogger.h"

#pragma mark - Germ Mailbox Service Tests
// Tests for the Germ E2EE mailbox transport service. Verifies
// ephemeral address claiming, ciphertext delivery/polling,
// rendezvous address registration, and single-read semantics.
// Models after Germ's current shipping 1:1 E2EE DM product.

@interface GermMailboxServiceTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabase *db;
@property (nonatomic, strong) GermMailboxService *service;
@end

@implementation GermMailboxServiceTests

- (void)setUp {
    [super setUp];

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    NSString *dbPath = [self.testDirectory stringByAppendingPathComponent:@"germ-mailbox-test.db"];
    self.db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    [self.db openWithError:nil];

    // Apply schema
    NSString *schemaSQL = [[GermMailboxSchemaManager sharedManager] mailboxSchemaSQL];
    [self.db executeRawSQL:schemaSQL error:nil];

    self.service = [[GermMailboxService alloc] initWithDatabase:(id<PDSQueryDatabase>)self.db];
}

- (void)tearDown {
    [self.db close];
    self.db = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - Ephemeral Address Claiming

- (void)testClaimAddresses {
    NSError *error = nil;
    NSArray *addresses = [self.service claimAddressesForAgent:@"agent-test-001"
                                                       count:5
                                                       error:&error];

    XCTAssertNil(error, @"Claim should succeed: %@", error.localizedDescription);
    XCTAssertNotNil(addresses, @"Should return addresses");
    XCTAssertEqual(addresses.count, 5, @"Should claim exactly 5 addresses");

    for (NSString *addr in addresses) {
        XCTAssertTrue(addr.length > 0, @"Address should not be empty");
        // Addresses should be base64url-encoded (no +, /, or =)
        XCTAssertFalse([addr containsString:@"+"], @"Address should be base64url (no +)");
        XCTAssertFalse([addr containsString:@"/"], @"Address should be base64url (no /)");
        XCTAssertFalse([addr containsString:@"="], @"Address should be base64url (no =)");
    }
}

- (void)testClaimAddressesAreUnique {
    NSError *error = nil;
    NSArray *batch1 = [self.service claimAddressesForAgent:@"agent-unique-1"
                                                      count:10
                                                      error:&error];
    NSArray *batch2 = [self.service claimAddressesForAgent:@"agent-unique-2"
                                                      count:10
                                                      error:&error];

    NSMutableSet *allAddresses = [NSMutableSet setWithArray:batch1];
    [allAddresses addObjectsFromArray:batch2];
    XCTAssertEqual(allAddresses.count, 20, @"All addresses should be unique");
}

- (void)testClaimAddressesRejectsInvalidCount {
    NSError *error = nil;
    NSArray *result = [self.service claimAddressesForAgent:@"agent-test"
                                                    count:0
                                                    error:&error];
    XCTAssertNotNil(error, @"Should reject count of 0");
    XCTAssertNil(result, @"Should return nil for invalid count");

    error = nil;
    result = [self.service claimAddressesForAgent:@"agent-test"
                                            count:101
                                            error:&error];
    XCTAssertNotNil(error, @"Should reject count > 100");
}

- (void)testClaimAddressesRejectsEmptyAgentRef {
    NSError *error = nil;
    NSArray *result = [self.service claimAddressesForAgent:@""
                                                    count:5
                                                    error:&error];
    XCTAssertNotNil(error, @"Should reject empty agent ref");
    XCTAssertNil(result, @"Should return nil for empty agent ref");
}

#pragma mark - Mailbox Delivery

- (void)testDeliverCiphertextToAddress {
    NSError *error = nil;
    NSArray *addresses = [self.service claimAddressesForAgent:@"agent-deliver"
                                                        count:1
                                                        error:&error];
    XCTAssertNil(error);

    NSString *address = addresses.firstObject;
    NSData *ciphertext = [self generateTestCiphertext];

    BOOL delivered = [self.service deliverCiphertext:ciphertext
                                          toAddress:address
                                               error:&error];
    XCTAssertNil(error, @"Delivery should succeed: %@", error.localizedDescription);
    XCTAssertTrue(delivered, @"Delivery should return YES");
}

- (void)testDeliverToExpiredAddressFails {
    // Insert an already-expired address directly
    NSString *expiredSQL = @"INSERT INTO germ_mailboxes (address, agent_ref, expires_at) VALUES (?, ?, datetime('now', '-1 hour'))";
    [(PDSDatabase *)self.db executeParameterizedUpdate:expiredSQL
                                                params:@[@"expired-addr-001", @"agent-expired"]
                                                 error:nil];

    NSData *ciphertext = [self generateTestCiphertext];
    NSError *error = nil;
    BOOL delivered = [self.service deliverCiphertext:ciphertext
                                          toAddress:@"expired-addr-001"
                                               error:&error];
    XCTAssertFalse(delivered, @"Should not deliver to expired address");
    XCTAssertNotNil(error, @"Should produce an error");
}

- (void)testDeliverToNonexistentAddressFails {
    NSData *ciphertext = [self generateTestCiphertext];
    NSError *error = nil;
    BOOL delivered = [self.service deliverCiphertext:ciphertext
                                          toAddress:@"nonexistent-address"
                                               error:&error];
    XCTAssertFalse(delivered, @"Should not deliver to nonexistent address");
    XCTAssertNotNil(error, @"Should produce an error");
}

#pragma mark - Mailbox Polling

- (void)testPollReturnsDeliveredMessages {
    NSError *error = nil;
    NSArray *addresses = [self.service claimAddressesForAgent:@"agent-poll"
                                                        count:2
                                                        error:&error];
    XCTAssertNil(error);

    NSData *ct1 = [self generateTestCiphertext];
    NSData *ct2 = [self generateTestCiphertext];

    [self.service deliverCiphertext:ct1 toAddress:addresses[0] error:nil];
    [self.service deliverCiphertext:ct2 toAddress:addresses[1] error:nil];

    NSArray *messages = [self.service pollMessagesForAgent:@"agent-poll"
                                                    error:&error];
    XCTAssertNil(error, @"Poll should succeed: %@", error.localizedDescription);
    XCTAssertEqual(messages.count, 2, @"Should return 2 messages");
}

- (void)testPollSingleReadSemantics {
    NSError *error = nil;
    NSArray *addresses = [self.service claimAddressesForAgent:@"agent-single-read"
                                                        count:1
                                                        error:&error];
    XCTAssertNil(error);

    NSData *ciphertext = [self generateTestCiphertext];
    [self.service deliverCiphertext:ciphertext toAddress:addresses.firstObject error:nil];

    // First poll should return the message
    NSArray *first = [self.service pollMessagesForAgent:@"agent-single-read" error:nil];
    XCTAssertEqual(first.count, 1, @"First poll should return 1 message");

    // Second poll should return nothing (single-read)
    NSArray *second = [self.service pollMessagesForAgent:@"agent-single-read" error:nil];
    XCTAssertEqual(second.count, 0, @"Second poll should return 0 messages (single-read)");
}

- (void)testPollOnlyReturnsOwnMessages {
    NSError *error = nil;
    NSArray *addr1 = [self.service claimAddressesForAgent:@"agent-a"
                                                    count:1
                                                    error:&error];
    NSArray *addr2 = [self.service claimAddressesForAgent:@"agent-b"
                                                    count:1
                                                    error:&error];
    XCTAssertNil(error);

    NSData *ct = [self generateTestCiphertext];
    [self.service deliverCiphertext:ct toAddress:addr1.firstObject error:nil];

    // Agent B should not see Agent A's messages
    NSArray *bMessages = [self.service pollMessagesForAgent:@"agent-b" error:nil];
    XCTAssertEqual(bMessages.count, 0, @"Agent B should not see Agent A's messages");

    // Agent A should see their own message
    NSArray *aMessages = [self.service pollMessagesForAgent:@"agent-a" error:nil];
    XCTAssertEqual(aMessages.count, 1, @"Agent A should see their own message");
}

#pragma mark - Rendezvous Addresses

- (void)testRegisterRendezvousAddress {
    NSError *error = nil;
    BOOL registered = [self.service registerRendezvousAddress:@"rendezvous-test-001"
                                                     forAgent:@"agent-rendezvous"
                                                       epoch:1
                                                       error:&error];
    XCTAssertNil(error, @"Registration should succeed: %@", error.localizedDescription);
    XCTAssertTrue(registered, @"Should return YES");
}

- (void)testDeliverToRendezvousAddress {
    NSError *error = nil;
    [self.service registerRendezvousAddress:@"rendezvous-deliver-001"
                                   forAgent:@"agent-rendezvous-deliver"
                                     epoch:1
                                     error:nil];

    NSData *ciphertext = [self generateTestCiphertext];
    BOOL delivered = [self.service deliverToRendezvous:ciphertext
                                              address:@"rendezvous-deliver-001"
                                               error:&error];
    XCTAssertNil(error, @"Rendezvous delivery should succeed: %@", error.localizedDescription);
    XCTAssertTrue(delivered, @"Should return YES");
}

- (void)testDeliverToNonexistentRendezvousFails {
    NSData *ciphertext = [self generateTestCiphertext];
    NSError *error = nil;
    BOOL delivered = [self.service deliverToRendezvous:ciphertext
                                              address:@"nonexistent-rendezvous"
                                               error:&error];
    XCTAssertFalse(delivered, @"Should not deliver to nonexistent rendezvous");
    XCTAssertNotNil(error, @"Should produce an error");
}

- (void)testPollRendezvousMessages {
    NSError *error = nil;
    [self.service registerRendezvousAddress:@"rendezvous-poll-001"
                                   forAgent:@"agent-rendezvous-poll"
                                     epoch:1
                                     error:nil];

    NSData *ct = [self generateTestCiphertext];
    [self.service deliverToRendezvous:ct address:@"rendezvous-poll-001" error:nil];

    NSArray *messages = [self.service pollRendezvousForAgent:@"agent-rendezvous-poll"
                                                       error:&error];
    XCTAssertNil(error, @"Rendezvous poll should succeed: %@", error.localizedDescription);
    XCTAssertEqual(messages.count, 1, @"Should return 1 message");
}

#pragma mark - Maintenance

- (void)testExpireStaleAddresses {
    // Insert an already-expired address
    NSString *expiredSQL = @"INSERT INTO germ_mailboxes (address, agent_ref, expires_at) VALUES (?, ?, datetime('now', '-1 hour'))";
    [(PDSDatabase *)self.db executeParameterizedUpdate:expiredSQL
                                                params:@[@"stale-addr", @"agent-stale"]
                                                 error:nil];

    // Insert a valid address
    NSError *error = nil;
    NSArray *valid = [self.service claimAddressesForAgent:@"agent-valid"
                                                    count:1
                                                    error:&error];
    XCTAssertNil(error);

    // Expire stale addresses
    [self.service expireStaleAddresses];

    // Delivery to stale address should fail
    NSData *ct = [self generateTestCiphertext];
    BOOL delivered = [self.service deliverCiphertext:ct
                                          toAddress:@"stale-addr"
                                               error:nil];
    XCTAssertFalse(delivered, @"Should not deliver to expired address after cleanup");

    // Delivery to valid address should succeed
    delivered = [self.service deliverCiphertext:ct
                                      toAddress:valid.firstObject
                                           error:nil];
    XCTAssertTrue(delivered, @"Should deliver to valid address after cleanup");
}

#pragma mark - Helpers

- (NSData *)generateTestCiphertext {
    NSMutableData *data = [NSMutableData dataWithLength:128];
    arc4random_buf(data.mutableBytes, 128);
    return data;
}

@end
