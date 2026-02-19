#import <XCTest/XCTest.h>

#import "Auth/PDSOpenSSLKeyManager.h"

@interface PDSOpenSSLKeyManagerTests : XCTestCase
@end

@implementation PDSOpenSSLKeyManagerTests

- (void)testGenerateAndLoadKeyMaterial {
    NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    PDSOpenSSLKeyManager *manager = [[PDSOpenSSLKeyManager alloc] initWithDid:@"did:plc:linux-ci" keystorePath:tmpDir];

    NSError *error = nil;
    XCTAssertTrue([manager generateSigningKeyWithError:&error]);
    XCTAssertNil(error);

    NSData *publicKey = [manager publicSigningKeyWithError:&error];
    XCTAssertNotNil(publicKey);
    XCTAssertNil(error);
    XCTAssertEqual(publicKey.length, (NSUInteger)33);

    NSString *didKey = [manager didKeyStringWithError:&error];
    XCTAssertNotNil(didKey);
    XCTAssertNil(error);
    XCTAssertTrue([didKey hasPrefix:@"did:key:z"]);
}

- (void)testImportRejectsWrongKeyLength {
    NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    PDSOpenSSLKeyManager *manager = [[PDSOpenSSLKeyManager alloc] initWithDid:@"did:plc:linux-ci" keystorePath:tmpDir];

    NSError *error = nil;
    NSData *badKey = [@"short" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertFalse([manager importSigningKey:badKey error:&error]);
    XCTAssertNotNil(error);
}

@end
