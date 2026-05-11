// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Services/PDS/PDSRecordService.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/PDSDatabase.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/Service/ServiceDatabases.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconValidator.h"

#pragma mark - Germ E2EE DM Record Tests
// These tests verify that the PDS can host com.germnetwork.* records
// for Germ Protocol E2EE 1:1 DM support. Models after Germ's current
// shipping product (1:1 E2EE DMs only).

@interface GermRecordTests : XCTestCase
@property (nonatomic, strong) NSString *testDirectory;
@property (nonatomic, strong) PDSDatabasePool *pool;
@property (nonatomic, strong) PDSRecordService *service;
@property (nonatomic, copy) NSString *testDID;
@end

@implementation GermRecordTests

- (void)setUp {
    [super setUp];

    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *lexiconPath = [cwd stringByAppendingPathComponent:@"Garazyk/Resources/lexicons"];
    setenv("PDS_LEXICON_PATH", lexiconPath.UTF8String, 1);

    self.testDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDirectory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.pool = [[PDSDatabasePool alloc] initWithDbDirectory:self.testDirectory maxSize:5];
    self.service = [[PDSRecordService alloc] initWithDatabasePool:self.pool];

    self.testDID = @"did:web:test.germ.example.com";

    uint8_t priv[32] = {0};
    memset(priv, 1, 32);
    PDSActorStore *store = [self.pool storeForDid:self.testDID error:nil];
    [store importSigningKey:[NSData dataWithBytes:priv length:32] error:nil];

    ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
    [registry clearCache];
    NSArray<NSString *> *paths = [registry searchPathsForDirectory:nil];
    for (NSString *path in paths) {
        [registry loadLexiconsFromDirectory:path error:nil];
    }
}

- (void)tearDown {
    [self.pool closeAll];
    self.pool = nil;
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.testDirectory error:nil];
    [super tearDown];
}

#pragma mark - com.germnetwork.declaration

- (void)testCreateGermDeclarationRecord {
    // Simulate a com.germnetwork.declaration record with a Curve25519
    // Anchor Key (32 bytes) and a version string.
    NSData *anchorKey = [self generateTestAnchorKey];

    NSDictionary *record = @{
        @"$type": @"com.germnetwork.declaration",
        @"version": @"1.0.0",
        @"currentKey": @{@"$bytes": [self base64EncodeData:anchorKey]},
        @"messageMe": @{
            @"showButtonTo": @"everyone",
            @"messageMeUrl": @"https://germ.example.com/message"
        }
    };

    NSDictionary *write = @{
        @"action": @"create",
        @"collection": @"com.germnetwork.declaration",
        @"rkey": @"self",
        @"value": record
    };

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:@[write]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOptimistic
                                          swapCommit:nil
                                               error:&error];

    XCTAssertNil(error, @"Declaration record creation should not fail: %@", error.localizedDescription);
    XCTAssertNotNil(result, @"Declaration record creation should return a result");

    NSArray *results = result[@"results"];
    XCTAssertTrue(results.count > 0, @"Should have at least one result");
    NSDictionary *firstResult = results.firstObject;
    XCTAssertNotNil(firstResult[@"uri"], @"Result should contain a URI");
    XCTAssertTrue([firstResult[@"uri"] containsString:@"com.germnetwork.declaration"],
                  @"URI should contain the collection name");
}

- (void)testReadGermDeclarationRecord {
    // Create first, then read back
    NSData *anchorKey = [self generateTestAnchorKey];

    NSDictionary *record = @{
        @"$type": @"com.germnetwork.declaration",
        @"version": @"1.0.0",
        @"currentKey": @{@"$bytes": [self base64EncodeData:anchorKey]},
        @"messageMe": @{
            @"showButtonTo": @"usersIFollow",
            @"messageMeUrl": @"https://germ.example.com/message"
        }
    };

    NSDictionary *write = @{
        @"action": @"create",
        @"collection": @"com.germnetwork.declaration",
        @"rkey": @"self",
        @"value": record
    };

    NSError *error = nil;
    [self.service applyWrites:@[write]
                      forDid:self.testDID
              validationMode:PDSValidationModeOptimistic
                  swapCommit:nil
                       error:&error];
    XCTAssertNil(error, @"Create should succeed");

    // Read back via URI
    NSString *uri = [NSString stringWithFormat:@"at://%s/com.germnetwork.declaration/self", self.testDID.UTF8String];
    PDSActorStore *store = [self.pool storeForDid:self.testDID error:nil];
    XCTAssertNotNil(store, @"Store should exist for test DID");

    PDSDatabaseRecord *readResult = [store getRecord:uri forDid:self.testDID error:&error];
    XCTAssertNil(error, @"Read should succeed: %@", error.localizedDescription);
    XCTAssertNotNil(readResult, @"Should be able to read back the declaration record");
}

