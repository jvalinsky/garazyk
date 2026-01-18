#import <XCTest/XCTest.h>
#import "Auth/KeyManager.h"

@interface KeyManagerSecurityTests : XCTestCase
@end

@implementation KeyManagerSecurityTests

- (void)testJWKUsesBase64URLWithoutPadding {
    KeyManager *manager = [[KeyManager alloc] initWithServiceIdentifier:@"com.atproto.pds.test.keys"];
    NSError *error = nil;
    KeyPair *pair = [manager generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
