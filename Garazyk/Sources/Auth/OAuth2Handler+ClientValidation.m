// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+ClientValidation.h"
#import "Auth/OAuth2.h"
#import "Security/PDSSecurityCompare.h"
#import "Auth/CryptoUtils.h"
#import "Auth/PDSReplayCache.h"
#import "Database/PDSDatabase.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"
#import <CommonCrypto/CommonDigest.h>

@implementation OAuth2Handler (ClientValidation)

#pragma mark - Client Validation
- (NSDictionary *)sanitizeClientMetadataIfNeeded:(NSDictionary *)validatedClient
                                        clientID:(NSString *)clientID {
  if (!validatedClient) {
    return nil;
  }
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  if ([config.oauthTrustedClientIDs containsObject:clientID]) {
    return validatedClient;
  }
  // Otherwise, untrusted: overwrite client_name with the raw clientID
  NSMutableDictionary *mutableClient = [validatedClient mutableCopy];
  mutableClient[@"client_name"] = clientID;
  return [mutableClient copy];
}

- (void)validateClient:(NSString *)clientID
            completion:(void (^)(NSDictionary *_Nullable client,
                                 NSError *_Nullable error))completion {
  if (!completion)
    return;

  if (!clientID) {
    completion(nil, [NSError errorWithDomain:@"OAuth2"
                                        code:400
                                    userInfo:@{
                                      NSLocalizedDescriptionKey :
                                          @"Missing client_id"
                                    }]);
    return;
  }

  // First attempt: Query database (existing path - preserve this exactly)
  NSError *dbError = nil;
  NSDictionary *client = [self.database getClientWithID:clientID error:&dbError];
  if (client) {
    // Database lookup succeeded - return the client
    completion(client, nil);
    return;
  }

  // Operator policy check: if allowlist is enabled, reject if not in allowed_client_ids
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  if ([config.oauthClientPolicy isEqualToString:@"allowlist"]) {
    if (![config.oauthAllowedClientIDs containsObject:clientID]) {
      GZ_LOG_AUTH_WARN(@"OAuth client rejected by allowlist policy: %@", clientID);
      completion(nil, [NSError errorWithDomain:@"OAuth2"
                                          code:400
                                      userInfo:@{
                                        NSLocalizedDescriptionKey : @"unauthorized_client"
                                      }]);
      return;
    }
  }

  // Database lookup failed - check if client_metadata is available in request
  if (self.clientMetadata) {
    GZ_LOG_AUTH_INFO(@"Client not in database, attempting validation via "
                      @"client_metadata for client_id: %@",
                      clientID);

    // Validate using client_metadata
    NSError *metadataError = nil;
    NSDictionary *validatedClient =
        [self validateClientMetadata:self.clientMetadata error:&metadataError];

    if (validatedClient) {
      NSString *metadataClientID = [validatedClient[@"client_id"]
          isKindOfClass:[NSString class]]
                                       ? validatedClient[@"client_id"]
                                       : nil;
      if (metadataClientID.length == 0 ||
          ![CryptoUtils constantTimeCompare:metadataClientID to:clientID]) {
        NSError *mismatchError = [NSError errorWithDomain:@"OAuth2"
                                                     code:400
                                                 userInfo:@{
                                                   NSLocalizedDescriptionKey :
                                                       @"client_id does not match "
                                                       @"client_metadata"
                                                 }];
        GZ_LOG_AUTH_WARN(@"client_metadata client_id mismatch for request client_id: %@", clientID);
        completion(nil, mismatchError);
        return;
      }
      GZ_LOG_AUTH_INFO(
          @"Client validated successfully via client_metadata: %@", clientID);
      completion([self sanitizeClientMetadataIfNeeded:validatedClient clientID:clientID], nil);
      return;
    } else {
      // Metadata validation failed
      GZ_LOG_AUTH_WARN(@"Client validation via client_metadata failed for client_id %@: %@",
                       clientID, metadataError.localizedDescription ?: @"Unknown error");
      completion(nil, metadataError);
      return;
    }
  }

  // Not in DB and not in request - check if it's a URL-based client_id for
  // dynamic discovery
  if ([clientID hasPrefix:@"https://"] || [self isLoopbackURL:clientID]) {
    GZ_LOG_AUTH_INFO(@"Attempting dynamic client discovery for: %@", clientID);

    dispatch_once(&sClientCacheOnceToken, ^{
      sClientMetadataCache = [[NSCache alloc] init];
      sClientMetadataCache.countLimit = 1000;
    });

    __block NSDictionary *cached = nil;
    dispatch_sync(sClientMetadataQueue, ^{
      cached = [sClientMetadataCache objectForKey:clientID];
    });
    if (cached) {
      GZ_LOG_AUTH_INFO(@"Found cached metadata for client: %@", clientID);
      completion([self sanitizeClientMetadataIfNeeded:cached clientID:clientID], nil);
      return;
    }

    __weak typeof(self) weakSelf = self;
    [self fetchClientMetadataFromURL:clientID
                          completion:^(NSDictionary *_Nullable fetchedMetadata,
                                       NSError *_Nullable fetchError) {
                            __strong typeof(weakSelf) strongSelf = weakSelf;
                            if (!strongSelf) return;
                            
                            if (fetchedMetadata) {
                              NSError *validationError = nil;
                              NSDictionary *validatedClient =
                                  [strongSelf validateClientMetadata:fetchedMetadata
                                                         error:&validationError];
                              if (validatedClient) {
                                // Ensure client_id in metadata matches the URL
                                NSString *metadataClientID =
                                    validatedClient[@"client_id"];
                                if ([PDSSecurityCompare constantTimeEqualString:metadataClientID string:clientID]) {
                                  dispatch_sync(sClientMetadataQueue, ^{
                                    [sClientMetadataCache
                                         setObject:validatedClient
                                            forKey:clientID];
                                  });
                                  GZ_LOG_AUTH_INFO(@"Successfully discovered "
                                                    @"and cached client: %@",
                                                    clientID);
                                  completion([strongSelf sanitizeClientMetadataIfNeeded:validatedClient clientID:clientID], nil);
                                } else {
                                  completion(
                                      nil,
                                      [NSError
                                          errorWithDomain:@"OAuth2"
                                                     code:400
                                                 userInfo:@{
                                                   NSLocalizedDescriptionKey :
                                                       @"client_id in fetched "
                                                       @"metadata does not "
                                                       @"match request "
                                                       @"client_id URL"
                                                 }]);
                                }
                              } else {
                                completion(nil, validationError);
                              }
                            } else {
                              completion(nil, fetchError);
                            }
                          }];
    return;
  }

  // Not found in database AND no client_metadata provided
  completion(nil, [NSError errorWithDomain:@"OAuth2"
                                      code:401
                                  userInfo:@{
                                    NSLocalizedDescriptionKey : @"Invalid client"
                                  }]);
}

