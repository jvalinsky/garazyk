// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Auth/JWT.h"
#import "Auth/Secp256k1.h"
#import "Auth/DPoPUtil.h"
#import "Auth/Crypto/AuthCryptoBase64URL.h"
#import "Auth/Crypto/AuthCryptoDPoP.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/CryptoUtils.h"
#import "Auth/Crypto/AuthCryptoECDSA.h"
#import "Auth/TestKeyFixtures.h"
#import "Auth/Verifier/AuthVerifier.h"
#import "Auth/Verifier/AuthVerifierProtocols.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"

@interface AuthParityAdminController : NSObject
@property (nonatomic, assign) BOOL takedownActive;
@property (nonatomic, assign) BOOL admin;
@end

@implementation AuthParityAdminController

- (BOOL)isAccountTakedownActive:(NSString *)did error:(NSError **)error {
    return self.takedownActive;
}

- (BOOL)isAdmin:(NSString *)did error:(NSError **)error {
    return self.admin;
}

@end

@interface AuthParityAccountPolicy : NSObject <AccountPolicy>
@property (nonatomic, assign) BOOL accountAllowed;
@property (nonatomic, assign) BOOL admin;
@end

@implementation AuthParityAccountPolicy

- (BOOL)isAccountAllowed:(NSString *)did error:(NSError **)error {
    if (!self.accountAllowed && error) {
        *error = [NSError errorWithDomain:@"AuthParity" code:1 userInfo:nil];
    }
    return self.accountAllowed;
}

- (BOOL)isAdmin:(NSString *)did error:(NSError **)error {
    return self.admin;
}

@end

@interface AuthParitySessionRepository : NSObject
@property (nonatomic, assign) BOOL active;
@end

@implementation AuthParitySessionRepository

- (BOOL)isSessionActive:(NSString *)sid forAccountDid:(NSString *)did error:(NSError **)error {
    return self.active;
}

@end

@interface AuthParityKeyResolver : NSObject <TokenKeyResolver>
@property (nonatomic, copy) NSString *allowedIssuer;
@property (nonatomic, strong) NSDictionary *jwks;
@end

@implementation AuthParityKeyResolver

- (nullable NSDictionary *)jwksForIssuer:(NSString *)issuer error:(NSError **)error {
    return [issuer isEqualToString:self.allowedIssuer] ? self.jwks : nil;
}

- (BOOL)isIssuerAllowed:(NSString *)issuer {
    return [issuer isEqualToString:self.allowedIssuer];
}

@end

@interface AuthVerifierParityTests : XCTestCase
@property (nonatomic, strong) JWTMinter *minter;
@property (nonatomic, strong) AuthVerifier *verifier;
@property (nonatomic, strong) AuthParityAdminController *adminController;
@property (nonatomic, strong) AuthParityAccountPolicy *accountPolicy;
@property (nonatomic, strong) AuthParitySessionRepository *sessionRepository;
@end

@implementation AuthVerifierParityTests

- (void)setUp {
    [super setUp];
    Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
    self.minter = [[JWTMinter alloc] init];
    self.minter.issuer = @"https://pds.example.com";
    self.minter.audience = self.minter.issuer;
    self.minter.signingAlgorithm = @"ES256K";
    self.minter.privateKey = keyPair.privateKey;
    self.minter.publicKey = keyPair.publicKey;
    self.minter.defaultExpiration = 3600;

    self.adminController = [[AuthParityAdminController alloc] init];
    self.accountPolicy = [[AuthParityAccountPolicy alloc] init];
    self.accountPolicy.accountAllowed = YES;
    self.sessionRepository = [[AuthParitySessionRepository alloc] init];
    self.sessionRepository.active = YES;

    self.verifier = [[AuthVerifier alloc] initWithKeyResolver:nil
                                                accountPolicy:self.accountPolicy
                                                   nonceStore:nil];
    [self.verifier setLocalPublicKey:keyPair.publicKey];
    [self.verifier setLocalIssuer:self.minter.issuer];
    self.verifier.expectedAudience = self.minter.audience;
}

