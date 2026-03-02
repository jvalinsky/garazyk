#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "PLC/PLCRotationKeyManager.h"
#import "Auth/Secp256k1.h"

@interface PLCRotationKeyManagerTests : XCTestCase
@property (nonatomic, copy) NSString *storageDir;
@end

@implementation PLCRotationKeyManagerTests

- (void)setUp {
    [super setUp];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.storageDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"plc-rotation-tests-%@", uuid]];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.storageDir error:nil];
    [super tearDown];
}

- (void)testLoadOrGenerateCreatesPersistedKey {
    PLCRotationKeyManager *manager = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    NSError *error = nil;
    BOOL ok = [manager loadOrGenerateKeyWithError:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    XCTAssertNotNil(manager.rotationKeyPair);
    XCTAssertNotNil(manager.rotationKeyDidKey);

    NSString *keyFile = [self.storageDir stringByAppendingPathComponent:@"plc_rotation_key.bin"];
    NSData *storedKey = [NSData dataWithContentsOfFile:keyFile];
    XCTAssertGreaterThanOrEqual(storedKey.length, (NSUInteger)32);
}

- (void)testLoadOrGenerateLoadsExistingKey {
    PLCRotationKeyManager *first = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    XCTAssertTrue([first loadOrGenerateKeyWithError:nil]);
    NSString *didKey = first.rotationKeyDidKey;
    NSData *privateKey = first.rotationKeyPair.privateKey;
    XCTAssertNotNil(didKey);
    XCTAssertEqual(privateKey.length, (NSUInteger)32);

    PLCRotationKeyManager *second = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    XCTAssertTrue([second loadOrGenerateKeyWithError:nil]);
    XCTAssertEqualObjects(second.rotationKeyDidKey, didKey);
    XCTAssertEqualObjects(second.rotationKeyPair.privateKey, privateKey);
}

- (void)testSignHashRejectsInvalidLength {
    PLCRotationKeyManager *manager = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    NSData *invalidHash = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *signature = nil;

    BOOL ok = [manager signHash:invalidHash result:&signature error:&error];
    XCTAssertFalse(ok);
    XCTAssertNil(signature);
    XCTAssertEqualObjects(error.domain, PLCRotationKeyManagerErrorDomain);
    XCTAssertEqual(error.code, PLCRotationKeyManagerErrorInvalidKey);
}

- (void)testSignHashReturnsVerifiableSignature {
    PLCRotationKeyManager *manager = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    NSMutableData *hash = [NSMutableData dataWithLength:32];
    for (NSUInteger i = 0; i < 32; i++) {
        uint8_t byte = (uint8_t)(i + 1);
        [hash replaceBytesInRange:NSMakeRange(i, 1) withBytes:&byte];
    }

    NSError *error = nil;
    NSData *signature = nil;
    BOOL ok = [manager signHash:hash result:&signature error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    XCTAssertNotNil(signature);
    XCTAssertGreaterThan(signature.length, (NSUInteger)0);

    NSError *verifyError = nil;
    BOOL verified = [manager.rotationKeyPair verifySignature:signature forHash:hash error:&verifyError];
    XCTAssertTrue(verified);
    XCTAssertNil(verifyError);
}

- (void)testClearKeyClearsMemoryAndFile {
    PLCRotationKeyManager *manager = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    XCTAssertTrue([manager loadOrGenerateKeyWithError:nil]);

    NSString *keyFile = [self.storageDir stringByAppendingPathComponent:@"plc_rotation_key.bin"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:keyFile]);

    [manager clearKey];
    XCTAssertNil(manager.rotationKeyPair);
    XCTAssertNil(manager.rotationKeyDidKey);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:keyFile]);
}

@end
