// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/WebAuthnVerifier.h"
#import "Repository/CBOR.h"

NS_ASSUME_NONNULL_BEGIN

@interface WebAuthnVerifierTests : XCTestCase
@end

@implementation WebAuthnVerifierTests

- (NSString *)base64URLStringFromData:(NSData *)data {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
    return base64;
}

- (NSDictionary *)registrationResponseWithChallenge:(NSData *)challenge
                                             origin:(NSString *)origin
                                        attestation:(NSData *)attestation {
    NSDictionary *clientData = @{
        @"type": @"webauthn.create",
        @"challenge": [self base64URLStringFromData:challenge],
        @"origin": origin
    };
    NSData *clientDataJSON = [NSJSONSerialization dataWithJSONObject:clientData options:0 error:nil];
    NSString *clientDataB64 = [clientDataJSON base64EncodedStringWithOptions:0];
    NSString *attestationB64 = [attestation base64EncodedStringWithOptions:0];
    return @{
        @"response": @{
            @"clientDataJSON": clientDataB64,
            @"attestationObject": attestationB64
        }
    };
}

- (NSData *)attestationObjectWithAuthData:(NSData *)authData {
    CBORValue *map = [CBORValue map:@{
        [CBORValue textString:@"authData"]: [CBORValue byteString:authData]
    }];
    return [map encode];
}

- (void)testRegistrationSuccessParsesAuthData {
    NSData *expectedChallenge = [@"expected" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *expectedOrigin = @"https://example.com";

    NSMutableData *authData = [NSMutableData dataWithLength:37];
    uint8_t *bytes = authData.mutableBytes;
    bytes[32] = 0x40; // has attested credential data

    NSData *aaguid = [NSMutableData dataWithLength:16];
    uint16_t credLen = CFSwapInt16HostToBig(4);
    NSData *credentialId = [@"cred" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *publicKey = [@"keydata" dataUsingEncoding:NSUTF8StringEncoding];

    [authData appendData:aaguid];
    [authData appendBytes:&credLen length:2];
    [authData appendData:credentialId];
    [authData appendData:publicKey];

    NSData *attestation = [self attestationObjectWithAuthData:authData];
    NSDictionary *response = [self registrationResponseWithChallenge:expectedChallenge
                                                              origin:expectedOrigin
                                                         attestation:attestation];

    NSError *error = nil;
    NSDictionary *result = [WebAuthnVerifier verifyRegistrationResponse:response
                                                              challenge:expectedChallenge
                                                                 origin:expectedOrigin
                                                                  error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
    XCTAssertEqualObjects(result[@"credentialId"], credentialId);
    XCTAssertEqualObjects(result[@"publicKey"], publicKey);
}

- (void)testRegistrationRejectsMissingAuthData {
    NSData *expectedChallenge = [@"expected" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *expectedOrigin = @"https://example.com";

    CBORValue *map = [CBORValue map:@{}];
    NSData *attestation = [map encode];
    NSDictionary *response = [self registrationResponseWithChallenge:expectedChallenge
                                                              origin:expectedOrigin
                                                         attestation:attestation];

    NSError *error = nil;
    NSDictionary *result = [WebAuthnVerifier verifyRegistrationResponse:response
                                                              challenge:expectedChallenge
                                                                 origin:expectedOrigin
                                                                  error:&error];
    XCTAssertNil(result);
    XCTAssertEqual(error.code, 1006);
}

- (void)testRegistrationReturnsErrorCode1007ForShortAuthData {
    NSData *expectedChallenge = [@"expected" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *expectedOrigin = @"https://example.com";

    NSData *shortAuthData = [NSMutableData dataWithLength:10];
    NSData *attestation = [self attestationObjectWithAuthData:shortAuthData];
    NSDictionary *response = [self registrationResponseWithChallenge:expectedChallenge
                                                              origin:expectedOrigin
                                                         attestation:attestation];

    NSError *error = nil;
    NSDictionary *result = [WebAuthnVerifier verifyRegistrationResponse:response
                                                              challenge:expectedChallenge
                                                                 origin:expectedOrigin
                                                                  error:&error];
    XCTAssertNil(result);
    XCTAssertEqual(error.code, 1007);
}

- (void)testRegistrationRejectsMissingAttestedCredentialDataFlag {
    NSData *expectedChallenge = [@"expected" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *expectedOrigin = @"https://example.com";

    NSMutableData *authData = [NSMutableData dataWithLength:37];
    uint8_t *bytes = authData.mutableBytes;
    bytes[32] = 0x00;

    NSData *attestation = [self attestationObjectWithAuthData:authData];
    NSDictionary *response = [self registrationResponseWithChallenge:expectedChallenge
                                                              origin:expectedOrigin
                                                         attestation:attestation];

    NSError *error = nil;
    NSDictionary *result = [WebAuthnVerifier verifyRegistrationResponse:response
                                                              challenge:expectedChallenge
                                                                 origin:expectedOrigin
                                                                  error:&error];
    XCTAssertNil(result);
    XCTAssertEqual(error.code, 1008);
}

- (void)testAssertionRejectsInvalidType {
    NSDictionary *clientData = @{
        @"type": @"webauthn.create",
        @"challenge": [self base64URLStringFromData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]],
        @"origin": @"https://example.com"
    };
    NSData *clientDataJSON = [NSJSONSerialization dataWithJSONObject:clientData options:0 error:nil];
    NSString *clientDataB64 = [clientDataJSON base64EncodedStringWithOptions:0];

    NSData *authData = [NSMutableData dataWithLength:37];
    NSString *authDataB64 = [authData base64EncodedStringWithOptions:0];
    NSString *signatureB64 = [[@"sig" dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];

    NSDictionary *response = @{
        @"response": @{
            @"clientDataJSON": clientDataB64,
            @"authenticatorData": authDataB64,
            @"signature": signatureB64
        }
    };

    NSError *error = nil;
    uint32_t outCount = 0;
    BOOL ok = [WebAuthnVerifier verifyAssertionResponse:response
                                              challenge:[@"expected" dataUsingEncoding:NSUTF8StringEncoding]
                                                 origin:@"https://example.com"
                                              publicKey:[NSData data]
                                              signCount:0
                                           newSignCount:&outCount
                                                  error:&error];
    XCTAssertFalse(ok);
    XCTAssertEqual(error.code, 2001);
}

@end

NS_ASSUME_NONNULL_END
