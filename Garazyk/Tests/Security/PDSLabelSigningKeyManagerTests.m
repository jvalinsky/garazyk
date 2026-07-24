// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>
#import "Security/PDSLabelSigningKeyManager.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"

@interface PDSLabelSigningKeyManagerTests : XCTestCase
@property (nonatomic, strong) NSString *tempDir;
@end

@implementation PDSLabelSigningKeyManagerTests

- (void)setUp {
    [super setUp];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    [super tearDown];
}

- (void)testGeneratesNewKey {
    NSError *error = nil;
    PDSLabelSigningKeyManager *mgr = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:self.tempDir];
    XCTAssertTrue([mgr loadOrGenerateKeyWithError:&error], @"error: %@", error);
    XCTAssertNotNil(mgr.signingKeyPair);
    XCTAssertNotNil(mgr.signingKeyDidKey);
    XCTAssertTrue([mgr.signingKeyDidKey hasPrefix:@"did:key:z"]);
}

- (void)testPersistsAndLoadsKey {
    PDSLabelSigningKeyManager *mgr1 = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:self.tempDir];
    NSError *error = nil;
    XCTAssertTrue([mgr1 loadOrGenerateKeyWithError:&error]);
    NSString *didKey1 = mgr1.signingKeyDidKey;

    PDSLabelSigningKeyManager *mgr2 = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:self.tempDir];
    XCTAssertTrue([mgr2 loadOrGenerateKeyWithError:&error]);
    XCTAssertEqualObjects(mgr2.signingKeyDidKey, didKey1);
}

- (void)testSignAndVerify {
    PDSLabelSigningKeyManager *mgr = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:self.tempDir];
    NSError *error = nil;
    [mgr loadOrGenerateKeyWithError:&error];

    NSData *data = [@"test label payload" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [mgr signData:data error:&error];
    XCTAssertNotNil(sig, @"sign error: %@", error);
    XCTAssertTrue([mgr verifySignature:sig forData:data error:&error]);
}

- (void)testVerifyRejectsTamperedData {
    PDSLabelSigningKeyManager *mgr = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:self.tempDir];
    [mgr loadOrGenerateKeyWithError:nil];

    NSData *data = [@"original data" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [mgr signData:data error:nil];
    NSData *tampered = [@"tampered data" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    XCTAssertFalse([mgr verifySignature:sig forData:tampered error:&error]);
}

- (void)testClearKeyRemovesFromDisk {
    PDSLabelSigningKeyManager *mgr = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:self.tempDir];
    [mgr loadOrGenerateKeyWithError:nil];
    XCTAssertNotNil(mgr.signingKeyDidKey);

    [mgr clearKey];
    XCTAssertNil(mgr.signingKeyPair);
    XCTAssertNil(mgr.signingKeyDidKey);

    NSString *keyPath = [self.tempDir stringByAppendingPathComponent:@"label_signing_key.bin"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:keyPath]);
}

- (void)testInMemoryOnly {
    PDSLabelSigningKeyManager *mgr = [[PDSLabelSigningKeyManager alloc] initWithStoragePath:nil];
    NSError *error = nil;
    XCTAssertTrue([mgr loadOrGenerateKeyWithError:&error]);
    XCTAssertNotNil(mgr.signingKeyPair);
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *sig = [mgr signData:data error:&error];
    XCTAssertNotNil(sig);
    XCTAssertTrue([mgr verifySignature:sig forData:data error:&error]);
}

@end