- (nullable NSDictionary *)validatedClientForClientID:(NSString *)clientID
                                                 error:(NSError **)error {
  __block NSDictionary *client = nil;
  __block NSError *clientError = nil;
  dispatch_semaphore_t clientSem = dispatch_semaphore_create(0);

  [self validateClient:clientID
            completion:^(NSDictionary *_Nullable fetchedClient,
                         NSError *_Nullable fetchedError) {
              client = fetchedClient;
              clientError = fetchedError;
              dispatch_semaphore_signal(clientSem);
            }];

  dispatch_time_t timeout =
      dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(kClientValidationTimeoutSeconds * NSEC_PER_SEC));
  long waitResult = dispatch_semaphore_wait(clientSem, timeout);
  if (waitResult != 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:kClientValidationTimeoutCode
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Timed out while validating client credentials"
                 }];
    }
    return nil;
  }

  if (!client) {
    if (error) {
      *error = clientError
                   ?: [NSError errorWithDomain:@"OAuth2"
                                          code:401
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Invalid client"
                                      }];
    }
    return nil;
  }

  return client;
}

- (BOOL)isClientValidationTimeoutError:(NSError *)error {
  return [error.domain isEqualToString:@"OAuth2"] &&
         error.code == kClientValidationTimeoutCode;
}