- (void)testGermDeclarationWithKeyPackage {
    // Test declaration with embedded keyPackage (opaque MLS data)
    NSData *anchorKey = [self generateTestAnchorKey];
    NSData *keyPackage = [self generateTestKeyPackage];

    NSDictionary *record = @{
        @"$type": @"com.germnetwork.declaration",
        @"version": @"1.0.0",
        @"currentKey": @{@"$bytes": [self base64EncodeData:anchorKey]},
        @"keyPackage": @{@"$bytes": [self base64EncodeData:keyPackage]},
        @"messageMe": @{
            @"showButtonTo": @"everyone",
            @"messageMeUrl": @"https://germ.example.com/message"
        }
    };

    NSDictionary *write = @{
        @"action": @"create",
        @"collection": @"com.germnetwork.declaration",
        @"rkey": @"self",
        @"value": record
    };

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:@[write]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOptimistic
                                          swapCommit:nil
                                               error:&error];

    XCTAssertNil(error, @"Declaration with keyPackage should succeed: %@", error.localizedDescription);
    XCTAssertNotNil(result, @"Should return a result");
}

- (void)testGermDeclarationWithContinuityProofs {
    // Test declaration with continuity proofs for key rolling
    NSData *anchorKey = [self generateTestAnchorKey];
    NSData *proof1 = [self generateTestContinuityProof];
    NSData *proof2 = [self generateTestContinuityProof];

    NSDictionary *record = @{
        @"$type": @"com.germnetwork.declaration",
        @"version": @"1.0.0",
        @"currentKey": @{@"$bytes": [self base64EncodeData:anchorKey]},
        @"continuityProofs": @[
            @{@"$bytes": [self base64EncodeData:proof1]},
            @{@"$bytes": [self base64EncodeData:proof2]}
        ],
        @"messageMe": @{
            @"showButtonTo": @"none",
            @"messageMeUrl": @"https://germ.example.com/message"
        }
    };

    NSDictionary *write = @{
        @"action": @"create",
        @"collection": @"com.germnetwork.declaration",
        @"rkey": @"self",
        @"value": record
    };

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:@[write]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOptimistic
                                          swapCommit:nil
                                               error:&error];

    XCTAssertNil(error, @"Declaration with continuity proofs should succeed: %@", error.localizedDescription);
    XCTAssertNotNil(result, @"Should return a result");
}

#pragma mark - com.germnetwork.keypackage

- (void)testCreateGermKeyPackageRecord {
    // KeyPackage is a separate record containing the AnchorHello wire format
    NSData *anchorHello = [self generateTestAnchorHello];
    NSData *anchorSignature = [self generateTestAnchorSignature];

    NSDictionary *record = @{
        @"$type": @"com.germnetwork.keypackage",
        @"version": @"1.0.0",
        @"anchorHello": @{@"$bytes": [self base64EncodeData:anchorHello]},
        @"anchorSignature": @{@"$bytes": [self base64EncodeData:anchorSignature]}
    };

    NSDictionary *write = @{
        @"action": @"create",
        @"collection": @"com.germnetwork.keypackage",
        @"rkey": @"self",
        @"value": record
    };

    NSError *error = nil;
    NSDictionary *result = [self.service applyWrites:@[write]
                                              forDid:self.testDID
                                      validationMode:PDSValidationModeOptimistic
                                          swapCommit:nil
                                               error:&error];

    XCTAssertNil(error, @"KeyPackage record creation should succeed: %@", error.localizedDescription);
    XCTAssertNotNil(result, @"Should return a result");
}

