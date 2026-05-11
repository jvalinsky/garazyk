// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSTwilioPhoneVerificationProvider.m

 @abstract Twilio Verify phone verification provider implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PhoneVerification/PDSTwilioPhoneVerificationProvider.h"
#import "Core/PDSProviderHTTPClient.h"
#import "Email/PDSSecretsProvider.h"
#import "Debug/PDSLogger.h"

static NSString *const kTwilioVerifyBaseURL = @"https://verify.twilio.com/v2/Service";
static NSString *const kTwilioAccountSIDEnvVar = @"TWILIO_ACCOUNT_SID";
static NSString *const kTwilioAuthTokenEnvVar = @"TWILIO_AUTH_TOKEN";
static NSString *const kTwilioVerifyServiceSIDEnvVar = @"TWILIO_VERIFY_SERVICE_SID";

NSString *const PDSTwilioProviderErrorDomain = @"com.atproto.pds.twilioprovider";

@interface PDSTwilioPhoneVerificationProvider () {
    dispatch_queue_t _initQueue;
}
@property (nonatomic, strong) id<PDSSecretsProvider> secretsProvider;
@property (nonatomic, copy) NSDictionary *providerConfig;
@property (nonatomic, strong, nullable) PDSProviderHTTPClient *httpClient;
@property (nonatomic, copy, nullable) NSString *accountSID;
@property (nonatomic, copy, nullable) NSString *authToken;
@property (nonatomic, copy, nullable) NSString *verifyServiceSID;
@end

@implementation PDSTwilioPhoneVerificationProvider

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
        _initQueue = dispatch_queue_create("com.atproto.pds.twilio.init", DISPATCH_QUEUE_SERIAL);
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
        NSString *accountSID = [self.secretsProvider secretForKey:kTwilioAccountSIDEnvVar
                                                            error:&secretError];
        if (!accountSID || accountSID.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                             code:PDSTwilioProviderErrorMissingAccountSID
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Twilio Account SID"
                                         }];
            }
            return;
        }

        NSString *authToken = [self.secretsProvider secretForKey:kTwilioAuthTokenEnvVar
                                                            error:&secretError];
        if (!authToken || authToken.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                             code:PDSTwilioProviderErrorMissingAuthToken
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Twilio Auth Token"
                                         }];
            }
            return;
        }

        NSString *serviceSID = [self.secretsProvider secretForKey:kTwilioVerifyServiceSIDEnvVar
                                                            error:&secretError];
        if (!serviceSID || serviceSID.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                             code:PDSTwilioProviderErrorMissingServiceSID
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Twilio Verify Service SID"
                                         }];
            }
            return;
        }

        self->_accountSID = [accountSID copy];
        self->_authToken = [authToken copy];
        self->_verifyServiceSID = [serviceSID copy];

        // Twilio uses Basic Auth: base64(accountSID:authToken)
        NSString *credentials = [NSString stringWithFormat:@"%@:%@", accountSID, authToken];
        NSData *credentialData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64Credentials = [credentialData base64EncodedStringWithOptions:0];
        NSString *authHeader = [NSString stringWithFormat:@"Basic %@", base64Credentials];

        NSURL *baseURL = [NSURL URLWithString:
            [NSString stringWithFormat:@"%@/%@",
                kTwilioVerifyBaseURL, serviceSID]];

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
            *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                         code:PDSTwilioProviderErrorInvalidPhoneNumber
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

    PDS_LOG_INFO(@"[Twilio] Sending verification to: %@", phoneNumber);

    // POST /Verifications
    NSDictionary *body = @{
        @"To": phoneNumber,
        @"Channel": @"sms"
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:@"/Verifications"
                                                  body:body
                                                 error:&requestError];
    if (!response) {
        PDS_LOG_ERROR(@"[Twilio] Failed to send verification: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                         code:PDSTwilioProviderErrorRequestFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Failed to send verification"
                                     }];
        }
        return nil;
    }

    NSString *status = response[@"status"];
    PDS_LOG_INFO(@"[Twilio] Verification sent to %@ (status: %@)", phoneNumber, status);
    // Twilio does not use session IDs — return empty string on success
    return @"";
}

- (BOOL)verifyCode:(NSString *)code forPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    return [self verifyCode:code forPhoneNumber:phoneNumber sessionID:nil error:error];
}

- (BOOL)verifyCode:(NSString *)code forPhoneNumber:(NSString *)phoneNumber sessionID:(nullable NSString *)sessionID error:(NSError **)error {
    if (!code || code.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                         code:PDSTwilioProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing verification code"
                                     }];
        }
        return NO;
    }

    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                         code:PDSTwilioProviderErrorInvalidPhoneNumber
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing phone number"
                                     }];
        }
        return NO;
    }

    NSError *initError = nil;
    if (![self ensureInitializedWithError:&initError]) {
        if (error) *error = initError;
        return NO;
    }

    PDS_LOG_INFO(@"[Twilio] Checking verification code for: %@", phoneNumber);

    // POST /VerificationCheck
    NSDictionary *body = @{
        @"To": phoneNumber,
        @"Code": code
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:@"/VerificationCheck"
                                                  body:body
                                                 error:&requestError];
    if (!response) {
        PDS_LOG_ERROR(@"[Twilio] Verification check failed: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                         code:PDSTwilioProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Verification check failed"
                                     }];
        }
        return NO;
    }

    NSString *status = response[@"status"];
    if ([status isEqualToString:@"approved"]) {
        PDS_LOG_INFO(@"[Twilio] Verification approved for %@", phoneNumber);
        return YES;
    }

    PDS_LOG_INFO(@"[Twilio] Verification not approved for %@ (status: %@)", phoneNumber, status);
    if (error) {
        *error = [NSError errorWithDomain:PDSTwilioProviderErrorDomain
                                     code:PDSTwilioProviderErrorVerificationFailed
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:
                                             @"Verification not approved (status: %@)",
                                             status ?: @"unknown"]
                                 }];
    }
    return NO;
}

@end