#pragma mark - OAuth Error Response
- (void)setOAuthErrorResponse:(HttpResponse *)response
                       status:(NSInteger)status
                        error:(NSString *)errorCode
             errorDescription:(NSString *)errorDescription {
  GZ_LOG_AUTH_WARN(@"OAuth error response status %ld (%@): %@", (long)status, errorCode ?: @"server_error", errorDescription ?: @"Unknown OAuth error");
  response.statusCode = (HttpStatusCode)status;
  [response setJsonBody:@{
    @"error" : errorCode ?: @"server_error",
    @"error_description" : errorDescription ?: @"Unknown OAuth error"
  }];
}

#pragma mark - Client Metadata & JWT Validation
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error {
  if (!metadata || ![metadata isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"client_metadata must be a JSON object"
                               }];
    }
    return nil;
  }

  // Validate client_id is HTTPS URL (required by ATProto spec)
  NSString *clientID = metadata[@"client_id"];
  if (!clientID || ![clientID isKindOfClass:[NSString class]]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"client_id is required in client_metadata"
                               }];
    }
    return nil;
  }

  if (![clientID hasPrefix:@"https://"] && ![self isLoopbackURL:clientID]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"client_id must be an HTTPS URL or a loopback address"
                               }];
    }
    return nil;
  }

  // Validate it's a valid URL
  NSURL *clientIDURL = [NSURL URLWithString:clientID];
  if (!clientIDURL || !clientIDURL.host) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"client_id must be a valid URL"
                               }];
    }
    return nil;
  }

  // Validate redirect_uris array is present, non-empty, and contains valid URIs
  NSArray *redirectURIs = metadata[@"redirect_uris"];
  if (!redirectURIs || ![redirectURIs isKindOfClass:[NSArray class]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"redirect_uris array is required in client_metadata"
                 }];
    }
    return nil;
  }

  if (redirectURIs.count == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"redirect_uris array must contain at least one URI"
                 }];
    }
    return nil;
  }

  // Validate each redirect_uri is a valid URI string
  for (id redirectURI in redirectURIs) {
    if (![redirectURI isKindOfClass:[NSString class]]) {
      if (error) {
        *error = [NSError errorWithDomain:@"OAuth2"
                                     code:400
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"All redirect_uris must be strings"
                                 }];
      }
      return nil;
    }

    NSString *uriString = (NSString *)redirectURI;
    NSURL *uri = [NSURL URLWithString:uriString];
    if (!uri || !uri.scheme) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         [NSString stringWithFormat:@"Invalid redirect_uri: %@",
                                                    uriString]
                   }];
      }
      return nil;
    }
  }

  // Extract client_name (optional but recommended)
  NSString *clientName = metadata[@"client_name"];
  if (clientName && ![clientName isKindOfClass:[NSString class]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"client_name must be a string"
                 }];
    }
    return nil;
  }

  // Extract grant_types (optional, defaults to ATProto-required grants)
  id grantTypes = metadata[@"grant_types"];
  NSMutableArray<NSString *> *normalizedGrantTypes = [NSMutableArray array];
  if (grantTypes) {
    if ([grantTypes isKindOfClass:[NSArray class]]) {
      for (id value in (NSArray *)grantTypes) {
        if (![value isKindOfClass:[NSString class]] ||
            [(NSString *)value length] == 0) {
          if (error) {
            *error = [NSError errorWithDomain:@"OAuth2"
                                         code:400
                                     userInfo:@{
                                       NSLocalizedDescriptionKey :
                                           @"grant_types values must be "
                                           @"non-empty strings"
                                     }];
          }
          return nil;
        }
        [normalizedGrantTypes addObject:(NSString *)value];
      }
    } else if ([grantTypes isKindOfClass:[NSString class]]) {
      NSArray<NSString *> *parts = [(NSString *)grantTypes
          componentsSeparatedByCharactersInSet:
              [NSCharacterSet whitespaceCharacterSet]];
      for (NSString *part in parts) {
        if (part.length > 0) {
          [normalizedGrantTypes addObject:part];
        }
      }
    } else {
      if (error) {
        *error = [NSError errorWithDomain:@"OAuth2"
                                     code:400
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"grant_types must be an array or string"
                                 }];
      }
      return nil;
    }
  } else {
    [normalizedGrantTypes addObjectsFromArray:@[
      @"authorization_code", @"refresh_token"
    ]];
  }

  NSSet<NSString *> *grantTypesSet =
      [NSSet setWithArray:normalizedGrantTypes];
  if (![grantTypesSet containsObject:@"authorization_code"] ||
      ![grantTypesSet containsObject:@"refresh_token"]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"grant_types must include authorization_code and "
                       @"refresh_token"
                 }];
    }
    return nil;
  }

  NSSet<NSString *> *allowedGrantTypes =
      [NSSet setWithArray:@[ @"authorization_code", @"refresh_token" ]];
  for (NSString *grantType in grantTypesSet) {
    if (![allowedGrantTypes containsObject:grantType]) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         [NSString stringWithFormat:
                                       @"Unsupported grant_type in "
                                       @"client_metadata: %@",
                                       grantType]
                   }];
      }
      return nil;
    }
  }

  // Extract scope (optional, default to "atproto")
  NSString *scope = metadata[@"scope"];
  if (scope && ![scope isKindOfClass:[NSString class]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"scope must be a string"
                 }];
    }
    return nil;
  }
  if (!scope) {
    scope = @"atproto";
  }

  NSArray<NSString *> *scopeParts =
      [scope componentsSeparatedByCharactersInSet:
                 [NSCharacterSet whitespaceCharacterSet]];
  BOOL hasATProtoScope = NO;
  for (NSString *scopePart in scopeParts) {
    if ([scopePart isEqualToString:@"atproto"]) {
      hasATProtoScope = YES;
      break;
    }
  }
  if (!hasATProtoScope) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"scope must include atproto"
                               }];
    }
    return nil;
  }

  // ATProto requires response_types to include only "code".
  id responseTypesValue = metadata[@"response_types"];
  NSMutableArray<NSString *> *responseTypes = [NSMutableArray array];
  if ([responseTypesValue isKindOfClass:[NSArray class]]) {
    for (id value in (NSArray *)responseTypesValue) {
      if (![value isKindOfClass:[NSString class]] ||
          [(NSString *)value length] == 0) {
        if (error) {
          *error = [NSError errorWithDomain:@"OAuth2"
                                       code:400
                                   userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         @"response_types must contain "
                                         @"non-empty strings"
                                   }];
        }
        return nil;
      }
      [responseTypes addObject:(NSString *)value];
    }
  } else if ([responseTypesValue isKindOfClass:[NSString class]]) {
    NSArray<NSString *> *parts = [(NSString *)responseTypesValue
        componentsSeparatedByCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    for (NSString *part in parts) {
      if (part.length > 0) {
        [responseTypes addObject:part];
      }
    }
  } else {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"response_types is required in "
                                     @"client_metadata"
                               }];
    }
    return nil;
  }

  if (responseTypes.count == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"response_types must include code"
                               }];
    }
    return nil;
  }

  for (NSString *responseType in responseTypes) {
    if (![responseType isEqualToString:@"code"]) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         [NSString stringWithFormat:
                                       @"Unsupported response_type in "
                                       @"client_metadata: %@",
                                       responseType]
                   }];
      }
      return nil;
    }
  }

  // ATProto clients must request DPoP-bound access tokens.
  id dpopBoundAccessTokens = metadata[@"dpop_bound_access_tokens"];
  if (![dpopBoundAccessTokens isKindOfClass:[NSNumber class]] ||
      ![(NSNumber *)dpopBoundAccessTokens boolValue]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"dpop_bound_access_tokens must be true"
                 }];
    }
    return nil;
  }

  id tokenEndpointAuthMethodValue = metadata[@"token_endpoint_auth_method"];
  if (![tokenEndpointAuthMethodValue isKindOfClass:[NSString class]] ||
      [(NSString *)tokenEndpointAuthMethodValue length] == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"token_endpoint_auth_method is required in "
                       @"client_metadata"
                 }];
    }
    return nil;
  }

  NSString *tokenEndpointAuthMethod = (NSString *)tokenEndpointAuthMethodValue;
  NSSet<NSString *> *allowedAuthMethods =
      [NSSet setWithArray:@[ @"none", @"private_key_jwt" ]];
  if (![allowedAuthMethods containsObject:tokenEndpointAuthMethod]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       [NSString
                           stringWithFormat:
                               @"Unsupported token_endpoint_auth_method: %@",
                               tokenEndpointAuthMethod]
                 }];
    }
    return nil;
  }

  id signingAlgValue = metadata[@"token_endpoint_auth_signing_alg"];
  NSString *signingAlg =
      [signingAlgValue isKindOfClass:[NSString class]]
          ? (NSString *)signingAlgValue
          : nil;
  if (signingAlgValue && ![signingAlgValue isKindOfClass:[NSString class]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"token_endpoint_auth_signing_alg must be a string"
                 }];
    }
    return nil;
  }

  id jwksValue = metadata[@"jwks"];
  if (jwksValue && ![jwksValue isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"jwks must be an object"
                 }];
    }
    return nil;
  }

  id jwksURIValue = metadata[@"jwks_uri"];
  NSString *jwksURI = nil;
  if (jwksURIValue) {
    if (![jwksURIValue isKindOfClass:[NSString class]] ||
        [(NSString *)jwksURIValue length] == 0) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"jwks_uri must be a non-empty string"
                   }];
      }
      return nil;
    }
    jwksURI = (NSString *)jwksURIValue;
  }

  BOOL hasJWKS = ([jwksValue isKindOfClass:[NSDictionary class]]);
  BOOL hasJWKSURI = (jwksURI.length > 0);
  if (hasJWKS && hasJWKSURI) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Only one of jwks or jwks_uri may be provided"
                 }];
    }
    return nil;
  }

  if ([tokenEndpointAuthMethod isEqualToString:@"private_key_jwt"]) {
    if (!hasJWKS && !hasJWKSURI) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"private_key_jwt clients must provide jwks or "
                         @"jwks_uri"
                   }];
      }
      return nil;
    }
    if (signingAlg.length == 0 || ![signingAlg isEqualToString:@"ES256"]) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"private_key_jwt requires "
                         @"token_endpoint_auth_signing_alg=ES256"
                   }];
      }
      return nil;
    }
  } else {
    if (hasJWKS || hasJWKSURI || signingAlg.length > 0) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         @"Public clients using token_endpoint_auth_method=none "
                         @"must not provide jwks, jwks_uri, or "
                         @"token_endpoint_auth_signing_alg"
                   }];
      }
      return nil;
    }
  }

  NSString *applicationType = metadata[@"application_type"];
  if (applicationType && ![applicationType isKindOfClass:[NSString class]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"application_type must be a string"
                 }];
    }
    return nil;
  }

  // Return normalized client dictionary matching database format for
  // consistency
  return @{
    @"client_id" : clientID,
    @"redirect_uris" : redirectURIs,
    @"client_name" : clientName ?: clientID,
    @"grant_types" : [normalizedGrantTypes componentsJoinedByString:@" "],
    @"scope" : scope,
    @"response_types" : [responseTypes componentsJoinedByString:@" "],
    @"dpop_bound_access_tokens" : @YES,
    @"token_endpoint_auth_method" : tokenEndpointAuthMethod,
    @"token_endpoint_auth_signing_alg" : signingAlg ?: @"",
    @"jwks" : jwksValue ?: @{},
    @"jwks_uri" : jwksURI ?: @"",
    @"application_type" : applicationType ?: @"web"
  };
}

