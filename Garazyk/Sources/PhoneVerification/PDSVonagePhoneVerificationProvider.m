/*!
 @file PDSVonagePhoneVerificationProvider.m

 @abstract Vonage Verify phone verification provider implementation.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PhoneVerification/PDSVonagePhoneVerificationProvider.h"
#import "Core/PDSProviderHTTPClient.h"
#import "Email/PDSSecretsProvider.h"
#import "Debug/PDSLogger.h"

static NSString *const kVonageVerifyBaseURL = @"https://api.nexmo.com";
static NSString *const kVonageAPIKeyEnvVar = @"VONAGE_API_KEY";
static NSString *const kVonageAPISecretEnvVar = @"VONAGE_API_SECRET";
static NSString *const kVonageBrandNameEnvVar = @"VONAGE_BRAND_NAME";
static NSString *const kVonageDefaultBrandName = @"Garazyk";

NSString *const PDSVonageProviderErrorDomain = @"com.atproto.pds.vonageprovider";

@interface PDSVonagePhoneVerificationProvider () {
    dispatch_queue_t _initQueue;
}
@property (nonatomic, strong) id<PDSSecretsProvider> secretsProvider;
@property (nonatomic, copy) NSDictionary *providerConfig;
@property (nonatomic, strong, nullable) PDSProviderHTTPClient *httpClient;
@property (nonatomic, copy, nullable) NSString *apiKey;
@property (nonatomic, copy, nullable) NSString *apiSecret;
@property (nonatomic, copy, nullable) NSString *brandName;
@end

@implementation PDSVonagePhoneVerificationProvider

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
        _initQueue = dispatch_queue_create("com.atproto.pds.vonage.init", DISPATCH_QUEUE_SERIAL);
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
        NSString *apiKey = [self.secretsProvider secretForKey:kVonageAPIKeyEnvVar
                                                        error:&secretError];
        if (!apiKey || apiKey.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                             code:PDSVonageProviderErrorMissingAPIKey
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Vonage API Key"
                                         }];
            }
            return;
        }

        NSString *apiSecret = [self.secretsProvider secretForKey:kVonageAPISecretEnvVar
                                                           error:&secretError];
        if (!apiSecret || apiSecret.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                             code:PDSVonageProviderErrorMissingAPISecret
                                         userInfo:@{
                                             NSLocalizedDescriptionKey: @"Missing Vonage API Secret"
                                         }];
            }
            return;
        }

        NSString *brandName = [self.secretsProvider secretForKey:kVonageBrandNameEnvVar
                                                           error:&secretError];
        if (!brandName || brandName.length == 0) {
            brandName = kVonageDefaultBrandName;
        }

        self->_apiKey = [apiKey copy];
        self->_apiSecret = [apiSecret copy];
        self->_brandName = [brandName copy];

        // Vonage uses API key/secret in form body, not headers.
        // Create HTTP client with base URL and empty auth header.
        NSURL *baseURL = [NSURL URLWithString:kVonageVerifyBaseURL];
        self->_httpClient = [[PDSProviderHTTPClient alloc]
            initWithBaseURL:baseURL authHeader:@""];
        success = YES;
    });
    return success;
}

#pragma mark - PDSPhoneVerificationProvider

- (nullable NSString *)requestVerificationForPhoneNumber:(NSString *)phoneNumber error:(NSError **)error {
    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorInvalidPhoneNumber
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

    PDS_LOG_INFO(@"[Vonage] Sending verification to: %@", phoneNumber);

    // POST /verify/json with form-encoded params
    NSDictionary *params = @{
        @"api_key": self.apiKey,
        @"api_secret": self.apiSecret,
        @"number": phoneNumber,
        @"brand": self.brandName
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postFormPath:@"/verify/json"
                                                   params:params
                                                    error:&requestError];
    if (!response) {
        PDS_LOG_ERROR(@"[Vonage] Failed to send verification: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorRequestFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Failed to send verification"
                                     }];
        }
        return nil;
    }

    NSString *status = response[@"status"];
    NSString *requestID = response[@"request_id"];

    // Vonage returns status "0" for success
    if (![status isEqualToString:@"0"]) {
        NSString *errorText = response[@"error_text"] ?: @"Unknown error";
        PDS_LOG_ERROR(@"[Vonage] Verification send failed (status: %@, error: %@)", status, errorText);
        if (error) {
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorRequestFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             [NSString stringWithFormat:@"Vonage verification failed: %@", errorText]
                                     }];
        }
        return nil;
    }

    PDS_LOG_INFO(@"[Vonage] Verification sent to %@ (request_id: %@)", phoneNumber, requestID);
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
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing verification code"
                                     }];
        }
        return NO;
    }

    if (!phoneNumber || phoneNumber.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorInvalidPhoneNumber
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing phone number"
                                     }];
        }
        return NO;
    }

    if (!sessionID || sessionID.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: @"Missing session ID (request_id) for Vonage verification"
                                     }];
        }
        return NO;
    }

    NSError *initError = nil;
    if (![self ensureInitializedWithError:&initError]) {
        if (error) *error = initError;
        return NO;
    }

    PDS_LOG_INFO(@"[Vonage] Checking verification code for: %@ (request_id: %@)", phoneNumber, sessionID);

    // POST /verify/check/json with form-encoded params
    NSDictionary *params = @{
        @"api_key": self.apiKey,
        @"api_secret": self.apiSecret,
        @"request_id": sessionID,
        @"code": code
    };

    NSError *requestError = nil;
    NSDictionary *response = [self.httpClient postFormPath:@"/verify/check/json"
                                                   params:params
                                                    error:&requestError];
    if (!response) {
        PDS_LOG_ERROR(@"[Vonage] Verification check failed: %@", requestError);
        if (error) {
            *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                         code:PDSVonageProviderErrorVerificationFailed
                                     userInfo:@{
                                         NSLocalizedDescriptionKey:
                                             requestError.localizedDescription ?: @"Verification check failed"
                                     }];
        }
        return NO;
    }

    NSString *status = response[@"status"];
    if ([status isEqualToString:@"0"]) {
        PDS_LOG_INFO(@"[Vonage] Verification approved for %@", phoneNumber);
        return YES;
    }

    NSString *errorText = response[@"error_text"] ?: @"unknown";
    PDS_LOG_INFO(@"[Vonage] Verification not approved for %@ (status: %@, error: %@)", phoneNumber, status, errorText);
    if (error) {
        *error = [NSError errorWithDomain:PDSVonageProviderErrorDomain
                                     code:PDSVonageProviderErrorVerificationFailed
                                 userInfo:@{
                                     NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:
                                             @"Verification not approved (status: %@, error: %@)",
                                             status ?: @"unknown", errorText]
                                 }];
    }
    return NO;
}

@end