- (HttpRequest *)requestWithAuthorization:(NSString *)authorization dpop:(NSString *)dpop {
    NSMutableDictionary *headers = [@{
        @"Authorization": authorization,
        @"Host": @"pds.example.com"
    } mutableCopy];
    if (dpop) {
        headers[@"DPoP"] = dpop;
    }
    return [[HttpRequest alloc] initWithMethod:HttpMethodGET
                                  methodString:@"GET"
                                        path:@"/xrpc/com.atproto.server.getSession"
                                 queryString:@""
                                 queryParams:@{}
                                     version:@"1.1"
                                     headers:headers
                                        body:nil
                               remoteAddress:@"127.0.0.1"];
}

- (NSString *)legacyDIDForAuthorization:(NSString *)authorization request:(HttpRequest *)request {
    return [XrpcAuthHelper extractDIDFromAuthHeader:authorization
                                          jwtMinter:self.minter
                                    adminController:(id)self.adminController
                                  sessionRepository:(id)self.sessionRepository
                                            request:request
                                           response:[[HttpResponse alloc] init]];
}

- (AuthVerifierPrincipal *)newPrincipalForAuthorization:(NSString *)authorization request:(HttpRequest *)request {
    NSError *error = nil;
    return [self.verifier verifyAuthHeader:authorization
                                dpopHeader:[request headerForKey:@"DPoP"]
                                   request:request
                                  response:[[HttpResponse alloc] init]
                                     error:&error];
}

- (void)assertParityForToken:(NSString *)token expectedDID:(nullable NSString *)expectedDID {
    NSString *authorization = [@"Bearer " stringByAppendingString:token];
    HttpRequest *request = [self requestWithAuthorization:authorization dpop:nil];
    NSString *legacyDID = [self legacyDIDForAuthorization:authorization request:request];
    AuthVerifierPrincipal *principal = [self newPrincipalForAuthorization:authorization request:request];
    XCTAssertEqualObjects(legacyDID, expectedDID);
    XCTAssertEqualObjects(principal.did, expectedDID);
}

/// Manually constructs a JWT signed with a P-256 key, letting the caller set the
/// header's alg independently of the key's real curve — needed to test §4.4's
/// algorithm-confusion defense on the remote-issuer path, where a genuinely
/// valid P-256 signature can be mislabeled with a disallowed alg.
- (nullable NSString *)signedRemoteTokenWithIssuer:(NSString *)issuer
                                          audience:(NSString *)audience
                                               sub:(NSString *)sub
                                          tokenUse:(NSString *)tokenUse
                                               typ:(NSString *)typ
                                               alg:(NSString *)alg
                                        privateKey:(SecKeyRef)privateKey
                                             error:(NSError **)error {
    NSDictionary *headerDict = @{@"alg": alg, @"typ": typ};
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *payloadDict = @{
        @"iss": issuer,
        @"sub": sub,
        @"aud": audience,
        @"token_use": tokenUse,
        @"iat": @(now),
        @"exp": @(now + 3600)
    };
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerDict options:0 error:error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:error];
    if (!headerData || !payloadData) return nil;

    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEnc, payloadEnc];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    CFErrorRef signError = NULL;
    NSData *derSignature = CFBridgingRelease(SecKeyCreateSignature(privateKey,
                                                                     kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                     (__bridge CFDataRef)signingData,
                                                                     &signError));
    if (!derSignature) {
        if (error && signError) *error = CFBridgingRelease(signError);
        return nil;
    }
    NSData *rawSignature = [AuthCryptoECDSA rawSignatureFromDER:derSignature expectedSize:32 error:error];
    rawSignature = [AuthCryptoECDSA normalizeLowS:rawSignature error:error];
    if (!rawSignature) return nil;

    NSString *sigEnc = [AuthCryptoBase64URL encode:rawSignature];
    return [NSString stringWithFormat:@"%@.%@.%@", headerEnc, payloadEnc, sigEnc];
}