- (NSDictionary *)getClientPublicKeys:(NSDictionary *)client
                                error:(NSError **)error {
  NSDictionary *jwks = client[@"jwks"];
  NSString *jwksURI = client[@"jwks_uri"];

  if ([jwks isKindOfClass:[NSDictionary class]] && jwks.count > 0) {
    return jwks;
  }

  if (jwksURI.length > 0) {
    NSURL *url = [NSURL URLWithString:jwksURI];
    if (!url) {
      if (error) {
        *error = [NSError errorWithDomain:@"OAuth2"
                                     code:400
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"Invalid jwks_uri"
                                 }];
      }
      return nil;
    }

    __block NSData *responseData = nil;
    __block NSError *fetchError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURLSessionConfiguration *config =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session
        dataTaskWithURL:url
      completionHandler:^(NSData *data, NSURLResponse *response,
                          NSError *err) {
        responseData = data;
        fetchError = err;
        dispatch_semaphore_signal(semaphore);
      }];
    [task resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW,
                                                     10 * NSEC_PER_SEC));

    if (fetchError || !responseData) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"OAuth2"
                       code:400
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                         [NSString stringWithFormat:
                                       @"Failed to fetch JWKS from %@",
                                       jwksURI]
                   }];
      }
      return nil;
    }

    NSError *jsonError = nil;
    NSDictionary *remoteJWKS = [NSJSONSerialization
        JSONObjectWithData:responseData
                   options:0
                     error:&jsonError];
    if (![remoteJWKS isKindOfClass:[NSDictionary class]]) {
      if (error) {
        *error = [NSError errorWithDomain:@"OAuth2"
                                     code:400
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"Invalid JWKS response"
                                 }];
      }
      return nil;
    }
    return remoteJWKS;
  }

  if (error) {
    *error = [NSError errorWithDomain:@"OAuth2"
                                 code:400
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Client has no jwks or jwks_uri"
                             }];
  }
  return nil;
}

