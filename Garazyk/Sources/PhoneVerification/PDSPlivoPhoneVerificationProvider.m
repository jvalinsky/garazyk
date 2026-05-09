/*!
 @file PDSPlivoPhoneVerificationProvider.m

 @abstract Plivo Verify phone verification provider implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PhoneVerification/PDSPlivoPhoneVerificationProvider.h"
#import "Core/PDSProviderHTTPClient.h"
#import "Email/PDSSecretsProvider.h"
#import "Debug/PDSLogger.h"

static NSString *const kPlivoVerifyBaseURLTemplate = @"https://api.plivo.com/v1/Account/%@";
static NSString *const kPlivoAuthIDEnvVar = @"PLIVO_AUTH_ID";
static NSString *const kPlivoAuthTokenEnvVar = @"PLIVO_AUTH_TOKEN";

NSString *const PDSPlivoProviderErrorDomain = @"com.atproto.pds.plivoprovider";

@interface PDSPlivoPhoneVerificationProvider () {
    dispatch_queue_t _initQueue;
}
@property (nonatomic, strong) id<PDSSecretsProvider> secretsProvider;
@property (nonatomic, copy) NSDictionary *providerConfig;
@property (nonatomic, strong, nullable) PDSProviderHTTPClient *httpClient;
@property (nonatomic, copy, nullable) NSString *authID;
@property (nonatomic, copy, nullable) NSString *authToken;
@end

@implementation PDSPlivoPhoneVerificationProvider

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (instancetype)new {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithSecretsProvider:(id<PDSSecretsProvider>)secretsProvider
                          configuration:(NSDictionary *)configuration {
    self = [super init];
    if (self) {
        _secretsProvider = secretsProvider;
        _providerConfig = [configuration copy] ?: @{};
        _initQueue = dispatch_queue_create("com.atproto.pds.plivo.init", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Lazy Initialization

- (BOOL)ensureInitializedWithError:(NSError **)error {
    __block BOOL success = NO;
    dispatch_sync(_initQueue, ^{
        if (self->_httpClient) {
            success = YES;
            return;
        }

        // Resolve credentials from secrets provider
        NSError *secretError = nil;
        NSString *authID = [self.secretsProvider secretForKey:kPlivoAuthIDEnvVar
                                                        error:&secretError];
        if (!authID || authID.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                             code:PDSPlivoProviderErrorMissingAuthID
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Plivo Auth ID"
                                         }];
            }
            return;
        }

        NSString *authToken = [self.secretsProvider secretForKey:kPlivoAuthTokenEnvVar
                                                           error:&secretError];
        if (!authToken || authToken.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                             code:PDSPlivoProviderErrorMissingAuthToken
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Plivo Auth Token"
                                         }];
            }
            return;
        }

        self->_authID = [authID copy];
        self->_authToken = [authToken copy];

        // Plivo uses Basic Auth: base64(authID:authToken)
        NSString *credentials = [NSString stringWithFormat:@"%@:%@", authID, authToken];
        NSData *credentialData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64Credentials = [credentialData base64EncodedStringWithOptions:0];
        NSString *authHeader = [NSString stringWithFormat:@"Basic %@", base64Credentials];

        NSURL *baseURL = [NSURL URLWithString:
            [NSString stringWithFormat:kPlivoVerifyBaseURLTemplate, authID]];

        self->_httpClient = [[PDSProviderHTTPClient alloc]
            initWithBaseURL:baseURL authHeader:authHeader];
        success = YES;
    });
    return success;
}

#pragma mark - PDSPhoneVerificationProvider

- (nullable NSString *)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                         code:PDSPlivoProviderErrorInvalidPhoneNumber
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing phone number"
                                     }];
        }
        return nil;
    }

    NSError *initError = nil;
    if (![self ensureInitializedWithError:&initError]) {
        if (error) *error = initError;
        return nil;
    }

    PDS_LOG_INFO(@"[Plivo] Sending verification to: %@", phoneNumber);

    // POST /Verify/Session/ with JSON body
    NSDictionary *body = @{
        @"recipient": phoneNumber,
        @"channel": @"sms"
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:@"/Verify/Session/"
                                                  body:body
                                                 error:&requestError];
    if (!response) {
        PDS_LOG_ERROR(@"[Plivo] Failed to send verification: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                         code:PDSPlivoProviderErrorRequestFailed
                                     userInfo:@{
                                             NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Failed to send verification"
                                     }];
        }
        return nil;
    }

    NSString *sessionUUID = response[@"session_uuid"];
    if (!sessionUUID || sessionUUID.length == 0) {
        // Plivo may return the UUID in a different field
        sessionUUID = response[@"api_id"];
    }

    PDS_LOG_INFO(@"[Plivo] Verification sent to %@ (session_uuid: %@)", phoneNumber, sessionUUID);
    return sessionUUID ?: @"";
}

- (BOOL)verifyCode:(NSString *)code forPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    return [self verifyCode:code forPhoneNumber:phoneNumber sessionID:nil error:error];
}

- (BOOL)verifyCode:(NSString *)code
     forPhoneNumber:(NSString *)phoneNumber
          sessionID:(nullable NSString *)sessionID
              error:(NSError **)error {
    if (!code || code.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                         code:PDSPlivoProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing verification code"
                                     }];
        }
        return NO;
    }

    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                         code:PDSPlivoProviderErrorInvalidPhoneNumber
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing phone number"
                                     }];
        }
        return NO;
    }

    if (!sessionID || sessionID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                         code:PDSPlivoProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing session ID (session_uuid) for Plivo verification"
                                     }];
        }
        return NO;
    }

    NSError *initError = nil;
    if (![self ensureInitializedWithError:&initError]) {
        if (error) *error = initError;
        return NO;
    }

    PDS_LOG_INFO(@"[Plivo] Checking verification code for: %@ (session_uuid: %@)", phoneNumber, sessionID);

    // POST /Verify/Session/{session_uuid}/ with JSON body
    NSString *path = [NSString stringWithFormat:@"/Verify/Session/%@/", sessionID];
    NSDictionary *body = @{
        @"otp": code
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:path
                                                  body:body
                                                 error:&requestError];
    if (!response) {
        PDS_LOG_ERROR(@"[Plivo] Verification check failed: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                         code:PDSPlivoProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Verification check failed"
                                     }];
        }
        return NO;
    }

    // Plivo returns 200 on success with the session object
    // Check for a "is_verified" field or successful status
    NSNumber *isVerified = response[@"is_verified"];
    if (isVerified && isVerified.boolValue) {
        PDS_LOG_INFO(@"[Plivo] Verification approved for %@", phoneNumber);
        return YES;
    }

    // Some Plivo responses indicate success by just returning 200
    // without an error. If we got here with a non-nil response,
    // the HTTP status was 200, which for Plivo means success.
    NSString *message = response[@"message"];
    if (message && [message containsString:@"verified"]) {
        PDS_LOG_INFO(@"[Plivo] Verification approved for %@", phoneNumber);
        return YES;
    }

    PDS_LOG_INFO(@"[Plivo] Verification not approved for %@", phoneNumber);
    if (error) {
        *error = [NSError errorWithDomain:PDSPlivoProviderErrorDomain
                                     code:PDSPlivoProviderErrorVerificationFailed
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:
                                             @"Verification not approved (response: %@)",
                                             message ?: @"unknown"]
                                 }];
    }
    return NO;
}

@end