- (NSString *)thumbprintFromProof:(NSString *)proof error:(NSError **)error {
    NSArray<NSString *> *parts = [proof componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        return nil;
    }
    NSData *headerData = [AuthCryptoBase64URL decode:parts[0]];
    NSDictionary *header = [NSJSONSerialization JSONObjectWithData:headerData options:0 error:error];
    return header ? [AuthCryptoJWK thumbprint:header[@"jwk"] error:error] : nil;
}

- (void)testParityValidSessionToken {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                          sessionID:@"session-1"
                                  dpopKeyThumbprint:nil
                                               error:&error];
    XCTAssertNotNil(token, @"Token minting failed: %@", error);
    [self assertParityForToken:token.encodedToken expectedDID:@"did:plc:alice"];
}

- (void)testParityExpiredToken {
    NSError *error = nil;
    NSString *token = [self.minter signPayload:@{
        @"sub": @"did:plc:alice", @"iss": self.minter.issuer,
        @"aud": self.minter.audience,
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"exp": @([[[NSDate date] dateByAddingTimeInterval:-60] timeIntervalSince1970])
    } error:&error];
    XCTAssertNotNil(token, @"Token signing failed: %@", error);
    [self assertParityForToken:token expectedDID:nil];
}

- (void)testParitySuspendedAndTakenDownAccount {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                          sessionID:@"session-1"
                                  dpopKeyThumbprint:nil
                                               error:&error];
    XCTAssertNotNil(token);

    self.sessionRepository.active = NO;
    self.accountPolicy.accountAllowed = NO;
    [self assertParityForToken:token.encodedToken expectedDID:nil];

    self.sessionRepository.active = YES;
    self.adminController.takedownActive = YES;
    [self assertParityForToken:token.encodedToken expectedDID:nil];
}

- (void)testParityRejectsDpopBoundTokenWithoutProofAndOnRequestlessPath {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                  dpopKeyThumbprint:@"bound-thumbprint"
                                               error:&error];
    XCTAssertNotNil(token);
    [self assertParityForToken:token.encodedToken expectedDID:nil];

    NSError *verificationError = nil;
    XCTAssertNil([self.verifier verifyAccessToken:token.encodedToken error:&verificationError]);
    XCTAssertEqual(verificationError.code, AuthVerifierErrorDPoPRequired);
}

- (void)testParityAcceptsDpopBoundTokenWithMatchingProof {
    NSError *error = nil;
    SecKeyRef key = PDSTestCreateFixedP256PrivateKey(&error);
    if (!key) {
        XCTSkip(@"Fixed P-256 key unavailable: %@", error);
    }
    NSString *url = @"https://pds.example.com/xrpc/com.atproto.server.getSession";
    DPoPToken *legacyProof = [DPoPUtil createDPoPForMethod:@"GET" uri:url nonce:nil key:key error:&error];
    NSString *thumbprint = [self thumbprintFromProof:legacyProof.jwt error:&error];
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                  dpopKeyThumbprint:thumbprint
                                               error:&error];
    XCTAssertNotNil(token, @"Token minting failed: %@", error);

    NSString *authorization = [@"DPoP " stringByAppendingString:token.encodedToken];
    HttpRequest *legacyRequest = [self requestWithAuthorization:authorization dpop:legacyProof.jwt];
    XCTAssertEqualObjects([self legacyDIDForAuthorization:authorization request:legacyRequest], @"did:plc:alice");

    // The new verifier enforces ath (access token hash) per RFC 9449 §4.3.
    // Create a fresh DPoP proof with ath so the new verifier accepts it.
    // Keep the same token/key binding with a new JTI to avoid replay rejection.
    NSData *tokenData = [token.encodedToken dataUsingEncoding:NSUTF8StringEncoding];
    NSData *tokenHash = [CryptoUtils sha256:tokenData];
    NSString *athValue = [AuthCryptoBase64URL encode:tokenHash];

    // Build the DPoP proof manually with ath in the payload
    NSDictionary *jwk = [AuthCryptoJWK publicJWKFromSecKey:key error:&error];
    XCTAssertNotNil(jwk, @"Failed to get public JWK: %@", error);
    NSDictionary *headerDict = @{@"typ": @"dpop+jwt", @"alg": @"ES256", @"jwk": jwk};
    NSString *canonicalHTU = [AuthCryptoDPoP canonicalHTUFromURL:[NSURL URLWithString:url]];
    NSDictionary *payloadDict = @{
        @"htm": @"GET",
        @"htu": canonicalHTU,
        @"iat": @([[NSDate date] timeIntervalSince1970]),
        @"jti": [[NSUUID UUID] UUIDString],
        @"ath": athValue
    };
    NSData *headerData = [NSJSONSerialization dataWithJSONObject:headerDict options:0 error:&error];
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payloadDict options:0 error:&error];
    XCTAssertNotNil(headerData);
    XCTAssertNotNil(payloadData);
    NSString *headerEnc = [AuthCryptoBase64URL encode:headerData];
    NSString *payloadEnc = [AuthCryptoBase64URL encode:payloadData];
    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerEnc, payloadEnc];
    NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    CFErrorRef signError = NULL;
    NSData *derSignature = CFBridgingRelease(SecKeyCreateSignature(key,
                                                                     kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                     (__bridge CFDataRef)signingData,
                                                                     &signError));
    XCTAssertNotNil(derSignature, @"Signature failed");
    if (signError) CFRelease(signError);

    NSData *rawSignature = [AuthCryptoECDSA rawSignatureFromDER:derSignature expectedSize:32 error:&error];
    rawSignature = [AuthCryptoECDSA normalizeLowS:rawSignature error:&error];
    XCTAssertNotNil(rawSignature);
    NSString *proofWithAth = [NSString stringWithFormat:@"%@.%@.%@", headerEnc, payloadEnc,
                                                          [AuthCryptoBase64URL encode:rawSignature]];

    HttpRequest *newRequest = [self requestWithAuthorization:authorization dpop:proofWithAth];
    XCTAssertEqualObjects([self newPrincipalForAuthorization:authorization request:newRequest].did, @"did:plc:alice");
    CFRelease(key);
}

