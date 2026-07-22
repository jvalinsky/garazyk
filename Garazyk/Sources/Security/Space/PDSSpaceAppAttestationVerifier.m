// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Security/Space/PDSSpaceAppAttestationVerifier.h"

#import <CommonCrypto/CommonDigest.h>

#import "Auth/JWT.h"
#import "Auth/Crypto/AuthCryptoJWK.h"
#import "Auth/PDSKeyProtocol.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Services/PDS/PDSSpaceStore.h"
#import "Debug/GZLogger.h"

NSString *const PDSSpaceAppAttestationErrorDomain = @"com.garazyk.space.appattestation";
NSString *const PDSSpaceAppAttestationJWTType = @"atproto-space-app-attestation+jwt";

// Short-lived by design: this is minted fresh per space-config request, not a
// long-lived credential, so a generous window only widens the replay window
// an attacker gets if a token ever leaks.
static const NSTimeInterval PDSSpaceAppAttestationMaxLifetime = 300.0;
static const NSTimeInterval PDSSpaceAppAttestationClockSkew = 30.0;
static const NSUInteger PDSSpaceAppAttestationMaxMetadataBytes = 64 * 1024;

@interface PDSSpaceAppAttestationVerifier ()
@property (nonatomic, strong) PDSSpaceStore *spaceStore;
@end

@implementation PDSSpaceAppAttestationVerifier

- (instancetype)initWithSpaceStore:(PDSSpaceStore *)spaceStore {
  self = [super init];
  if (self) {
    _spaceStore = spaceStore;
  }
  return self;
}

- (BOOL)verifyAttestationJWT:(NSString *)attestationJWT
              forAppClientID:(NSString *)appClientID
                    audience:(NSString *)serviceDID
                       error:(NSError **)error {
  if (attestationJWT.length == 0 || appClientID.length == 0 || serviceDID.length == 0) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMalformed
                                     message:@"Attestation JWT, app client_id, and audience are all required"];
    return NO;
  }

  NSURL *clientIDURL = [NSURL URLWithString:appClientID];
  BOOL validScheme = [clientIDURL.scheme.lowercaseString isEqualToString:@"https"];
#ifdef DEBUG
  // Mirrors OAuth2Handler's redirect_uri loopback exception (RFC 8252): only
  // in DEBUG builds, and only for loopback hosts, so a real deployment can
  // never be tricked into treating a plaintext endpoint as attestable.
  if (!validScheme && [clientIDURL.scheme.lowercaseString isEqualToString:@"http"] &&
      ([clientIDURL.host isEqualToString:@"localhost"] || [clientIDURL.host isEqualToString:@"127.0.0.1"])) {
    validScheme = YES;
  }
#endif
  if (!clientIDURL || !validScheme) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMetadataInvalid
                                     message:@"App client_id must be an https URL"];
    return NO;
  }

  NSDictionary *metadata = [self fetchJSONFromURL:clientIDURL
                                    maxBytes:PDSSpaceAppAttestationMaxMetadataBytes
                                       error:error];
  if (!metadata) return NO;
  if (![metadata[@"client_id"] isEqualToString:appClientID]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMetadataInvalid
                                     message:@"Client metadata's client_id does not match the URL it was served from"];
    return NO;
  }

  NSDictionary *jwks = [self resolveJWKSFromMetadata:metadata error:error];
  if (!jwks) return NO;

  return [self verifyJWT:attestationJWT
                   jwks:jwks
         expectedIssuer:appClientID
       expectedAudience:serviceDID
                  error:error];
}

#pragma mark - Client metadata / JWKS resolution

