// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface OAuth2Handler (ClientValidation)
- (void)validateClient:(NSString *)clientID
            completion:(void (^)(NSDictionary *_Nullable client,
                                 NSError *_Nullable error))completion;
- (nullable NSDictionary *)validatedClientForClientID:(NSString *)clientID
                                                error:(NSError **)error;
- (BOOL)isClientValidationTimeoutError:(NSError *)error;
- (void)setOAuthErrorResponse:(HttpResponse *)response
                       status:(NSInteger)status
                        error:(NSString *)errorCode
             errorDescription:(NSString *)errorDescription;
- (NSDictionary *)sanitizeClientMetadataIfNeeded:(NSDictionary *)validatedClient
                                        clientID:(NSString *)clientID;
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error;
- (NSDictionary *)getClientPublicKeys:(NSDictionary *)client
                                error:(NSError **)error;
- (BOOL)validateJWTAssertion:(NSString *)assertion
                   withClient:(NSDictionary *)client
                        error:(NSError **)error;
- (SecKeyRef)createECPublicKeyFromX:(NSData *)xData Y:(NSData *)yData;
- (BOOL)isLoopbackURL:(NSString *)urlString;
- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