- (void)testParityRejectsDpopProofWithMismatchedThumbprint {
    NSError *error = nil;
    SecKeyRef key = PDSTestCreateFixedP256PrivateKey(&error);
    if (!key) {
        XCTSkip(@"Fixed P-256 key unavailable: %@", error);
    }
    NSString *url = @"https://pds.example.com/xrpc/com.atproto.server.getSession";
    DPoPToken *proof = [DPoPUtil createDPoPForMethod:@"GET" uri:url nonce:nil key:key error:&error];
    JWT *token = [self.minter mintAccessTokenForDID:@"did:plc:alice"
                                             handle:@"alice.example.com"
                                             scopes:@[]
                                  dpopKeyThumbprint:@"wrong-thumbprint"
                                               error:&error];
    NSString *authorization = [@"DPoP " stringByAppendingString:token.encodedToken];
    HttpRequest *request = [self requestWithAuthorization:authorization dpop:proof.jwt];
    XCTAssertNil([self legacyDIDForAuthorization:authorization request:request]);
    XCTAssertNil([self newPrincipalForAuthorization:authorization request:request]);
    CFRelease(key);
}

- (void)testParitySupportsDidWebSubjectAndCapturesAdminScope {
    NSError *error = nil;
    JWT *token = [self.minter mintAccessTokenForDID:@"did:web:pds.example.com%3A8443"
                                             handle:@"alice.example.com"
                                             scopes:@[@"admin:write"]
                                               error:&error];
    XCTAssertNotNil(token);
    self.accountPolicy.admin = YES;
    [self assertParityForToken:token.encodedToken expectedDID:@"did:web:pds.example.com%3A8443"];

    NSString *authorization = [@"Bearer " stringByAppendingString:token.encodedToken];
    AuthVerifierPrincipal *principal = [self newPrincipalForAuthorization:authorization
                                                                    request:[self requestWithAuthorization:authorization dpop:nil]];
    XCTAssertTrue(principal.isAdmin);
}

// §4.1/§4.4: the remote-issuer path (JWKS fetched from another PDS) enforces
// expectedTokenUse/expectedTyp and the alg allowlist just like the local
// path — phase-29 slice 4.