- (nullable NSDictionary *)resolveJWKSFromMetadata:(NSDictionary *)metadata error:(NSError **)error {
  id inlineJWKS = metadata[@"jwks"];
  if ([inlineJWKS isKindOfClass:[NSDictionary class]]) {
    return inlineJWKS;
  }
  NSString *jwksURIString = [metadata[@"jwks_uri"] isKindOfClass:[NSString class]] ? metadata[@"jwks_uri"] : nil;
  NSURL *jwksURI = jwksURIString ? [NSURL URLWithString:jwksURIString] : nil;
  if (!jwksURI || ![jwksURI.scheme.lowercaseString isEqualToString:@"https"]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMetadataInvalid
                                     message:@"Client metadata has neither an inline jwks object nor an https jwks_uri"];
    return nil;
  }
  NSDictionary *jwks = [self fetchJSONFromURL:jwksURI
                               maxBytes:PDSSpaceAppAttestationMaxMetadataBytes
                                  error:error];
  if (!jwks || ![jwks[@"keys"] isKindOfClass:[NSArray class]]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorJWKSUnreachable
                                     message:@"jwks_uri did not return a valid JWK Set"];
    return nil;
  }
  return jwks;
}

- (nullable NSDictionary *)fetchJSONFromURL:(NSURL *)url maxBytes:(NSUInteger)maxBytes error:(NSError **)error {
  ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
  options.timeout = 10.0;
  options.maxResponseBytes = maxBytes;
  options.allowHTTP = NO;
  options.allowPrivateHosts = NO;
  options.followRedirects = YES;
  // Mirrors OAuth2Handler's existing dynamic-client-metadata escape hatch for
  // Docker-based E2E tests, where the app under test is only reachable via a
  // private/loopback address without TLS. Production leaves this env var unset.
  const char *envAllowPrivate = getenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS");
  if (envAllowPrivate && (strcmp(envAllowPrivate, "1") == 0 || strcmp(envAllowPrivate, "true") == 0)) {
    options.allowPrivateHosts = YES;
    options.allowHTTP = YES;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

  NSError *fetchError = nil;
  NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                options:options
                                                               response:nil
                                                                  error:&fetchError];
  if (!data) {
    GZ_LOG_WARN(@"[SpaceAppAttestation] Failed to fetch %@: %@", url, fetchError.localizedDescription);
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMetadataUnreachable
                                     message:[NSString stringWithFormat:@"Could not fetch %@", url.absoluteString]];
    return nil;
  }
  NSError *jsonError = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMetadataInvalid
                                     message:[NSString stringWithFormat:@"%@ did not return a JSON object", url.absoluteString]];
    return nil;
  }
  return parsed;
}

#pragma mark - JWT verification

