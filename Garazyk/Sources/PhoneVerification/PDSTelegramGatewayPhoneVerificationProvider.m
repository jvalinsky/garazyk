// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSTelegramGatewayPhoneVerificationProvider.m

 @abstract Telegram Gateway phone verification provider implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PhoneVerification/PDSTelegramGatewayPhoneVerificationProvider.h"
#import "Core/GZProviderHTTPClient.h"
#import "Email/PDSSecretsProvider.h"
#import "Debug/GZLogger.h"
#import "Debug/GZLogRedactor.h"

static NSString *const kTelegramGatewayBaseURL = @"https://gatewayapi.telegram.org";
static NSString *const kTelegramGatewayTokenEnvVar = @"TELEGRAM_GATEWAY_TOKEN";
static NSString *const kTelegramGatewayBaseURLEnvVar = @"TELEGRAM_API_BASE_URL";

NSString *const PDSTelegramGatewayProviderErrorDomain = @"com.atproto.pds.telegramgatewayprovider";

@interface PDSTelegramGatewayPhoneVerificationProvider () {
    dispatch_queue_t _initQueue;
}
@property (nonatomic, strong) id<PDSSecretsProvider> secretsProvider;
@property (nonatomic, copy) NSDictionary *providerConfig;
@property (nonatomic, strong, nullable) GZProviderHTTPClient *httpClient;
@property (nonatomic, copy, nullable) NSString *gatewayToken;
@end

@implementation PDSTelegramGatewayPhoneVerificationProvider

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
        _initQueue = dispatch_queue_create("com.atproto.pds.telegramgateway.init", DISPATCH_QUEUE_SERIAL);
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
        NSString *gatewayToken = [self.secretsProvider secretForKey:kTelegramGatewayTokenEnvVar
                                                              error:&secretError];
        if (!gatewayToken || gatewayToken.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                             code:PDSTelegramGatewayProviderErrorMissingToken
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Telegram Gateway Token"
                                         }];
            }
            return;
        }

        self->_gatewayToken = [gatewayToken copy];

        // Determine base URL
        NSString *baseURLString = self->_providerConfig[@"baseURL"];
        if (!baseURLString) {
            baseURLString = [self.secretsProvider secretForKey:kTelegramGatewayBaseURLEnvVar
                                                         error:&secretError];
        }
        if (!baseURLString) {
            baseURLString = kTelegramGatewayBaseURL;
        }

        // Telegram Gateway uses Bearer token authentication.
        NSURL *baseURL = [NSURL URLWithString:baseURLString];
        self->_httpClient = [[GZProviderHTTPClient alloc]
            initWithBaseURL:baseURL
                    apiKey:gatewayToken];
        success = YES;
    });
    return success;
}

#pragma mark - PDSPhoneVerificationProvider

