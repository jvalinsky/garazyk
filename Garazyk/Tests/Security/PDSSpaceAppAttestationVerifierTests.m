// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#import "Security/Space/PDSSpaceAppAttestationVerifier.h"
#import "Services/PDS/PDSSpaceStore.h"
#import "Auth/JWT.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/PDSKeyProtocol.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

// Fixed test-only P-256 key pair (generated once via `openssl ecparam
// -genkey`, not reused anywhere production-facing). x/y/d are base64url
// per RFC 7518.
static NSString * const kTestJWKKid = @"test-app-key-1";
static NSString * const kTestJWKX = @"sCkXlWdTiv6k4_7Aj0qbk-6Rp-s2xnOHNzI30SksjzE";
static NSString * const kTestJWKY = @"eJHxfJbaq5y8xhEFiwhVcA1xpx_Jpj5GVDaUC_0rqrI";
static NSString * const kTestJWKD = @"GE8ea5wxqv-uyg35MjN4QwaINAa6wl4uSXJtZbDzNg4";

@interface PDSSpaceAppAttestationVerifierTests : XCTestCase
@property(nonatomic, copy) NSString *temporaryDirectory;
@property(nonatomic, strong) PDSSpaceStore *store;
@property(nonatomic, strong) PDSSpaceAppAttestationVerifier *verifier;
@end

@implementation PDSSpaceAppAttestationVerifierTests

- (void)setUp {
  [super setUp];
  self.temporaryDirectory = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-app-attest-%@", NSUUID.UUID.UUIDString]];
  NSError *error = nil;
  self.store = [[PDSSpaceStore alloc]
      initWithDatabasePath:[self.temporaryDirectory stringByAppendingPathComponent:@"spaces.sqlite"]
                  error:&error];
  XCTAssertNil(error);
  self.verifier = [[PDSSpaceAppAttestationVerifier alloc] initWithSpaceStore:self.store];
}

- (void)tearDown {
  [[NSFileManager defaultManager] removeItemAtPath:self.temporaryDirectory error:nil];
  [super tearDown];
}

#pragma mark - Helpers

- (NSDictionary *)testJWKSWithKid:(NSString *)kid {
  return @{ @"keys" : @[ @{
    @"kty" : @"EC", @"crv" : @"P-256", @"kid" : kid ?: kTestJWKKid,
    @"use" : @"sig", @"x" : kTestJWKX, @"y" : kTestJWKY,
  } ] };
}

- (NSString *)signedAttestationWithIssuer:(NSString *)issuer
                                  subject:(nullable NSString *)subject
                                 audience:(nullable NSString *)audience
                                      kid:(nullable NSString *)kid
                                      alg:(nullable NSString *)alg
                                      jti:(nullable NSString *)jti
                              issuedDelta:(NSTimeInterval)issuedDelta
                                lifetime:(NSTimeInterval)lifetime {
  NSDate *now = [NSDate date];
  NSDate *issuedAt = [now dateByAddingTimeInterval:issuedDelta];
  NSDictionary *header = @{ @"alg" : alg ?: @"ES256", @"typ" : @"atproto-space-app-attestation+jwt", @"kid" : kid ?: kTestJWKKid };
  NSMutableDictionary *payload = [@{
    @"iss" : issuer,
    @"sub" : subject ?: issuer,
    @"aud" : audience ?: @"did:web:host.example#atproto_space_host",
    @"iat" : @((NSInteger)floor(issuedAt.timeIntervalSince1970)),
    @"exp" : @((NSInteger)floor([issuedAt dateByAddingTimeInterval:lifetime].timeIntervalSince1970)),
    @"jti" : jti ?: NSUUID.UUID.UUIDString,
  } mutableCopy];

  NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:nil];
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  NSString *encodedHeader = [JWT base64URLEncodeData:headerData error:nil];
  NSString *encodedPayload = [JWT base64URLEncodeData:payloadData error:nil];
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", encodedHeader, encodedPayload];

  NSDictionary *privateJWK = @{ @"kty" : @"EC", @"crv" : @"P-256", @"x" : kTestJWKX, @"y" : kTestJWKY, @"d" : kTestJWKD };
  id<PDSPrivateKeyProtocol> privateKey = [AuthCryptoJWK privateKeyFromJWK:privateJWK error:nil];
  XCTAssertNotNil(privateKey);
  NSData *signature = [privateKey signData:[signingInput dataUsingEncoding:NSUTF8StringEncoding] error:nil];
  XCTAssertEqual(signature.length, (NSUInteger)64);
  NSString *encodedSignature = [JWT base64URLEncodeData:signature error:nil];
  return [NSString stringWithFormat:@"%@.%@", signingInput, encodedSignature];
}

#pragma mark - Core claim/signature verification (no network)

- (void)testValidAttestationVerifies {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertTrue(ok, @"%@", error);
  XCTAssertNil(error);
}

