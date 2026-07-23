// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+PasskeyAuth.h"
#import "Auth/OAuth2.h"
#import "Auth/CryptoUtils.h"
#import "Auth/WebAuthnVerifier.h"
#import "Database/PDSDatabase.h"
#import "Security/PDSSecurityCompare.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (PasskeyAuth)

- (void)handlePasskeyChallenge:(HttpRequest *)request
                      response:(HttpResponse *)response {
  NSDictionary *body = [self parseJSONBody:request.body];
  if (!body) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Invalid request body"
    }];
    return;
  }

  NSString *did = body[@"did"];
  if (![did isKindOfClass:[NSString class]] || did.length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Missing did"
    }];
    return;
  }

  if (self.serverOrigin.length == 0) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Server origin not configured"
    }];
    return;
  }

  NSData *challenge = [CryptoUtils randomBytes:32];
  if (!challenge) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Failed to generate passkey challenge"
    }];
    return;
  }

  NSString *sessionId = [[NSUUID UUID] UUIDString];
  NSDate *expires = [NSDate dateWithTimeIntervalSinceNow:kPasskeyChallengeTTLSeconds];
  dispatch_sync(sPasskeyChallengeQueue, ^{
    [self cleanupExpiredPasskeyChallengesLocked];
    sPasskeyChallenges[sessionId] = @{
      @"challenge" : challenge,
      @"did" : did,
      @"expires" : expires
    };
  });

  response.statusCode = 200;
  [response setJsonBody:@{
    @"challenge" : [CryptoUtils base64URLEncode:challenge],
    @"sessionId" : sessionId,
    @"rpId" : self.serverOrigin
  }];
}

