#import <XCTest/XCTest.h>
#import "Auth/PDSAppleKeyManager.h"

@interface KeyManagerSecurityTests : XCTestCase
@end

@implementation KeyManagerSecurityTests

- (void)testJWKUsesBase64URLWithoutPadding {
    PDSAppleKeyManager *manager = [[PDSAppleKeyManager alloc] initWithServiceIdentifier:@"com.atproto.pds.test.keys"];
    NSError *error = nil;
    id<PDSKeyPair> pair = [manager generateKeyPairWithAlgorithm:@"RS256" keySize:2048 error:&error];
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