- (void)testRemoteIssuerRejectsRefreshTokenAtAccessTokenBoundary {
    NSError *error = nil;
    SecKeyRef privateKey = PDSTestCreateFixedP256PrivateKey(&error);
    XCTAssertNotNil((__bridge id)privateKey, @"Failed to create fixed P-256 key: %@", error);
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    NSDictionary *jwk = [AuthCryptoJWK publicJWKFromSecKey:publicKey error:&error];
    XCTAssertNotNil(jwk, @"Failed to derive public JWK: %@", error);

    NSString *remoteIssuer = @"https://other-pds.example.com";
    AuthParityKeyResolver *resolver = [[AuthParityKeyResolver alloc] init];
    resolver.allowedIssuer = remoteIssuer;
    resolver.jwks = @{@"keys": @[jwk]};

    AuthVerifier *remoteVerifier = [[AuthVerifier alloc] initWithKeyResolver:resolver
                                                                accountPolicy:self.accountPolicy
                                                                   nonceStore:nil];
    [remoteVerifier setLocalIssuer:self.minter.issuer];
    remoteVerifier.expectedAudience = self.minter.audience;

    // A refresh token, genuinely minted and signed by the remote PDS, presented
    // where an access token is expected.
    NSString *token = [self signedRemoteTokenWithIssuer:remoteIssuer
                                                audience:self.minter.audience
                                                     sub:@"did:plc:alice"
                                                tokenUse:@"refresh"
                                                     typ:@"refresh+jwt"
                                                     alg:@"ES256"
                                              privateKey:privateKey
                                                   error:&error];
    XCTAssertNotNil(token, @"Failed to sign remote token: %@", error);

    NSError *verifyError = nil;
    AuthVerifierPrincipal *principal = [remoteVerifier verifyAccessToken:token error:&verifyError];
    XCTAssertNil(principal, @"A remote-issued refresh token must not be accepted as an access token");
    XCTAssertNotNil(verifyError);

    CFRelease(privateKey);
    CFRelease(publicKey);
}

- (void)testRemoteIssuerRejectsDisallowedAlgorithm {
    NSError *error = nil;
    SecKeyRef privateKey = PDSTestCreateFixedP256PrivateKey(&error);
    XCTAssertNotNil((__bridge id)privateKey, @"Failed to create fixed P-256 key: %@", error);
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    NSDictionary *jwk = [AuthCryptoJWK publicJWKFromSecKey:publicKey error:&error];
    XCTAssertNotNil(jwk, @"Failed to derive public JWK: %@", error);

    NSString *remoteIssuer = @"https://other-pds.example.com";
    AuthParityKeyResolver *resolver = [[AuthParityKeyResolver alloc] init];
    resolver.allowedIssuer = remoteIssuer;
    resolver.jwks = @{@"keys": @[jwk]};

    AuthVerifier *remoteVerifier = [[AuthVerifier alloc] initWithKeyResolver:resolver
                                                                accountPolicy:self.accountPolicy
                                                                   nonceStore:nil];
    [remoteVerifier setLocalIssuer:self.minter.issuer];
    remoteVerifier.expectedAudience = self.minter.audience;

    // Every claim is otherwise valid (access/at+jwt, correct aud) and the
    // signature is a genuine P-256 signature the JWKS key verifies — only the
    // header's alg is mislabeled outside the allowlist, simulating an
    // algorithm-confusion attempt.
    NSString *token = [self signedRemoteTokenWithIssuer:remoteIssuer
                                                audience:self.minter.audience
                                                     sub:@"did:plc:alice"
                                                tokenUse:@"access"
                                                     typ:@"at+jwt"
                                                     alg:@"ES256K"
                                              privateKey:privateKey
                                                   error:&error];
    XCTAssertNotNil(token, @"Failed to sign remote token: %@", error);

    NSError *verifyError = nil;
    AuthVerifierPrincipal *principal = [remoteVerifier verifyAccessToken:token error:&verifyError];
    XCTAssertNil(principal, @"A token whose header alg is outside the remote allowlist must be rejected");
    XCTAssertNotNil(verifyError);

    CFRelease(privateKey);
    CFRelease(publicKey);
}

@end