- (void)handlePasskeySignIn:(HttpRequest *)request
                     response:(HttpResponse *)response {
  NSDictionary *body = [self parseJSONBody:request.body];
  if (!body) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Invalid request body"
    }];
    return;
  }

  NSString *sessionId = body[@"sessionId"];
  NSDictionary *assertion = body[@"assertion"];
  NSString *did = body[@"did"];

  // CSRF validation
  NSString *csrfHeader = [request headerForKey:@"X-CSRF-Token"];
  NSString *cookieHeader = [request headerForKey:@"Cookie"];
  NSString *csrfCookie = nil;
  if (cookieHeader) {
    for (NSString *cookie in [cookieHeader componentsSeparatedByString:@";"]) {
      NSString *trimmed =
          [cookie stringByTrimmingCharactersInSet:[NSCharacterSet
                                                      whitespaceCharacterSet]];
      if ([trimmed hasPrefix:@"csrf_token="]) {
        csrfCookie = [trimmed substringFromIndex:@"csrf_token=".length];
        break;
      }
    }
  }
  if (!csrfHeader || !csrfCookie || ![PDSSecurityCompare constantTimeEqualString:csrfHeader string:csrfCookie]) {
    response.statusCode = 403;
    [response setJsonBody:@{@"ok" : @NO, @"error" : @"Invalid CSRF token"}];
    return;
  }

  if (![sessionId isKindOfClass:[NSString class]] || sessionId.length == 0 ||
      ![assertion isKindOfClass:[NSDictionary class]] ||
      ![did isKindOfClass:[NSString class]] || did.length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Session ID, assertion, and did are required"
    }];
    return;
  }

  if (self.serverOrigin.length == 0) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Server origin not configured"
    }];
    return;
  }

  NSDictionary *challengeInfo = [self consumePasskeyChallengeForSessionId:sessionId];
  if (!challengeInfo) {
    response.statusCode = 403;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Invalid or expired passkey challenge"
    }];
    return;
  }

  NSString *challengeDid = challengeInfo[@"did"];
  if (![CryptoUtils constantTimeCompare:did to:challengeDid]) {
    response.statusCode = 403;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Passkey challenge does not match DID"
    }];
    return;
  }

  NSData *expectedChallenge = challengeInfo[@"challenge"];
  if (![expectedChallenge isKindOfClass:[NSData class]]) {
    response.statusCode = 403;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Invalid or expired passkey challenge"
    }];
    return;
  }

  PDSDatabaseAccount *account = [self.database getAccountByDid:did error:nil];
  NSString *sessionHandle = account.handle ?: did;
  if (sessionHandle.length == 0) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Failed to resolve account handle"
    }];
    return;
  }

  NSArray<NSDictionary *> *credentials =
      [self.database getWebAuthnCredentialsForDid:did error:nil];
  if (!credentials || credentials.count == 0) {
    response.statusCode = 404;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"No WebAuthn credentials found for DID"
    }];
    return;
  }

  BOOL verified = NO;
  NSError *verificationError = nil;
  NSDictionary *matchedCredential = nil;
  uint32_t newSignCount = 0;

  for (NSDictionary *credential in credentials) {
    NSData *publicKey = credential[@"publicKey"];
    NSData *credentialId = credential[@"credentialId"];
    if (![publicKey isKindOfClass:[NSData class]] ||
        ![credentialId isKindOfClass:[NSData class]]) {
      continue;
    }

    uint32_t storedSignCount = [credential[@"signCount"] unsignedIntValue];
    uint32_t candidateSignCount = 0;
    NSError *candidateError = nil;
    BOOL candidateVerified =
        [WebAuthnVerifier verifyAssertionResponse:assertion
                                        challenge:expectedChallenge
                                           origin:self.serverOrigin
                                        publicKey:publicKey
                                        signCount:storedSignCount
                                     newSignCount:&candidateSignCount
                                             error:&candidateError];

    if (candidateVerified) {
      verified = YES;
      matchedCredential = credential;
      newSignCount = candidateSignCount;
      break;
    }
    if (candidateError) {
      verificationError = candidateError;
    }
  }

  if (!verified || !matchedCredential) {
    response.statusCode = 401;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : verificationError.localizedDescription ?: @"Invalid passkey assertion"
    }];
    return;
  }

  NSError *updateError = nil;
  if (![self.database updateWebAuthnCredentialSignCount:matchedCredential[@"credentialId"]
                                                  forDid:did
                                               signCount:newSignCount
                                                   error:&updateError]) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : updateError.localizedDescription ?: @"Failed to update passkey sign count"
    }];
    return;
  }

  NSString *sessionToken = [self createPendingConsentSessionForDid:did
                                                            handle:sessionHandle];
  if (!sessionToken) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Failed to create session token"
    }];
    return;
  }

  response.statusCode = 200;
  [response setJsonBody:@{
    @"ok" : @YES,
    @"did" : did,
    @"session_token" : sessionToken
  }];
}

- (void)cleanupExpiredPasskeyChallengesLocked {
  if (!sPasskeyChallenges || sPasskeyChallenges.count == 0) {
    return;
  }

  NSDate *now = [NSDate date];
  NSMutableArray<NSString *> *expired = [NSMutableArray array];
  [sPasskeyChallenges enumerateKeysAndObjectsUsingBlock:^(id key, id obj,
                                                          BOOL *stop) {
    NSDictionary *challenge = (NSDictionary *)obj;
    NSDate *expires = challenge[@"expires"];
    if (![expires isKindOfClass:[NSDate class]] ||
        [expires compare:now] != NSOrderedDescending) {
      [expired addObject:(NSString *)key];
    }
  }];
  [sPasskeyChallenges removeObjectsForKeys:expired];
}

- (NSDictionary *)consumePasskeyChallengeForSessionId:(NSString *)sessionId {
  if (sessionId.length == 0) {
    return nil;
  }

  __block NSDictionary *challengeInfo = nil;
  dispatch_sync(sPasskeyChallengeQueue, ^{
    [self cleanupExpiredPasskeyChallengesLocked];
    challengeInfo = sPasskeyChallenges[sessionId];
    if (challengeInfo) {
      [sPasskeyChallenges removeObjectForKey:sessionId];
    }
  });
  return challengeInfo;
}

@end