- (BOOL)validateJWTAssertion:(NSString *)assertion
                   withClient:(NSDictionary *)client
                        error:(NSError **)error {
  if (!assertion || assertion.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Missing client_assertion"
                               }];
    }
    return NO;
  }

  NSArray<NSString *> *parts = [assertion componentsSeparatedByString:@"."];
  if (parts.count != 3) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid JWT assertion format"
                               }];
    }
    return NO;
  }

  NSError *parseError = nil;
  JWT *jwt = [JWT jwtWithToken:assertion error:&parseError];
  if (!jwt) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to parse JWT assertion"
                               }];
    }
    return NO;
  }

  NSString *clientID = client[@"client_id"];
  JWTPayload *jwtPayload = jwt.payload;
  NSDictionary *payload = [jwtPayload toDictionary];

  if (![payload isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid JWT payload"
                               }];
    }
    return NO;
  }

  NSString *iss = payload[@"iss"];
  NSString *sub = payload[@"sub"];
  NSString *aud = payload[@"aud"];
  NSString *jti = payload[@"jti"];
  NSNumber *exp = payload[@"exp"];

  if (!iss || ![iss isKindOfClass:[NSString class]] ||
      ![PDSSecurityCompare constantTimeEqualString:iss string:clientID]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid 'iss' claim: must match client_id"
                               }];
    }
    return NO;
  }

  if (!sub || ![sub isKindOfClass:[NSString class]] ||
      ![PDSSecurityCompare constantTimeEqualString:sub string:clientID]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid 'sub' claim: must match client_id"
                               }];
    }
    return NO;
  }

  NSString *expectedAud = [ATProtoServiceConfiguration sharedConfiguration].issuer;
  if (!expectedAud) {
    expectedAud = @"https://pds.garazyk.xyz";
  }
  if (!aud || ![aud isKindOfClass:[NSString class]] ||
      ![PDSSecurityCompare constantTimeEqualString:aud string:expectedAud]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid 'aud' claim: must match issuer"
                               }];
    }
    return NO;
  }

  if (!exp || ![exp isKindOfClass:[NSNumber class]]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Missing 'exp' claim"
                               }];
    }
    return NO;
  }

  NSTimeInterval expTime = [exp doubleValue];
  NSDate *expirationDate = [NSDate dateWithTimeIntervalSince1970:expTime];
  if ([[NSDate date] compare:expirationDate] != NSOrderedAscending) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"JWT assertion has expired"
                               }];
    }
    return NO;
  }

  if (!jti || ![jti isKindOfClass:[NSString class]] || jti.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Missing 'jti' claim for replay protection"
                               }];
    }
    return NO;
  }

  if (![[PDSReplayCache sharedCache] checkAndAddJTI:jti
                                          expiration:expirationDate]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"JWT assertion 'jti' has been replayed"
                               }];
    }
    return NO;
  }

  NSError *keysError = nil;
  NSDictionary *clientKeys = [self getClientPublicKeys:client error:&keysError];
  if (!clientKeys) {
    if (error) {
      *error = keysError;
    }
    return NO;
  }

  NSArray *keys = clientKeys[@"keys"];
  if (![keys isKindOfClass:[NSArray class]] || keys.count == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"No keys found in client JWKS"
                               }];
    }
    return NO;
  }

  NSString *kid = jwt.header.kid;
  NSDictionary *matchingKey = nil;
  for (NSDictionary *key in keys) {
    if ([key isKindOfClass:[NSDictionary class]]) {
      NSString *keyKid = key[@"kty"];
      if ([keyKid isEqualToString:@"EC"]) {
        NSString *keyID = key[@"kid"];
        if (kid.length == 0) {
          if (!matchingKey) {
            matchingKey = key;
          }
        } else if ([keyID isEqualToString:kid]) {
          matchingKey = key;
          break;
        }
      }
    }
  }

  if (!matchingKey) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"No matching key found in client JWKS"
                               }];
    }
    return NO;
  }

  NSString *kty = matchingKey[@"kty"];
  if (![kty isEqualToString:@"EC"]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Only EC (elliptic curve) keys supported"
                               }];
    }
    return NO;
  }

  NSString *crv = matchingKey[@"crv"];
  if (![crv isEqualToString:@"P-256"]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Only P-256 (ES256) curve supported"
                               }];
    }
    return NO;
  }

  NSString *xB64 = matchingKey[@"x"];
  NSString *yB64 = matchingKey[@"y"];
  if (!xB64 || !yB64) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid EC key format"
                               }];
    }
    return NO;
  }

  NSData *xData = [JWT base64URLDecode:xB64 error:&parseError];
  NSData *yData = [JWT base64URLDecode:yB64 error:&parseError];
  if (!xData || !yData) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid key coordinate encoding"
                               }];
    }
    return NO;
  }

  SecKeyRef publicKey = [self createECPublicKeyFromX:xData Y:yData];
  if (!publicKey) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to create public key from JWKS"
                               }];
    }
    return NO;
  }

  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0],
                                                     parts[1]];
  NSData *signingInputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
  NSData *signatureData = [JWT base64URLDecode:parts[2] error:&parseError];

  if (!signatureData) {
    CFRelease(publicKey);
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid signature encoding"
                               }];
    }
    return NO;
  }

  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(signingInputData.bytes, (CC_LONG)signingInputData.length, hash);
  NSData *hashData = [NSData dataWithBytes:hash length:CC_SHA256_DIGEST_LENGTH];

  CFErrorRef verifyError = NULL;
  BOOL signatureValid =
      SecKeyVerifySignature(publicKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                             (__bridge CFDataRef)hashData,
                             (__bridge CFDataRef)signatureData,
                             &verifyError);

  CFRelease(publicKey);

  if (!signatureValid) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:401
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid JWT signature"
                               }];
    }
    return NO;
  }

  return YES;
}

