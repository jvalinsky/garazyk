// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/ActorStore/PDSActorStoreInternal.h"

@interface PDSDatabaseWebAuthnTests : XCTestCase
@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) PDSActorStore *serviceStore;
@property (nonatomic, strong) NSURL *tempDirURL;
@end

@implementation PDSDatabaseWebAuthnTests

- (void)setUp {
    [super setUp];
    self.tempDirURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"webauthn_test_%@", [[NSUUID UUID] UUIDString]]]];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempDirURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSURL *dbURL = [self.tempDirURL URLByAppendingPathComponent:@"test.db"];

    // webauthn_credentials lives in the service schema (PDSSchemaManager
    // serviceSchemaSQL), which only gets bootstrapped onto a PDSDatabase via
    // PDSActorStore's "__service__" shard handling (see
    // ServiceDatabases.serviceDatabaseWithError:) - a bare
    // [PDSDatabase databaseAtURL:] + openWithError: never applies it. Go
    // through the same PDSActorStore path production uses instead of
    // reimplementing its bootstrap sequence here.
    self.serviceStore = [[PDSActorStore alloc] initWithDid:PDSServiceStoreDID dbPath:dbURL.path];
    NSError *error = nil;
    XCTAssertTrue([self.serviceStore openWithError:&error], @"Failed to open service store: %@", error);
    XCTAssertNil(error);
    self.database = self.serviceStore.database;
}

- (void)tearDown {
    [self.serviceStore close];
    self.serviceStore = nil;
    self.database = nil;
    [[NSFileManager defaultManager] removeItemAtURL:self.tempDirURL error:nil];
    [super tearDown];
}

#pragma mark - Store & Retrieve

- (void)testStoreAndRetrieveCredential {
    NSString *did = @"did:plc:webauthn1";
    NSData *credentialId = [@"credential-id-1" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *credential = @{
        @"credentialId": credentialId,
        @"publicKey": [@"pubkey-1" dataUsingEncoding:NSUTF8StringEncoding],
        @"signCount": @(1),
    };

    NSError *error = nil;
    BOOL stored = [self.database storeWebAuthnCredential:credential forDid:did error:&error];
    XCTAssertTrue(stored, @"storeWebAuthnCredential should succeed");
    XCTAssertNil(error);

    NSArray<NSDictionary *> *creds = [self.database getWebAuthnCredentialsForDid:did error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(creds.count, 1);
}

- (void)testGetCredentialsForDidNotFound {
    NSError *error = nil;
    NSArray<NSDictionary *> *creds = [self.database getWebAuthnCredentialsForDid:@"did:plc:nonexistent" error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(creds.count, 0);
}

- (void)testGetCredentialsMultipleForDid {
    NSString *did = @"did:plc:webauthn-multi";
    for (int i = 0; i < 3; i++) {
        NSDictionary *credential = @{
            @"credentialId": [[NSString stringWithFormat:@"cred-%d", i] dataUsingEncoding:NSUTF8StringEncoding],
            @"publicKey": [@"pubkey" dataUsingEncoding:NSUTF8StringEncoding],
            @"signCount": @(i),
        };
        [self.database storeWebAuthnCredential:credential forDid:did error:nil];
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *creds = [self.database getWebAuthnCredentialsForDid:did error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(creds.count, 3);
}

#pragma mark - Delete

- (void)testDeleteCredential {
    NSString *did = @"did:plc:webauthn-delete";
    NSData *credentialId = [@"cred-to-delete" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *credential = @{
        @"credentialId": credentialId,
        @"publicKey": [@"pubkey" dataUsingEncoding:NSUTF8StringEncoding],
        @"signCount": @(1),
    };
    [self.database storeWebAuthnCredential:credential forDid:did error:nil];

    NSError *error = nil;
    BOOL deleted = [self.database deleteWebAuthnCredential:credentialId forDid:did error:&error];
    XCTAssertTrue(deleted, @"deleteWebAuthnCredential should succeed");
    XCTAssertNil(error);

    NSArray<NSDictionary *> *creds = [self.database getWebAuthnCredentialsForDid:did error:nil];
    XCTAssertEqual(creds.count, 0, @"No credentials should remain after deletion");
}

- (void)testDeleteCredentialNotFound {
    NSData *fakeId = [@"nonexistent-cred" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    BOOL deleted = [self.database deleteWebAuthnCredential:fakeId forDid:@"did:plc:nobody" error:&error];
    XCTAssertFalse(deleted, @"Deleting nonexistent credential should return NO");
}

#pragma mark - Update Sign Count

- (void)testUpdateSignCount {
    NSString *did = @"did:plc:webauthn-signcount";
    NSData *credentialId = [@"cred-signcount" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *credential = @{
        @"credentialId": credentialId,
        @"publicKey": [@"pubkey" dataUsingEncoding:NSUTF8StringEncoding],
        @"signCount": @(1),
    };
    [self.database storeWebAuthnCredential:credential forDid:did error:nil];

    NSError *error = nil;
    BOOL updated = [self.database updateWebAuthnCredentialSignCount:credentialId
                                                            forDid:did
                                                         signCount:42
                                                            error:&error];
    XCTAssertTrue(updated, @"updateWebAuthnCredentialSignCount should succeed");
    XCTAssertNil(error);

    NSArray<NSDictionary *> *creds = [self.database getWebAuthnCredentialsForDid:did error:nil];
    XCTAssertEqual(creds.count, 1);
}

@end