- (BOOL)verifyJWT:(NSString *)token
             jwks:(NSDictionary *)jwks
   expectedIssuer:(NSString *)issuer
 expectedAudience:(NSString *)audience
            error:(NSError **)error {
  NSArray<NSString *> *parts = [token componentsSeparatedByString:@"."];
  if (parts.count != 3 || parts[0].length == 0 || parts[1].length == 0 || parts[2].length == 0) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMalformed message:@"Malformed compact JWT"];
    return NO;
  }
  NSData *headerData = [JWT base64URLDecode:parts[0] error:nil];
  NSData *payloadData = [JWT base64URLDecode:parts[1] error:nil];
  NSData *signature = [JWT base64URLDecode:parts[2] error:nil];
  NSDictionary *header = headerData ? [NSJSONSerialization JSONObjectWithData:headerData options:0 error:nil] : nil;
  NSDictionary *payload = payloadData ? [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil] : nil;
  if (![header isKindOfClass:[NSDictionary class]] || ![payload isKindOfClass:[NSDictionary class]] ||
      signature.length != 64 || ![header[@"alg"] isEqualToString:@"ES256"] ||
      ![header[@"typ"] isEqualToString:PDSSpaceAppAttestationJWTType]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMalformed
                                     message:@"Attestation JWT header or payload shape is invalid; alg must be ES256"];
    return NO;
  }
  NSString *kid = [header[@"kid"] isKindOfClass:[NSString class]] ? header[@"kid"] : nil;
  if (kid.length == 0) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorMalformed message:@"Attestation JWT header is missing kid"];
    return NO;
  }

  if (![payload[@"iss"] isKindOfClass:[NSString class]] || ![payload[@"sub"] isKindOfClass:[NSString class]] ||
      ![payload[@"aud"] isKindOfClass:[NSString class]] || ![payload[@"jti"] isKindOfClass:[NSString class]] ||
      ![payload[@"iat"] isKindOfClass:[NSNumber class]] || ![payload[@"exp"] isKindOfClass:[NSNumber class]]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorClaims message:@"Attestation JWT is missing a required claim"];
    return NO;
  }
  if (![payload[@"iss"] isEqualToString:issuer]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorIssuer message:@"Attestation issuer does not match the app's client_id"];
    return NO;
  }
  // Self-asserted app identity per ADR 0004: the app attests to its own
  // identity, so sub must equal iss - there is no third party being
  // identified here the way a delegation JWT identifies a space member.
  if (![payload[@"sub"] isEqualToString:issuer]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorSubject message:@"Attestation subject must equal its own issuer (app identity)"];
    return NO;
  }
  if (![payload[@"aud"] isEqualToString:audience]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorAudience message:@"Attestation audience does not match this PDS"];
    return NO;
  }

  NSDate *issuedAt = [NSDate dateWithTimeIntervalSince1970:[payload[@"iat"] doubleValue]];
  NSDate *expiresAt = [NSDate dateWithTimeIntervalSince1970:[payload[@"exp"] doubleValue]];
  NSDate *now = [NSDate date];
  if ([expiresAt timeIntervalSinceDate:issuedAt] <= 0 ||
      [expiresAt timeIntervalSinceDate:issuedAt] > PDSSpaceAppAttestationMaxLifetime ||
      [issuedAt timeIntervalSinceDate:now] > PDSSpaceAppAttestationClockSkew) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorLifetime
                                     message:@"Attestation timestamps are outside the permitted lifetime window"];
    return NO;
  }
  if ([expiresAt timeIntervalSinceDate:now] < -PDSSpaceAppAttestationClockSkew) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorExpired message:@"Attestation has expired"];
    return NO;
  }

  NSDictionary *matchingJWK = [self jwkMatchingKeyID:kid inJWKS:jwks];
  if (!matchingJWK) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorKeyNotFound
                                     message:@"No JWKS key matches the attestation's kid"];
    return NO;
  }
  NSError *keyError = nil;
  id<PDSPublicKeyProtocol> publicKey = [AuthCryptoJWK publicKeyFromJWK:matchingJWK error:&keyError];
  if (!publicKey) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorKeyNotFound
                                     message:[NSString stringWithFormat:@"Matched JWK could not be parsed: %@", keyError.localizedDescription]];
    return NO;
  }

  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
  NSData *signingInputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(signingInputData.bytes, (CC_LONG)signingInputData.length, digest);
  NSError *verifyError = nil;
  if (![publicKey verifyDigestSignature:signature
                                forHash:[NSData dataWithBytes:digest length:sizeof(digest)]
                                  error:&verifyError]) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorSignature
                                     message:[NSString stringWithFormat:@"Attestation signature does not verify: %@", verifyError.localizedDescription]];
    return NO;
  }

  NSError *replayError = nil;
  BOOL consumed = [self.spaceStore consumeAppAttestationID:payload[@"jti"]
                                             expiresAt:expiresAt
                                                   now:now
                                                 error:&replayError];
  if (!consumed) {
    if (error) *error = [self errorWithCode:PDSSpaceAppAttestationErrorReplay
                                     message:replayError.localizedDescription ?: @"Attestation jti has already been used"];
    return NO;
  }

  return YES;
}

- (nullable NSDictionary *)jwkMatchingKeyID:(NSString *)kid inJWKS:(NSDictionary *)jwks {
  NSArray *keys = [jwks[@"keys"] isKindOfClass:[NSArray class]] ? jwks[@"keys"] : @[];
  for (NSDictionary *jwk in keys) {
    if (![jwk isKindOfClass:[NSDictionary class]]) continue;
    if (![jwk[@"kid"] isEqualToString:kid]) continue;
    if (jwk[@"use"] && ![jwk[@"use"] isEqualToString:@"sig"]) continue;
    if (![jwk[@"kty"] isEqualToString:@"EC"] || ![jwk[@"crv"] isEqualToString:@"P-256"]) continue;
    return jwk;
  }
  return nil;
}

- (NSError *)errorWithCode:(PDSSpaceAppAttestationError)code message:(NSString *)message {
  return [NSError errorWithDomain:PDSSpaceAppAttestationErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