- (SecKeyRef)createECPublicKeyFromX:(NSData *)xData Y:(NSData *)yData {
  uint8_t *publicKeyBytes =
      (uint8_t *)malloc(xData.length + yData.length + 1);
  publicKeyBytes[0] = 0x04;
  memcpy(publicKeyBytes + 1, xData.bytes, xData.length);
  memcpy(publicKeyBytes + 1 + xData.length, yData.bytes, yData.length);

  NSDictionary *attributes = @{
    (__bridge id)kSecAttrKeyType : (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
    (__bridge id)kSecAttrKeyClass : (__bridge id)kSecAttrKeyClassPublic,
    (__bridge id)kSecAttrKeySizeInBits : @256
  };

  CFErrorRef error = NULL;
  SecKeyRef publicKey = SecKeyCreateWithData(
      (__bridge CFDataRef)[NSData dataWithBytes:publicKeyBytes
                                          length:xData.length + yData.length + 1],
      (__bridge CFDictionaryRef)attributes, &error);

  free(publicKeyBytes);

  return publicKey;
}

- (BOOL)isLoopbackURL:(NSString *)urlString {
  if (!urlString)
    return NO;
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url || !url.host)
    return NO;
  if (![[url.scheme lowercaseString] isEqualToString:@"http"])
    return NO;

  NSString *host = [url.host lowercaseString];
  return ([host isEqualToString:@"127.0.0.1"] ||
          [host isEqualToString:@"localhost"] ||
          [host isEqualToString:@"::1"] || [host isEqualToString:@"[::1]"]);
}

