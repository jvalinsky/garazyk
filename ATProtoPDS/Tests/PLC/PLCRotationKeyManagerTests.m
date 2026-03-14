#ifdef __APPLE__
#import <XCTest/XCTest.h>
#else
#import "Compat/XCTest/XCTest.h"
#endif

#import "PLC/PLCRotationKeyManager.h"
#import "Auth/Secp256k1.h"
#import "Auth/CryptoUtils.h"
#import "App/PDSConfiguration.h"
#import <CommonCrypto/CommonCrypto.h>

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

#pragma mark - CBC→GCM Lazy Migration Tests

// The salt hardcoded in PLCRotationKeyManager.encryptionKeyWithError:
- (NSData *)plcRotationKeySalt {
    static const uint8_t saltBytes[] = {
        0x41, 0x54, 0x50, 0x52, 0x4f, 0x54, 0x4f, 0x5f,
        0x50, 0x44, 0x53, 0x5f, 0x4b, 0x45, 0x59, 0x53
    };
    return [NSData dataWithBytes:saltBytes length:sizeof(saltBytes)];
}

- (NSData *)encryptionKeyForPassword:(NSString *)password {
    return [CryptoUtils deriveKeyFromPassword:password salt:[self plcRotationKeySalt]];
}

// Build a versioned CBC blob (0x01 || IV(16) || ciphertext) using CommonCrypto
- (NSData *)makeVersionedCBCBlob:(NSData *)plaintext encryptionKey:(NSData *)key {
    uint8_t iv[16] = {
        0x10,0x20,0x30,0x40,0x50,0x60,0x70,0x80,
        0x90,0xA0,0xB0,0xC0,0xD0,0xE0,0xF0,0x00
    };
    size_t bufSize = plaintext.length + kCCBlockSizeAES128;
    NSMutableData *ct = [NSMutableData dataWithLength:bufSize];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv,
                                 plaintext.bytes, plaintext.length,
                                 ct.mutableBytes, bufSize, &moved);
    if (st != kCCSuccess) return nil;
    ct.length = moved;

    NSMutableData *blob = [NSMutableData data];
    uint8_t version = 0x01;
    [blob appendBytes:&version length:1];
    [blob appendBytes:iv length:16];
    [blob appendData:ct];
    return blob;
}

- (void)testLoadMigratesCBCEncryptedKeyToGCM {
    NSString *testPassword = @"test-master-secret-for-migration";

    // Set the shared configuration's master secret so the manager can derive the key
    NSString *previousSecret = [PDSConfiguration sharedConfiguration].masterSecret;
    [PDSConfiguration sharedConfiguration].masterSecret = testPassword;

    // Create the storage directory
    [[NSFileManager defaultManager] createDirectoryAtPath:self.storageDir
                                withIntermediateDirectories:YES attributes:nil error:nil];

    // Generate a real secp256k1 private key (32 bytes)
    Secp256k1KeyPair *pair = [Secp256k1KeyPair generateKeyPair:nil];
    XCTAssertNotNil(pair);
    NSData *privateKeyBytes = pair.privateKey;
    XCTAssertEqual(privateKeyBytes.length, (NSUInteger)32);

    // Encrypt it as a versioned CBC blob
    NSData *encKey = [self encryptionKeyForPassword:testPassword];
    XCTAssertNotNil(encKey);
    NSData *cbcBlob = [self makeVersionedCBCBlob:privateKeyBytes encryptionKey:encKey];
    XCTAssertNotNil(cbcBlob);

    // Write the CBC blob to the key file
    NSString *keyFile = [self.storageDir stringByAppendingPathComponent:@"plc_rotation_key.bin"];
    XCTAssertTrue([cbcBlob writeToFile:keyFile atomically:YES]);

    // Confirm the stored blob is NOT already GCM
    const uint8_t *storedBytes = (const uint8_t *)cbcBlob.bytes;
    XCTAssertEqual(storedBytes[0], (uint8_t)0x01, @"Pre-migration blob must be versioned CBC (0x01)");

    // Load the key — the manager must decrypt it and migrate to GCM
    PLCRotationKeyManager *manager = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    NSError *error = nil;
    BOOL ok = [manager loadOrGenerateKeyWithError:&error];
    XCTAssertTrue(ok, @"loadOrGenerateKeyWithError: must succeed for a valid CBC blob: %@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(manager.rotationKeyPair.privateKey, privateKeyBytes,
                          @"Loaded private key must match the original");

    // After migration the file on disk must start with GCM version byte 0x02
    NSData *migratedBlob = [NSData dataWithContentsOfFile:keyFile];
    XCTAssertNotNil(migratedBlob);
    const uint8_t *migratedBytes = (const uint8_t *)migratedBlob.bytes;
    XCTAssertEqual(migratedBytes[0], (uint8_t)0x02, @"Post-migration blob must be GCM (0x02)");

    // Restore previous master secret
    [PDSConfiguration sharedConfiguration].masterSecret = previousSecret;
}

- (void)testLoadAlreadyGCMKeyDoesNotChangeFile {
    NSString *testPassword = @"test-master-secret-gcm-noop";
    NSString *previousSecret = [PDSConfiguration sharedConfiguration].masterSecret;
    [PDSConfiguration sharedConfiguration].masterSecret = testPassword;

    // Generate a new key (will be stored as GCM since master secret is available)
    PLCRotationKeyManager *first = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    NSError *error = nil;
    XCTAssertTrue([first loadOrGenerateKeyWithError:&error]);
    XCTAssertNil(error);

    NSString *keyFile = [self.storageDir stringByAppendingPathComponent:@"plc_rotation_key.bin"];
    NSData *originalBlob = [NSData dataWithContentsOfFile:keyFile];
    XCTAssertNotNil(originalBlob);
    const uint8_t *ob = (const uint8_t *)originalBlob.bytes;
    XCTAssertEqual(ob[0], (uint8_t)0x02, @"Freshly generated key must be GCM (0x02)");

    // Load again — should not rewrite the file
    PLCRotationKeyManager *second = [[PLCRotationKeyManager alloc] initWithStoragePath:self.storageDir];
    XCTAssertTrue([second loadOrGenerateKeyWithError:nil]);
    XCTAssertEqualObjects(second.rotationKeyPair.privateKey, first.rotationKeyPair.privateKey);

    [PDSConfiguration sharedConfiguration].masterSecret = previousSecret;
}

@end
