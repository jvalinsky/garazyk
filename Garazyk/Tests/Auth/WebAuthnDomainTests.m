// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/WebAuthnDomain.h"
#import "Auth/Base32Utils.h"

@interface WebAuthnDomainTests : XCTestCase
@end

@implementation WebAuthnDomainTests

- (ATProtoWebAuthnRegistrationOptions *)sampleRegistrationOptions {
    ATProtoWebAuthnRelyingParty *rp = [[ATProtoWebAuthnRelyingParty alloc] init];
    rp.name = @"Test RP";
    rp.identifier = @"example.com";

    ATProtoWebAuthnUser *user = [[ATProtoWebAuthnUser alloc] init];
    user.identifier = [@"user-id" dataUsingEncoding:NSUTF8StringEncoding];
    user.name = @"user@example.com";
    user.displayName = @"User Name";

    ATProtoWebAuthnPubKeyCredParam *param1 = [[ATProtoWebAuthnPubKeyCredParam alloc] init];
    param1.type = @"public-key";
    param1.alg = -7;

    ATProtoWebAuthnPubKeyCredParam *param2 = [[ATProtoWebAuthnPubKeyCredParam alloc] init];
    param2.type = @"public-key";
    param2.alg = -8;

    ATProtoWebAuthnRegistrationOptions *options = [[ATProtoWebAuthnRegistrationOptions alloc] init];
    options.challenge = [@"challenge-bytes" dataUsingEncoding:NSUTF8StringEncoding];
    options.rp = rp;
    options.user = user;
    options.pubKeyCredParams = @[ param1, param2 ];
    options.timeout = 12.5;
    options.attestation = @"direct";
    return options;
}

- (void)testDictionaryFromRegistrationOptionsIncludesAllFields {
    ATProtoWebAuthnRegistrationOptions *options = [self sampleRegistrationOptions];
    NSDictionary *dict = [ATProtoWebAuthnDomain dictionaryFromRegistrationOptions:options];

    XCTAssertEqualObjects(dict[@"challenge"], [ATProtoBase32Utils base32StringFromData:options.challenge]);
    XCTAssertEqualObjects(dict[@"rp"][@"name"], @"Test RP");
    XCTAssertEqualObjects(dict[@"rp"][@"id"], @"example.com");
    XCTAssertEqualObjects(dict[@"user"][@"id"], [ATProtoBase32Utils base32StringFromData:options.user.identifier]);
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
    ATProtoWebAuthnRegistrationOptions *options = [self sampleRegistrationOptions];
    options.attestation = nil;

    NSDictionary *dict = [ATProtoWebAuthnDomain dictionaryFromRegistrationOptions:options];
    XCTAssertEqualObjects(dict[@"attestation"], @"none");
}

- (void)testDictionaryFromAssertionOptionsWithAllowCredentialsAndTransports {
    ATProtoWebAuthnCredentialDescriptor *descriptor = [[ATProtoWebAuthnCredentialDescriptor alloc] init];
    descriptor.type = @"public-key";
    descriptor.credentialId = [@"cred-id" dataUsingEncoding:NSUTF8StringEncoding];
    descriptor.transports = @[ @"usb", @"internal" ];

    ATProtoWebAuthnAssertionOptions *options = [[ATProtoWebAuthnAssertionOptions alloc] init];
    options.challenge = [@"assertion-challenge" dataUsingEncoding:NSUTF8StringEncoding];
    options.timeout = 3.2;
    options.rpId = @"example.com";
    options.allowCredentials = @[ descriptor ];
    options.userVerification = @"required";

    NSDictionary *dict = [ATProtoWebAuthnDomain dictionaryFromAssertionOptions:options];

    XCTAssertEqualObjects(dict[@"challenge"], [ATProtoBase32Utils base32StringFromData:options.challenge]);
    XCTAssertEqualObjects(dict[@"timeout"], @(3200));
    XCTAssertEqualObjects(dict[@"rpId"], @"example.com");
    XCTAssertEqualObjects(dict[@"userVerification"], @"required");
    XCTAssertNotNil(dict[@"allowCredentials"]);
    XCTAssertEqual([dict[@"allowCredentials"] count], 1);
    XCTAssertEqualObjects(dict[@"allowCredentials"][0][@"type"], @"public-key");
    XCTAssertEqualObjects(dict[@"allowCredentials"][0][@"id"],
                          [ATProtoBase32Utils base32StringFromData:descriptor.credentialId]);
    XCTAssertEqualObjects(dict[@"allowCredentials"][0][@"transports"], descriptor.transports);
}

- (void)testDictionaryFromAssertionOptionsDefaultsAndSkipsEmptyAllowCredentials {
    ATProtoWebAuthnAssertionOptions *options = [[ATProtoWebAuthnAssertionOptions alloc] init];
    options.challenge = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
    options.timeout = 1.0;
    options.rpId = @"example.com";
    options.allowCredentials = @[];
    options.userVerification = nil;

    NSDictionary *dict = [ATProtoWebAuthnDomain dictionaryFromAssertionOptions:options];

    XCTAssertEqualObjects(dict[@"userVerification"], @"preferred");
    XCTAssertNil(dict[@"allowCredentials"]);
}

- (void)testDictionaryFromAssertionOptionsOmitsTransportsWhenNil {
    ATProtoWebAuthnCredentialDescriptor *descriptor = [[ATProtoWebAuthnCredentialDescriptor alloc] init];
    descriptor.type = @"public-key";
    descriptor.credentialId = [@"cred-id-2" dataUsingEncoding:NSUTF8StringEncoding];
    descriptor.transports = nil;

    ATProtoWebAuthnAssertionOptions *options = [[ATProtoWebAuthnAssertionOptions alloc] init];
    options.challenge = [@"challenge" dataUsingEncoding:NSUTF8StringEncoding];
    options.timeout = 1.5;
    options.rpId = @"example.com";
    options.allowCredentials = @[ descriptor ];
    options.userVerification = @"discouraged";

    NSDictionary *dict = [ATProtoWebAuthnDomain dictionaryFromAssertionOptions:options];
    NSDictionary *credDict = dict[@"allowCredentials"][0];
    XCTAssertNil(credDict[@"transports"]);
}

@end