- (void)testReadGermKeyPackageRecord {
    NSData *anchorHello = [self generateTestAnchorHello];
    NSData *anchorSignature = [self generateTestAnchorSignature];

    NSDictionary *record = @{
        @"$type": @"com.germnetwork.keypackage",
        @"version": @"1.0.0",
        @"anchorHello": @{@"$bytes": [self base64EncodeData:anchorHello]},
        @"anchorSignature": @{@"$bytes": [self base64EncodeData:anchorSignature]}
    };

    NSDictionary *write = @{
        @"action": @"create",
        @"collection": @"com.germnetwork.keypackage",
        @"rkey": @"self",
        @"value": record
    };

    NSError *error = nil;
    [self.service applyWrites:@[write]
                      forDid:self.testDID
              validationMode:PDSValidationModeOptimistic
                  swapCommit:nil
                       error:&error];
    XCTAssertNil(error, @"Create should succeed");

    NSString *uri = [NSString stringWithFormat:@"at://%s/com.germnetwork.keypackage/self", self.testDID.UTF8String];
    PDSActorStore *store = [self.pool storeForDid:self.testDID error:nil];
    PDSDatabaseRecord *readResult = [store getRecord:uri forDid:self.testDID error:&error];
    XCTAssertNil(error, @"Read should succeed: %@", error.localizedDescription);
    XCTAssertNotNil(readResult, @"Should be able to read back the keypackage record");
}

#pragma mark - Lexicon Validation

- (void)testGermLexiconsAreLoaded {
    ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
    XCTAssertTrue([registry hasSchemaForNSID:@"com.germnetwork.declaration"],
                  @"com.germnetwork.declaration lexicon should be loaded");
    XCTAssertTrue([registry hasSchemaForNSID:@"com.germnetwork.keypackage"],
                  @"com.germnetwork.keypackage lexicon should be loaded");
    XCTAssertTrue([registry hasSchemaForNSID:@"com.germnetwork.authManageDeclaration"],
                  @"com.germnetwork.authManageDeclaration lexicon should be loaded");
}

- (void)testGermDeclarationValidationRejectsMissingRequiredFields {
    // Missing required field "version" should fail in required mode
    NSDictionary *record = @{
        @"$type": @"com.germnetwork.declaration",
        @"currentKey": @{@"$bytes": [self base64EncodeData:[self generateTestAnchorKey]]}
        // Missing "version"
    };

    ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
    ATProtoLexiconValidator *validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];

    NSError *error = nil;
    BOOL valid = [validator validateRecord:record
                               collection:@"com.germnetwork.declaration"
                                     mode:ATProtoValidationModeRequired
                                    error:&error];

    XCTAssertFalse(valid, @"Should reject record missing required 'version' field");
    XCTAssertNotNil(error, @"Should produce a validation error");
}

#pragma mark - Helpers

- (NSData *)generateTestAnchorKey {
    // Simulate a Curve25519 public key (32 bytes) with a type prefix byte
    // In the real protocol, this is TypedKeyMaterial with a byte enum prefix
    uint8_t keyBytes[33] = {0};
    keyBytes[0] = 0x00; // Type prefix for curve25519 signing
    for (int i = 1; i < 33; i++) keyBytes[i] = (uint8_t)(arc4random_uniform(256));
    return [NSData dataWithBytes:keyBytes length:33];
}

- (NSData *)generateTestKeyPackage {
    // Simulate an MLS KeyPackage (opaque blob)
    uint8_t data[256] = {0};
    for (int i = 0; i < 256; i++) data[i] = (uint8_t)(arc4random_uniform(256));
    return [NSData dataWithBytes:data length:256];
}

- (NSData *)generateTestContinuityProof {
    // Simulate a succession proof (opaque blob)
    uint8_t data[128] = {0};
    for (int i = 0; i < 128; i++) data[i] = (uint8_t)(arc4random_uniform(256));
    return [NSData dataWithBytes:data length:128];
}

- (NSData *)generateTestAnchorHello {
    // Simulate an AnchorHello wire format (opaque blob)
    uint8_t data[512] = {0};
    for (int i = 0; i < 512; i++) data[i] = (uint8_t)(arc4random_uniform(256));
    return [NSData dataWithBytes:data length:512];
}

- (NSData *)generateTestAnchorSignature {
    // Simulate an Ed25519 signature (64 bytes)
    uint8_t sig[64] = {0};
    for (int i = 0; i < 64; i++) sig[i] = (uint8_t)(arc4random_uniform(256));
    return [NSData dataWithBytes:sig length:64];
}

- (NSString *)base64EncodeData:(NSData *)data {
    return [data base64EncodedStringWithOptions:0];
}

@end