- (void)testWrongIssuerRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://other-app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorIssuer);
}

- (void)testSubjectMustEqualIssuer {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:@"https://someone-else.example.com"
                                              audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorSubject);
}

- (void)testWrongAudienceRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:other-host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorAudience);
}

- (void)testExpiredAttestationRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:-600 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorExpired);
}

- (void)testOverlongLifetimeRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:3600];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorLifetime);
}

- (void)testWrongAlgorithmRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:@"none" jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorMalformed);
}

- (void)testUnknownKeyIDRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:@"not-in-jwks" alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:kTestJWKKid]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorKeyNotFound);
}

- (void)testReplayedJTIRejectedOnSecondUse {
  NSString *jti = NSUUID.UUID.UUIDString;
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:jti issuedDelta:0 lifetime:60];
  NSError *firstError = nil;
  BOOL first = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                          expectedIssuer:@"https://app.example.com"
                        expectedAudience:@"did:web:host.example#atproto_space_host" error:&firstError];
  XCTAssertTrue(first, @"%@", firstError);

  NSError *secondError = nil;
  BOOL second = [self.verifier verifyJWT:token jwks:[self testJWKSWithKid:nil]
                           expectedIssuer:@"https://app.example.com"
                         expectedAudience:@"did:web:host.example#atproto_space_host" error:&secondError];
  XCTAssertFalse(second, @"A second use of the same jti must be rejected as a replay");
  XCTAssertEqual(secondError.code, PDSSpaceAppAttestationErrorReplay);
}

- (void)testTamperedSignatureRejected {
  NSString *token = [self signedAttestationWithIssuer:@"https://app.example.com" subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
  NSString *tamperedPayload = [[parts[1] stringByAppendingString:@"AA"] stringByReplacingOccurrencesOfString:@"A" withString:@"B" options:0 range:NSMakeRange(0, 1)];
  NSString *tampered = [NSString stringWithFormat:@"%@.%@.%@", parts[0], tamperedPayload, parts[2]];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyJWT:tampered jwks:[self testJWKSWithKid:nil]
                       expectedIssuer:@"https://app.example.com"
                     expectedAudience:@"did:web:host.example#atproto_space_host" error:&error];
  XCTAssertFalse(ok);
}

#pragma mark - End-to-end: real client-metadata + JWKS fetch over HTTP

- (void)testEndToEndFetchesMetadataAndJWKSThenVerifies {
  setenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS", "1", 1);
  HttpServer *server = [HttpServer serverWithHost:@"127.0.0.1" port:0];
  NSDictionary *jwks = [self testJWKSWithKid:nil];
  __block NSString *clientID = nil;
  [server addRoute:@"GET" path:@"/client-metadata.json" handler:^(HttpRequest *request, HttpResponse *response) {
    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{ @"client_id" : clientID, @"jwks" : jwks }];
  }];
  NSError *startError = nil;
  XCTAssertTrue([server startWithError:&startError], @"%@", startError);
  clientID = [NSString stringWithFormat:@"http://127.0.0.1:%lu/client-metadata.json", (unsigned long)server.port];

  NSString *token = [self signedAttestationWithIssuer:clientID subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyAttestationJWT:token forAppClientID:clientID
                                       audience:@"did:web:host.example#atproto_space_host" error:&error];
  [server stop];
  unsetenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS");
  XCTAssertTrue(ok, @"%@", error);
}

- (void)testEndToEndRejectsMismatchedMetadataClientID {
  setenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS", "1", 1);
  HttpServer *server = [HttpServer serverWithHost:@"127.0.0.1" port:0];
  NSDictionary *jwks = [self testJWKSWithKid:nil];
  [server addRoute:@"GET" path:@"/client-metadata.json" handler:^(HttpRequest *request, HttpResponse *response) {
    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{ @"client_id" : @"https://not-the-real-url.example.com", @"jwks" : jwks }];
  }];
  NSError *startError = nil;
  XCTAssertTrue([server startWithError:&startError], @"%@", startError);
  NSString *clientID = [NSString stringWithFormat:@"http://127.0.0.1:%lu/client-metadata.json", (unsigned long)server.port];

  NSString *token = [self signedAttestationWithIssuer:clientID subject:nil audience:@"did:web:host.example#atproto_space_host"
                                                    kid:nil alg:nil jti:nil issuedDelta:0 lifetime:60];
  NSError *error = nil;
  BOOL ok = [self.verifier verifyAttestationJWT:token forAppClientID:clientID
                                       audience:@"did:web:host.example#atproto_space_host" error:&error];
  [server stop];
  unsetenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS");
  XCTAssertFalse(ok, @"Metadata whose own client_id disagrees with the URL it was served from must be rejected");
  XCTAssertEqual(error.code, PDSSpaceAppAttestationErrorMetadataInvalid);
}

@end