- (BOOL)validateRedirectURI:(NSString *)redirectURI
                  forClient:(NSDictionary *)client
                      error:(NSError **)error {
  if (!redirectURI) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"OAuth2"
                              code:400
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"Missing redirect_uri"
                          }];
    }
    return NO;
  }

  NSURL *url = [NSURL URLWithString:redirectURI];
  if (!url) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Invalid redirect_uri format"
                 }];
    }
    return NO;
  }

  BOOL isLoopback = [self isLoopbackURL:redirectURI];

  // Scheme validation: HTTPS required unless it's a loopback redirect (RFC
  // 8252)
  if (!isLoopback) {
#ifndef DEBUG
    if (![url.scheme isEqualToString:@"https"]) {
      if (error) {
        *error =
            [NSError errorWithDomain:@"OAuth2"
                                code:400
                            userInfo:@{
                              NSLocalizedDescriptionKey :
                                  @"redirect_uri must use HTTPS in production"
                            }];
      }
      return NO;
    }
#else
    if ([url.scheme isEqualToString:@"http"]) {
      NSString *host = url.host;
      if (![host isEqualToString:@"localhost"] &&
          ![host isEqualToString:@"127.0.0.1"]) {
        if (error) {
          *error = [NSError errorWithDomain:@"OAuth2"
                                       code:400
                                   userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         @"HTTP redirect_uri only allowed for "
                                         @"localhost in development"
                                   }];
        }
        return NO;
      }
    }
