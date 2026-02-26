#import <XCTest/XCTest.h>
#import "Auth/WebAuthnDomain.h"
#import "Auth/Base32Utils.h"

@interface WebAuthnDomainTests : XCTestCase
@end

@implementation WebAuthnDomainTests

- (WebAuthnRegistrationOptions *)sampleRegistrationOptions {
    WebAuthnRelyingParty *rp = [[WebAuthnRelyingParty alloc] init];
    rp.name = @"Test RP";
    rp.identifier = @"example.com";

    WebAuthnUser *user = [[WebAuthnUser alloc] init];
    user.identifier = [@"user-id" dataUsingEncoding:NSUTF8StringEncoding];
    user.name = @"user@example.com";
    user.displayName = @"User Name";

    WebAuthnPubKeyCredParam *param1 = [[WebAuthnPubKeyCredParam alloc] init];
    param1.type = @"public-key";
    param1.alg = -7;

    WebAuthnPubKeyCredParam *param2 = [[WebAuthnPubKeyCredParam alloc] init];
    param2.type = @"public-key";
    param2.alg = -8;

    WebAuthnRegistrationOptions *options = [[WebAuthnRegistrationOptions alloc] init];
    options.challenge = [@"challenge-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    options.rp = rp;
    options.user = user;
    options.pubKeyCredParams = @[ param1, param2 ];
    options.timeout = 12.5;
    options.attestation = @"direct";
    return options;
}

- (void)testDictionaryFromRegistrationOptionsIncludesAllFields {
    WebAuthnRegistrationOptions *options = [self sampleRegistrationOptions];
    NSDictionary *dict = [WebAuthnDomain dictionaryFromRegistrationOptions:options];

    XCTAssertEqualObjects(dict[@"challenge"], [Base32Utils base32StringFromData:options.challenge]);
    XCTAssertEqualObjects(dict[@"rp"][@"name"], @"Test RP");
    XCTAssertEqualObjects(dict[@"rp"][@"id"], @"example.com");
    XCTAssertEqualObjects(dict[@"user"][@"id"], [Base32Utils base32StringFromData:options.user.identifier]);
    XCTAssertEqualObjects(dict[@"user"][@"name"], @"user@example.com");
    XCTAssertEqualObjects(dict[@"user"][@"displayName"], @"User Name");
    XCTAssertEqualObjects(dict[@"attestation"], @"direct");
    XCTAssertEqualObjects(dict[@"timeout"], @(12500));
    XCTAssertEqual([dict[@"pubKeyCredParams"] count], 2);
    XCTAssertEqualObjects(dict[@"pubKeyCredParams"][0][@"type"], @"public-key");
    XCTAssertEqualObjects(dict[@"pubKeyCredParams"][0][@"alg"], @(-7));
    XCTAssertEqualObjects(dict[@"pubKeyCredParams"][1][@"alg"], @(-8));
}

- (void)testDictionaryFromRegistrationOptionsDefaultsAttestationToNone {
    WebAuthnRegistrationOptions *options = [self sampleRegistrationOptions];
    options.attestation = nil;

    NSDictionary *dict = [WebAuthnDomain dictionaryFromRegistrationOptions:options];
    XCTAssertEqualObjects(dict[@"attestation"], @"none");
}

- (void)testDictionaryFromAssertionOptionsWithAllowCredentialsAndTransports {
    WebAuthnCredentialDescriptor *descriptor = [[WebAuthnCredentialDescriptor alloc] init];
    descriptor.type = @"public-key";
    descriptor.credentialId = [@"cred-id" dataUsingEncoding:NSUTF8StringEncoding];
    descriptor.transports = @[ @"usb", @"internal" ];

    WebAuthnAssertionOptions *options = [[WebAuthnAssertionOptions alloc] init];
    options.challenge = [@"assertion-challenge" dataUsingEncoding:NSUTF8StringEncoding];
    options.timeout = 3.2;
    options.rpId = @"example.com";
    options.allowCredentials = @[ descriptor ];
    options.userVerification = @"required";

    NSDictionary *dict = [WebAuthnDomain dictionaryFromAssertionOptions:options];

    XCTAssertEqualObjects(dict[@"challenge"], [Base32Utils base32StringFromData:options.challenge]);
    XCTAssertEqualObjects(dict[@"timeout"], @(3200));
    XCTAssertEqualObjects(dict[@"rpId"], @"example.com");
    XCTAssertEqualObjects(dict[@"userVerification"], @"required");
    XCTAssertNotNil(dict[@"allowCredentials"]);
    XCTAssertEqual([dict[@"allowCredentials"] count], 1);
    XCTAssertEqualObjects(dict[@"allowCredentials"][0][@"type"], @"public-key");
    XCTAssertEqualObjects(dict[@"allowCredentials"][0][@"id"],
                          [Base32Utils base32StringFromData:descriptor.credentialId]);
    XCTAssertEqualObjects(dict[@"allowCredentials"][0][@"transports"], descriptor.transports);
}

- (void)testDictionaryFromAssertionOptionsDefaultsAndSkipsEmptyAllowCredentials {
    WebAuthnAssertionOptions *options = [[WebAuthnAssertionOptions alloc] init];
    options.challenge = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
    options.timeout = 1.0;
    options.rpId = @"example.com";
    options.allowCredentials = @[];
    options.userVerification = nil;

    NSDictionary *dict = [WebAuthnDomain dictionaryFromAssertionOptions:options];

    XCTAssertEqualObjects(dict[@"userVerification"], @"preferred");
    XCTAssertNil(dict[@"allowCredentials"]);
}

- (void)testDictionaryFromAssertionOptionsOmitsTransportsWhenNil {
    WebAuthnCredentialDescriptor *descriptor = [[WebAuthnCredentialDescriptor alloc] init];
    descriptor.type = @"public-key";
    descriptor.credentialId = [@"cred-id-2" dataUsingEncoding:NSUTF8StringEncoding];
    descriptor.transports = nil;

    WebAuthnAssertionOptions *options = [[WebAuthnAssertionOptions alloc] init];
    options.challenge = [@"challenge" dataUsingEncoding:NSUTF8StringEncoding];
    options.timeout = 1.5;
    options.rpId = @"example.com";
    options.allowCredentials = @[ descriptor ];
    options.userVerification = @"discouraged";

    NSDictionary *dict = [WebAuthnDomain dictionaryFromAssertionOptions:options];
    NSDictionary *credDict = dict[@"allowCredentials"][0];
    XCTAssertNil(credDict[@"transports"]);
}

@end
