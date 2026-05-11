// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "WebAuthnRegistrationHandler.h"
#import "Auth/WebAuthnVerifier.h"
#import "Auth/CryptoUtils.h"
#import "Database/PDSDatabase.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Session.h"

static NSString *const kWebAuthnErrorDomain = @"com.atproto.pds.webauthn";
static NSTimeInterval kChallengeTimeoutSeconds = 300.0;

@interface WebAuthnRegistrationHandler ()
@property (nonatomic, strong) NSMutableDictionary *pendingChallenges;
@end

@implementation WebAuthnRegistrationHandler {
    dispatch_queue_t _challengeQueue;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (instancetype)new {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database serverOrigin:(NSString *)serverOrigin {
    self = [super init];
    if (self) {
        _database = database;
        _serverOrigin = serverOrigin;
        _pendingChallenges = [NSMutableDictionary dictionary];
        _challengeQueue = dispatch_queue_create("com.atproto.webauthn.challenges", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)httpServer {
    [httpServer addRoute:@"POST" path:@"/auth/webauthn/register/begin" handler:^(HttpRequest *req, HttpResponse *res) {
        [self handleRegisterBegin:req response:res];
    }];
    [httpServer addRoute:@"POST" path:@"/auth/webauthn/register/complete" handler:^(HttpRequest *req, HttpResponse *res) {
        [self handleRegisterComplete:req response:res];
    }];
    [httpServer addRoute:@"POST" path:@"/auth/webauthn/assert" handler:^(HttpRequest *req, HttpResponse *res) {
        [self handleAssert:req response:res];
    }];
}

#pragma mark - Register Begin

- (void)handleRegisterBegin:(HttpRequest *)request response:(HttpResponse *)response {
    NSDictionary *body = [self parseJSONBody:request.body];
    if (!body) {
        [self respondWithError:response code:400 message:@"Invalid request body"];
        return;
    }

    NSString *did = body[@"did"];
    if (!did) {
        [self respondWithError:response code:400 message:@"Missing did"];
        return;
    }

    NSError *error = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&error];
    if (!account) {
        [self respondWithError:response code:404 message:@"Account not found"];
        return;
    }

    NSData *challenge = [CryptoUtils randomBytes:32];
    if (!challenge) {
        [self respondWithError:response code:500 message:@"Failed to generate challenge"];
        return;
    }

    NSString *challengeB64 = [self base64URLEncode:challenge];
    NSString *sessionId = [[NSUUID UUID] UUIDString];

    dispatch_sync(_challengeQueue, ^{
        self.pendingChallenges[sessionId] = @{
            @"challenge": challenge,
            @"did": did,
            @"expiresAt": @([[NSDate date] timeIntervalSince1970] + kChallengeTimeoutSeconds)
        };
    });

    NSDictionary *result = @{
        @"challenge": challengeB64,
        @"rp": @{@"name": @"PDS", @"id": self.serverOrigin},
        @"user": @{@"id": did, @"name": account.handle ?: @"unknown"},
        @"pubKeyCredParams": @[@{@"type": @"public-key", @"alg": @(-7)}],
        @"sessionId": sessionId
    };

    [self respondWithJSON:response code:200 body:result];
}

#pragma mark - Register Complete

- (void)handleRegisterComplete:(HttpRequest *)request response:(HttpResponse *)response {
    NSDictionary *body = [self parseJSONBody:request.body];
    if (!body) {
        [self respondWithError:response code:400 message:@"Invalid request body"];
        return;
    }

    NSString *sessionId = body[@"sessionId"];
    NSString *credentialId = body[@"credentialId"];
    NSDictionary *attestation = body[@"attestation"];

    if (!sessionId || !credentialId || !attestation) {
        [self respondWithError:response code:400 message:@"Missing required fields"];
        return;
    }

    NSDictionary *challengeInfo = [self popChallenge:sessionId];
    if (!challengeInfo) {
        [self respondWithError:response code:400 message:@"Invalid or expired session"];
        return;
    }

    NSData *expectedChallenge = challengeInfo[@"challenge"];
    NSString *did = challengeInfo[@"did"];

    NSError *error = nil;
    NSDictionary *credentialData = [WebAuthnVerifier verifyRegistrationResponse:attestation
                                                                    challenge:expectedChallenge
                                                                       origin:self.serverOrigin
                                                                        error:&error];
    if (!credentialData) {
        [self respondWithError:response code:400 message:error.localizedDescription ?: @"Verification failed"];
        return;
    }

    NSMutableDictionary *credentialToStore = [NSMutableDictionary dictionary];
    credentialToStore[@"credentialId"] = credentialData[@"credentialId"];
    credentialToStore[@"publicKey"] = credentialData[@"publicKey"];
    credentialToStore[@"signCount"] = @(0);
    credentialToStore[@"aaguid"] = credentialData[@"aaguid"];

    BOOL stored = [self.database storeWebAuthnCredential:credentialToStore forDid:did error:&error];
    if (!stored) {
        [self respondWithError:response code:500 message:@"Failed to store credential"];
        return;
    }

    NSString *credIdB64 = [self base64URLEncode:credentialData[@"credentialId"]];

    [self respondWithJSON:response code:200 body:@{@"success": @YES, @"credentialId": credIdB64}];
}

#pragma mark - Assert

- (void)handleAssert:(HttpRequest *)request response:(HttpResponse *)response {
    NSDictionary *body = [self parseJSONBody:request.body];
    if (!body) {
        [self respondWithError:response code:400 message:@"Invalid request body"];
        return;
    }

    NSString *sessionId = body[@"sessionId"];
    NSDictionary *assertion = body[@"assertion"];

    if (!sessionId || !assertion) {
        [self respondWithError:response code:400 message:@"Missing required fields"];
        return;
    }

    NSDictionary *challengeInfo = [self popChallenge:sessionId];
    if (!challengeInfo) {
        [self respondWithError:response code:400 message:@"Invalid or expired session"];
        return;
    }

    NSData *expectedChallenge = challengeInfo[@"challenge"];
    NSString *did = challengeInfo[@"did"];

    NSError *error = nil;
    NSArray<NSDictionary *> *credentials = [self.database getWebAuthnCredentialsForDid:did error:&error];
    if (credentials.count == 0) {
        [self respondWithError:response code:404 message:@"No credentials found"];
        return;
    }

    BOOL verified = NO;
    NSNumber *newSignCount = nil;
    NSDictionary *matchedCredential = nil;

    for (NSDictionary *cred in credentials) {
        uint32_t storedSignCount = [cred[@"signCount"] unsignedIntValue];
        uint32_t newCount = 0;

        verified = [WebAuthnVerifier verifyAssertionResponse:assertion
                                         challenge:expectedChallenge
                                            origin:self.serverOrigin
                                         publicKey:cred[@"publicKey"]
                                         signCount:storedSignCount
                                      newSignCount:&newCount
                                             error:&error];

        if (verified) {
            matchedCredential = cred;
            newSignCount = @(newCount);
            break;
        }
    }

    if (!verified) {
        [self respondWithError:response code:400 message:error.localizedDescription ?: @"Assertion verification failed"];
        return;
    }

    if (newSignCount && [newSignCount unsignedIntValue] > 0) {
        [self.database updateWebAuthnCredentialSignCount:matchedCredential[@"credentialId"]
                                              forDid:did
                                           signCount:[newSignCount unsignedIntValue]
                                               error:nil];
    }

    [self respondWithJSON:response code:200 body:@{@"success": @YES, @"did": did}];
}

#pragma mark - Helpers

- (NSDictionary *)popChallenge:(NSString *)sessionId {
    __block NSDictionary *info = nil;
    dispatch_sync(_challengeQueue, ^{
        info = self.pendingChallenges[sessionId];
        if (info) {
            NSTimeInterval expiresAt = [info[@"expiresAt"] doubleValue];
            if ([[NSDate date] timeIntervalSince1970] > expiresAt) {
                info = nil;
                [self.pendingChallenges removeObjectForKey:sessionId];
            } else {
                [self.pendingChallenges removeObjectForKey:sessionId];
            }
        }
    });
    return info;
}

- (NSDictionary *)parseJSONBody:(NSData *)data {
    if (!data || data.length == 0) {
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (NSString *)base64URLEncode:(NSData *)data {
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return b64;
}

- (void)respondWithJSON:(HttpResponse *)response code:(NSInteger)code body:(NSDictionary *)body {
    response.statusCode = code;
    [response setHeader:@"application/json" forKey:@"Content-Type"];
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    response.body = json;
}

- (void)respondWithError:(HttpResponse *)response code:(NSInteger)code message:(NSString *)message {
    response.statusCode = code;
    [response setHeader:@"application/json" forKey:@"Content-Type"];
    NSDictionary *body = @{@"error": message};
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    response.body = json;
}

@end