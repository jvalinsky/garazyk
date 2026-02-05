#import <XCTest/XCTest.h>
#import "Auth/JWT.h"

@interface JWTSecurityTests : XCTestCase
@property (nonatomic, strong) JWTVerifier *verifier;
@end

@implementation JWTSecurityTests

- (void)setUp {
    [super setUp];
    self.verifier = [[JWTVerifier alloc] init];
    self.verifier.allowedAlgorithms = @[@"ES256K", @"ES256"];
}

- (void)testAlgNoneRejection {
    // Create a JWT header with alg: none
    NSString *header = @"{\"alg\":\"none\",\"typ\":\"JWT\"}";
    NSString *payload = @"{\"sub\":\"1234567890\",\"name\":\"John Doe\",\"iat\":1516239022}";
    
    NSString *headerBase64 = [self base64UrlEncode:header];
    NSString *payloadBase64 = [self base64UrlEncode:payload];
    
    // No signature
    NSString *token = [NSString stringWithFormat:@"%@.%@.", headerBase64, payloadBase64];
    
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    
    // It might parse successfully (depending on implementation), but verification MUST fail
    BOOL verified = [self.verifier verifyJWT:jwt error:&error];
    
    XCTAssertFalse(verified, @"Should not verify token with alg: none");
}

- (void)testSignatureStripping {
    JWTVerifier *verifierWithKey = [[JWTVerifier alloc] init];
    NSData *dummyKey = [NSMutableData dataWithLength:65];
    verifierWithKey.publicKey = dummyKey;

    NSString *header = @"{\"alg\":\"ES256\",\"typ\":\"JWT\"}";
    NSString *payload = @"{\"sub\":\"123\",\"iat\":100}";
    NSString *token = [NSString stringWithFormat:@"%@.%@.invalidsig", [self base64UrlEncode:header], [self base64UrlEncode:payload]];

    JWT *jwt = [JWT jwtWithToken:token error:nil];

    XCTAssertFalse([verifierWithKey verifyJWT:jwt error:nil], @"Invalid signature should be rejected");
}

- (void)testFailClosedWhenNoKeyConfigured {
    JWTVerifier *verifierWithoutKey = [[JWTVerifier alloc] init];

    NSString *header = @"{\"alg\":\"ES256\",\"typ\":\"JWT\"}";
    NSString *payload = @"{\"sub\":\"123\",\"iat\":1516239022}";
    NSString *token = [NSString stringWithFormat:@"%@.%@.anysignature", [self base64UrlEncode:header], [self base64UrlEncode:payload]];

    JWT *jwt = [JWT jwtWithToken:token error:nil];
    NSError *error = nil;
    BOOL verified = [verifierWithoutKey verifyJWT:jwt error:&error];

    XCTAssertFalse(verified, @"Should fail verification when no key is configured");
    XCTAssertNotNil(error, @"Should return error when no key is configured");
    XCTAssertEqual(error.code, JWTErrorNoPublicKey, @"Error should indicate no public key configured");
}

- (void)testInvalidSignature {
    // Setup verifier with a dummy public key (random bytes) just to trigger verification path
    NSData *dummyKey = [NSMutableData dataWithLength:32];
    self.verifier.publicKey = dummyKey;
    
    NSString *header = @"{\"alg\":\"ES256\",\"typ\":\"JWT\"}";
    NSString *payload = @"{\"sub\":\"123\",\"iat\":100}";
    NSString *token = [NSString stringWithFormat:@"%@.%@.invalidsig", [self base64UrlEncode:header], [self base64UrlEncode:payload]];
    
    JWT *jwt = [JWT jwtWithToken:token error:nil];
    BOOL verified = [self.verifier verifyJWT:jwt error:nil];
    
    XCTAssertFalse(verified, @"Should reject invalid signature");
}

#pragma mark - Helpers

- (NSString *)base64UrlEncode:(NSString *)str {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return base64;
}

@end
