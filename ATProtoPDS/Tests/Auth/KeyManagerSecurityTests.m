#import <XCTest/XCTest.h>
#import "App/PDSConfiguration.h"
#import "Auth/PDSAppleKeyManager.h"
#import "Auth/PDSKeyManagerFactory.h"
#import "Auth/TestKeyFixtures.h"
#if defined(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
#import "Auth/PDSOpenSSLSessionKeyManager.h"
#endif
#import "Database/PDSDatabase.h"

@interface PDSAppleKeyManager (Testing)
- (NSString *)keychainTagForKeyID:(NSString *)keyID;
@end

@interface KeyManagerSecurityTests : XCTestCase
@end

@implementation KeyManagerSecurityTests

- (PDSDatabase *)openTemporaryDatabaseAtPath:(NSString **)pathOut {
    NSString *name = [@"KeyManagerSecurityTests_" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:path]];
    NSError *openError = nil;
    BOOL opened = [database openWithError:&openError];
    XCTAssertTrue(opened, @"Failed to open test database: %@", openError);
    if (pathOut) {
        *pathOut = path;
    }
    return database;
}

- (void)testFactorySelectionWithKeychainDisabled {
    NSString *dbPath = nil;
    PDSDatabase *database = [self openTemporaryDatabaseAtPath:&dbPath];
    BOOL originalUseKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
    @try {
        [PDSConfiguration sharedConfiguration].useKeychain = NO;

        id<PDSKeyManager> manager = [PDSKeyManagerFactory createKeyManagerWithDatabase:database];
#if defined(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
        XCTAssertTrue([manager isKindOfClass:[PDSOpenSSLSessionKeyManager class]]);
#elif defined(__APPLE__) && !defined(GNUSTEP)
        XCTAssertTrue([manager isKindOfClass:[PDSAppleKeyManager class]]);
#else
        XCTSkip(@"OpenSSL-backed session key manager unavailable in this build configuration.");
#endif
    } @finally {
        [PDSConfiguration sharedConfiguration].useKeychain = originalUseKeychain;
        [database close];
        [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
    }
}

- (void)testNonKeychainFactoryPersistenceWhenOpenSSLAvailable {
#if !defined(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
    XCTSkip(@"OpenSSL session key manager unavailable; skipping persistence test.");
#else
    NSString *dbPath = nil;
    PDSDatabase *database = [self openTemporaryDatabaseAtPath:&dbPath];
    BOOL originalUseKeychain = [PDSConfiguration sharedConfiguration].useKeychain;
    @try {
        [PDSConfiguration sharedConfiguration].useKeychain = NO;

        id<PDSKeyManager> manager = [PDSKeyManagerFactory createKeyManagerWithDatabase:database];
        XCTAssertTrue([manager isKindOfClass:[PDSOpenSSLSessionKeyManager class]]);

        NSError *generationError = nil;
        id<PDSKeyPair> generated = [manager generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&generationError];
        XCTAssertNotNil(generated);
        XCTAssertNil(generationError);

        NSError *queryError = nil;
        NSArray<NSDictionary *> *rows = [database executeParameterizedQuery:
            @"SELECT private_key_data, keychain_tag FROM jwt_signing_keys WHERE key_id = ?"
            params:@[generated.keyID]
            error:&queryError];
        XCTAssertNil(queryError);
        XCTAssertEqual(rows.count, (NSUInteger)1);

        NSDictionary *row = rows.firstObject;
        id privateKeyData = row[@"private_key_data"];
        id keychainTag = row[@"keychain_tag"];
        XCTAssertTrue([privateKeyData isKindOfClass:[NSData class]]);
        XCTAssertGreaterThan([(NSData *)privateKeyData length], (NSUInteger)0);
        XCTAssertTrue(keychainTag == nil || keychainTag == [NSNull null]);

        id<PDSKeyManager> reloaded = [PDSKeyManagerFactory createKeyManagerWithDatabase:database];
        NSError *reloadError = nil;
        id<PDSKeyPair> loaded = [reloaded getKeyPairWithID:generated.keyID error:&reloadError];
        XCTAssertNotNil(loaded);
        XCTAssertNil(reloadError);
    } @finally {
        [PDSConfiguration sharedConfiguration].useKeychain = originalUseKeychain;
        [database close];
        [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
    }
#endif
}

- (void)testKeychainTagUsesServiceNamespace {
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.atproto.pds.test.keys"];
    NSString *tag = [manager keychainTagForKeyID:@"abc123"];
    XCTAssertEqualObjects(tag, @"com.atproto.pds.test.keys.abc123");
}

- (void)testJWKUsesBase64URLWithoutPadding {
    NSError *error = nil;
    SecKeyRef privateKey = PDSTestCreateFixedP256PrivateKey(&error);
    XCTAssertNotNil((__bridge id)privateKey, @"Fixed key import must succeed: %@", error);
    SecKeyRef publicKey = privateKey ? SecKeyCopyPublicKey(privateKey) : NULL;
    XCTAssertNotNil((__bridge id)publicKey);

    NSString *keyID = [[NSUUID UUID] UUIDString];
    id<PDSKeyPair> pair = [PDSAppleKeyPair keyPairFromPrivateKey:privateKey
                                                        publicKey:publicKey
                                                            keyID:keyID
                                                         algorithm:@"ES256"];
    if (privateKey) {
        CFRelease(privateKey);
    }
    if (publicKey) {
        CFRelease(publicKey);
    }
    XCTAssertNotNil(pair);
    XCTAssertNil(error);

    NSDictionary *jwk = [pair publicKeyJWK];
    XCTAssertNotNil(jwk);

    NSString *modulus = jwk[@"n"];
    XCTAssertNotNil(modulus);
    XCTAssertFalse([modulus containsString:@"+"]);
    XCTAssertFalse([modulus containsString:@"/"]);
    XCTAssertFalse([modulus containsString:@"="]);

    NSString *thumbprint = [pair publicKeyThumbprint];
    XCTAssertNotNil(thumbprint);
    XCTAssertFalse([thumbprint containsString:@"+"]);
    XCTAssertFalse([thumbprint containsString:@"/"]);
    XCTAssertFalse([thumbprint containsString:@"="]);
}

@end