#endif
  }

  // Check if the redirect URI is in the client's registered URIs
  NSArray *allowedURIs = client[@"redirect_uris"];
  if (!allowedURIs || ![allowedURIs isKindOfClass:[NSArray class]]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Client has no registered redirect URIs"
                               }];
    }
    return NO;
  }

  GZ_LOG_AUTH_DEBUG(@"Validating redirect_uri: '%@' against allowed: %@",
                     redirectURI, allowedURIs);

  for (NSString *allowedURI in allowedURIs) {
    // Exact match (standard OAuth 2.0 security best practice)
    if ([PDSSecurityCompare constantTimeEqualString:redirectURI string:allowedURI]) {
      GZ_LOG_AUTH_DEBUG(@"Successfully matched redirect_uri: %@", allowedURI);
      return YES;
    }

    // Loopback port wildcard matching per RFC 8252 §7.3:
    // If the allowed URI is a loopback address, match ignoring port.
    if (isLoopback && [self isLoopbackURL:allowedURI]) {
      NSURL *allowedURL = [NSURL URLWithString:allowedURI];
      if (allowedURL &&
          [[url.host lowercaseString]
              isEqualToString:[allowedURL.host lowercaseString]] &&
          [[url.path ?: @"/" lowercaseString]
              isEqualToString:[allowedURL.path ?: @"/" lowercaseString]]) {
        GZ_LOG_AUTH_DEBUG(
            @"Loopback port-wildcard matched redirect_uri: %@ (allowed: %@)",
            redirectURI, allowedURI);
        return YES;
      }
    }
  }

  GZ_LOG_AUTH_DEBUG(@"No match found for redirect_uri: %@", redirectURI);

  if (error) {
    *error = [NSError
        errorWithDomain:@"OAuth2"
                   code:400
               userInfo:@{NSLocalizedDescriptionKey : @"Invalid redirect_uri"}];
  }
  return NO;
}

@end