- (nullable NSString *)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorInvalidPhoneNumber
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

    GZ_LOG_INFO(@"[TelegramGateway] Sending verification to: %@", [GZLogRedactor maskToken:phoneNumber]);

    // Optional: check send ability first to avoid unnecessary charges.
    // If the user cannot receive Telegram messages, fail early.
    NSString *freeRequestID = [self checkSendAbilityForPhoneNumber:phoneNumber error:nil];
    // freeRequestID is nil if the user cannot receive Telegram messages,
    // but we still proceed with sendVerificationMessage — the Telegram
    // Gateway will return an error if delivery is impossible.

    // POST /sendVerificationMessage with JSON body
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"phone_number"] = phoneNumber;
    body[@"code_length"] = @6;
    if (freeRequestID) {
        body[@"request_id"] = freeRequestID;
    }

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:@"/sendVerificationMessage"
                                                  body:[body copy]
                                                 error:&requestError];
    if (!response) {
        GZ_LOG_ERROR(@"[TelegramGateway] Failed to send verification: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorRequestFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Failed to send verification"
                                     }];
        }
        return nil;
    }

    // Telegram Gateway returns { "ok": true, "result": { "request_id": "..." } }
    NSNumber *ok = response[@"ok"];
    if (!ok || !ok.boolValue) {
        NSString *errorMsg = response[@"error"] ?: @"Unknown error";
        GZ_LOG_ERROR(@"[TelegramGateway] Verification send failed (error: %@)", errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorRequestFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Telegram Gateway verification failed: %@", errorMsg]
                                     }];
        }
        return nil;
    }

    NSDictionary *result = response[@"result"];
    NSString *requestID = result[@"request_id"];

    GZ_LOG_INFO(@"[TelegramGateway] Verification sent to %@ (request_id: %@)", [GZLogRedactor maskToken:phoneNumber], requestID);
    return requestID ?: @"";
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
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing verification code"
                                     }];
        }
        return NO;
    }

    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorInvalidPhoneNumber
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing phone number"
                                     }];
        }
        return NO;
    }

    if (!sessionID || sessionID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing session ID (request_id) for Telegram Gateway verification"
                                     }];
        }
        return NO;
    }

    NSError *initError = nil;
    if (![self ensureInitializedWithError:&initError]) {
        if (error) *error = initError;
        return NO;
    }

    GZ_LOG_INFO(@"[TelegramGateway] Checking verification code for: %@ (request_id: %@)", [GZLogRedactor maskToken:phoneNumber], sessionID);

    // POST /checkVerificationStatus with JSON body
    NSDictionary *body = @{
        @"request_id": sessionID,
        @"code": code
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:@"/checkVerificationStatus"
                                                  body:body
                                                 error:&requestError];
    if (!response) {
        GZ_LOG_ERROR(@"[TelegramGateway] Verification check failed: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Verification check failed"
                                     }];
        }
        return NO;
    }

    // Telegram Gateway returns { "ok": true, "result": { "verification_status": { "status": "code_valid" } } }
    NSNumber *ok = response[@"ok"];
    if (!ok || !ok.boolValue) {
        NSString *errorMsg = response[@"error"] ?: @"Unknown error";
        GZ_LOG_INFO(@"[TelegramGateway] Verification not approved for %@ (error: %@)", [GZLogRedactor maskToken:phoneNumber], errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Verification not approved: %@", errorMsg]
                                     }];
        }
        return NO;
    }

    NSDictionary *result = response[@"result"];
    NSDictionary *verificationStatus = result[@"verification_status"];
    NSString *status = verificationStatus[@"status"];

    if ([status isEqualToString:@"code_valid"]) {
        GZ_LOG_INFO(@"[TelegramGateway] Verification approved for %@", [GZLogRedactor maskToken:phoneNumber]);
        return YES;
    }

    GZ_LOG_INFO(@"[TelegramGateway] Verification not approved for %@ (status: %@)", [GZLogRedactor maskToken:phoneNumber], status ?: @"unknown");
    if (error) {
        *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                     code:PDSTelegramGatewayProviderErrorVerificationFailed
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:
                                             @"Verification not approved (status: %@)",
                                             status ?: @"unknown"]
                                 }];
    }
    return NO;
}

#pragma mark - Private

/*!
 @method checkSendAbilityForPhoneNumber:error:
 @abstract Checks whether a user can receive Telegram messages before sending.

 @discussion
    Calls the Telegram Gateway checkSendAbility endpoint to verify the
    phone number is associated with a Telegram account. Returns a
    request_id that can be passed to sendVerificationMessage for free
    delivery, or nil if the user cannot receive Telegram messages.

 @param phoneNumber E.164 phone number.
 @param error On failure, set to a send ability check error.
 @result request_id for free delivery, or nil if the user cannot receive messages.
 */
- (nullable NSString *)checkSendAbilityForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    NSDictionary *body = @{
        @"phone_number": phoneNumber
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postPath:@"/checkSendAbility"
                                                  body:body
                                                 error:&requestError];
    if (!response) {
        GZ_LOG_INFO(@"[TelegramGateway] checkSendAbility failed for %@: %@", [GZLogRedactor maskToken:phoneNumber], requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorSendAbilityCheckFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Send ability check failed"
                                     }];
        }
        return nil;
    }

    NSNumber *ok = response[@"ok"];
    if (!ok || !ok.boolValue) {
        NSString *errorMsg = response[@"error"] ?: @"Unknown error";
        GZ_LOG_INFO(@"[TelegramGateway] checkSendAbility returned error for %@: %@", [GZLogRedactor maskToken:phoneNumber], errorMsg);
        if (error) {
            *error = [NSError errorWithDomain:PDSTelegramGatewayProviderErrorDomain
                                         code:PDSTelegramGatewayProviderErrorSendAbilityCheckFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Send ability check failed: %@", errorMsg]
                                     }];
        }
        return nil;
    }

    NSDictionary *result = response[@"result"];
    NSString *requestID = result[@"request_id"];
    GZ_LOG_INFO(@"[TelegramGateway] checkSendAbility OK for %@ (request_id: %@)", [GZLogRedactor maskToken:phoneNumber], requestID);
    return requestID;
}

@end
