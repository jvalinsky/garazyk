// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler.h"
#import "Security/PDSSecurityCompare.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuthClientAuthPolicy.h"
#import "Auth/Session.h"
#import "Auth/CryptoUtils.h"
#import "Auth/WebAuthnVerifier.h"
#import "Auth/PDSReplayCache.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/OAuthServerMetadata.h"
#import "Database/PDSDatabase.h"
#import "Core/NSDateFormatter+ATProto.h"

#import <CommonCrypto/CommonDigest.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/SSRFValidator.h"

#import "App/ATProtoServiceConfiguration.h"
#import "Services/PDS/PDSAccountService.h"
#import "Security/Space/PDSSpaceScope.h"
#import "Debug/GZLogger.h"

@interface OAuth2Handler ()
@property(nonatomic, strong) PDSDatabase *database;
@property(nonatomic, copy) NSString *serverOrigin;

- (void)handleAuthorizeRequest:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handleAuthorizeConfirm:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handleAuthorizeSignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
- (void)handlePasskeyChallenge:(HttpRequest *)request
                      response:(HttpResponse *)response;
- (void)handlePasskeySignIn:(HttpRequest *)request
                     response:(HttpResponse *)response;
- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response;
- (void)handleRevokeRequest:(HttpRequest *)request
                   response:(HttpResponse *)response;
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request
                                 response:(HttpResponse *)response;
- (void)handleProtectedResourceMetadata:(HttpRequest *)request
                               response:(HttpResponse *)response;
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePARRequest:(HttpRequest *)request
                response:(HttpResponse *)response;
- (NSDictionary *)parseJSONBody:(NSData *)data;
- (NSString *)createPendingConsentSessionForDid:(NSString *)did
                                         handle:(NSString *)handle;
- (void)cleanupExpiredPasskeyChallengesLocked;
- (NSDictionary *)consumePasskeyChallengeForSessionId:(NSString *)sessionId;
- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
                 outThumbprint:(NSString **)outThumbprint;
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata
                                   error:(NSError **)error;
- (BOOL)isLoopbackURL:(NSString *)urlString;
- (NSDictionary *)consumePARRequestForURI:(NSString *)requestURI
                                 clientID:(NSString *)clientID
                                    error:(NSError **)error;
- (NSDate *)dateFromISO8601String:(NSString *)dateString;
- (void)cleanupExpiredPendingConsentsLocked;
- (void)enforcePendingConsentCapacityLocked;
- (BOOL)requestShouldTrustForwardedHeaders:(HttpRequest *)request;
- (NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request;
- (NSString *)requestOriginForRequest:(HttpRequest *)request;
- (void)attachDPoPNonceToResponseIfMissing:(HttpResponse *)response;
- (NSDictionary *)parseClientMetadataFromInput:(id)clientMetadataInput;
- (NSString *)assetsPath;
- (NSString *)escapeHtml:(NSString *)input;
- (NSDictionary *)sanitizeClientMetadataIfNeeded:(NSDictionary *)validatedClient
                                        clientID:(NSString *)clientID;
- (void)serveAuthorizePage:(HttpResponse *)response
                    params:(NSDictionary *)params
                    client:(NSDictionary *)client;
- (void)fetchClientMetadataFromURL:(NSString *)url
                        completion:(void (^)(NSDictionary *_Nullable metadata,
                                             NSError *_Nullable error))completion;
- (BOOL)validateJWTAssertion:(NSString *)assertion
                   withClient:(NSDictionary *)client
                        error:(NSError **)error;
- (NSDictionary *)getClientPublicKeys:(NSDictionary *)client
                                 error:(NSError **)error;
- (nullable NSDictionary *)validatedClientForClientID:(NSString *)clientID
                                                 error:(NSError **)error;
- (BOOL)isClientValidationTimeoutError:(NSError *)error;
- (void)setOAuthErrorResponse:(HttpResponse *)response
                       status:(NSInteger)status
                        error:(NSString *)errorCode
             errorDescription:(NSString *)errorDescription;
@end

static NSMutableDictionary *sPendingConsents = nil;
static NSMutableDictionary *sPasskeyChallenges = nil;
static dispatch_queue_t sPasskeyChallengeQueue = nil;
static dispatch_queue_t sAuthGlobalsQueue = nil;
static dispatch_queue_t sClientMetadataQueue = nil;
static const NSTimeInterval kPendingConsentTTLSeconds = 300.0;
static const NSTimeInterval kPasskeyChallengeTTLSeconds = 300.0;
static const NSUInteger kMaxPendingConsents = 1024;
static const NSTimeInterval kClientValidationTimeoutSeconds = 10.0;
static NSInteger const kClientValidationTimeoutCode = 504;
static NSCache *sClientMetadataCache = nil;
static dispatch_once_t sClientCacheOnceToken;
static dispatch_once_t sPasskeyChallengeOnceToken;
static dispatch_once_t sAuthGlobalsQueueOnceToken;

static BOOL OAuthHandlerScopeIsValid(NSString *scope) {
  BOOL containsAtproto = NO;
  for (NSString *item in [scope componentsSeparatedByCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
    if (item.length == 0) continue;
    if ([item isEqualToString:@"atproto"]) {
      containsAtproto = YES;
    } else if ([item hasPrefix:@"space:"] && ![PDSSpaceScope scopeWithString:item error:nil]) {
      return NO;
    }
  }
  return containsAtproto;
}

@interface OAuth2Handler ()
- (void)setCorsHeaders:(HttpResponse *)response
           forRequest:(HttpRequest *)request;
@end

@implementation OAuth2Handler {
  JWTMinter *_minter;
}

#pragma mark - Init / Lifecycle
- (instancetype)init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void)setMinter:(JWTMinter *)minter {
  _minter = minter;
  self.oauthServer.jwtMinter = minter;
}

- (JWTMinter *)minter {
  return _minter;
}

- (instancetype)initWithDatabase:(PDSDatabase *)database {
  self = [super init];
  if (self) {
    _database = database;
    if (!sPendingConsents)
      sPendingConsents = [NSMutableDictionary dictionary];
    dispatch_once(&sPasskeyChallengeOnceToken, ^{
      sPasskeyChallenges = [NSMutableDictionary dictionary];
      sPasskeyChallengeQueue = dispatch_queue_create(
          "com.atproto.oauth2.passkey.challenges", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_once(&sAuthGlobalsQueueOnceToken, ^{
      sAuthGlobalsQueue = dispatch_queue_create(
          "com.atproto.oauth2.globals", DISPATCH_QUEUE_SERIAL);
    });
    static dispatch_once_t sClientMetadataQueueOnceToken;
    dispatch_once(&sClientMetadataQueueOnceToken, ^{
      sClientMetadataQueue = dispatch_queue_create(
          "com.atproto.oauth2.client.metadata", DISPATCH_QUEUE_SERIAL);
    });
    self.oauthServer = [[OAuth2Server alloc] initWithDatabase:database];
    self.oauthServer.jwtMinter = self.minter;

    // Keep env override behavior for tests/runtime while canonicalizing issuer
    // shape.
    ATProtoServiceConfiguration *configuration = [ATProtoServiceConfiguration sharedConfiguration];
    NSString *envIssuer =
        [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"];
    NSString *issuer = nil;
    if (envIssuer.length > 0) {
      ATProtoServiceConfiguration *envConfiguration = [[ATProtoServiceConfiguration alloc] init];
      envConfiguration.issuer = envIssuer;
      issuer = [envConfiguration canonicalIssuerWithPortHint:0];
    } else {
      issuer = [configuration canonicalIssuerWithPortHint:0];
    }
    self.oauthServer.issuer = issuer;
    self.serverOrigin = issuer;

    self.oauthServer.authorizationEndpoint =
        [NSString stringWithFormat:@"%@/oauth/authorize", issuer];
    self.oauthServer.tokenEndpoint =
        [NSString stringWithFormat:@"%@/oauth/token", issuer];
    self.oauthServer.jwksURI =
        [NSString stringWithFormat:@"%@/oauth/jwks", issuer];
  }
  return self;
}

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
        completion(nil, [NSError errorWithDomain:@"OAuth2"
                                            code:400
                                        userInfo:@{
                                          NSLocalizedDescriptionKey :
                                              @"client_id does not match "
                                              @"client_metadata"
                                        }]);
        return;
      }
      GZ_LOG_AUTH_INFO(
          @"Client validated successfully via client_metadata: %@", clientID);
      completion([self sanitizeClientMetadataIfNeeded:validatedClient clientID:clientID], nil);
      return;
    } else {
      // Metadata validation failed
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

#pragma mark - CORS
- (void)setCorsHeaders:(HttpResponse *)response forRequest:(HttpRequest *)request {
  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  NSArray<NSString *> *allowedOrigins =
      [config arrayForKey:@"cors.allowed_origins"];
  if (!allowedOrigins) {
    allowedOrigins = @[ @"*" ];
  }

  NSString *origin = [request headerForKey: @"Origin"];
  BOOL isMetadataPath = [request.path hasPrefix: @"/.well-known/"];

  if (origin && ([allowedOrigins containsObject: @"*"] || [origin hasPrefix: @"http://127.0.0.1"] || [origin hasPrefix: @"http://localhost"])) {
    [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  } else if (isMetadataPath) {
    // Public metadata fallback
    [response setHeader: @"*" forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  } else if (origin && [allowedOrigins containsObject:origin]) {
    [response setHeader:origin forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Credentials"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  } else if (!origin && [allowedOrigins containsObject: @"*"]) {
    [response setHeader: @"*" forKey: @"Access-Control-Allow-Origin"];
    [response setHeader: @"true" forKey: @"Access-Control-Allow-Private-Network"];
  }

  NSArray *methodsArr = [config arrayForKey:@"cors.allowed_methods"];
  NSString *allowedMethods = methodsArr ? [methodsArr componentsJoinedByString:@", "] : @"GET, POST, PUT, DELETE, OPTIONS, HEAD";
  NSArray *headersArr = [config arrayForKey:@"cors.allowed_headers"];
  NSString *allowedHeaders = headersArr ? [headersArr componentsJoinedByString:@", "] : @"DPoP, Authorization, Content-Type, *";
  NSInteger maxAge = [config integerForKey:@"cors.max_age"] ?: 86400;

  [response setHeader:allowedMethods forKey:@"Access-Control-Allow-Methods"];
  [response setHeader:allowedHeaders forKey:@"Access-Control-Allow-Headers"];
  [response setHeader:[NSString stringWithFormat:@"%ld", (long)maxAge]
               forKey:@"Access-Control-Max-Age"];
  [response setHeader:@"DPoP-Nonce, WWW-Authenticate"
               forKey:@"Access-Control-Expose-Headers"];
  [response setHeader:@"Origin" forKey:@"Vary"];
}

#pragma mark - Route Registration
- (void)registerRoutesWithServer:(HttpServer *)httpServer {
  // Serve shared design system CSS files (tokens, reset, components, etc.)
  [httpServer addHandlerForPath:@"/css/"
                        handler:^(HttpRequest *request, HttpResponse *response) {
                          [self handleCSSRequest:request response:response];
                        }];

  [httpServer addRoute:@"GET"
                  path:@"/oauth/authorize"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleAuthorizeRequest:request response:response];
               }];

  [httpServer addRoute:@"POST"
                  path:@"/oauth/authorize/confirm"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleAuthorizeConfirm:request response:response];
               }];

  [httpServer addRoute:@"POST"
                  path:@"/oauth/authorize/sign-in"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handleAuthorizeSignIn:request response:response];
               }];

  [httpServer addRoute:@"POST"
                  path:@"/oauth/authorize/passkey/challenge"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handlePasskeyChallenge:request response:response];
               }];

  [httpServer addRoute:@"POST"
                  path:@"/oauth/authorize/passkey"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self handlePasskeySignIn:request response:response];
               }];

  [httpServer addRoute:@"POST"
                  path:@"/oauth/token"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self setCorsHeaders:response forRequest:request];
                 [self handleTokenRequest:request response:response];
               }];

  [httpServer addRoute:@"POST"
                  path:@"/oauth/revoke"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self setCorsHeaders:response forRequest:request];
                 [self handleRevokeRequest:request response:response];
               }];

  // Phase 1: Add /oauth/introspect endpoint for token introspection (RFC 7662)
  [httpServer addRoute:@"POST"
                  path:@"/oauth/introspect"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self setCorsHeaders:response forRequest:request];
                 [self handleIntrospectRequest:request response:response];
               }];

  [httpServer
      addRoute:@"GET"
          path:@"/.well-known/oauth-authorization-server"
       handler:^(HttpRequest *request, HttpResponse *response) {
         [self setCorsHeaders:response forRequest:request];
         [self handleAuthorizationServerMetadata:request response:response];
       }];

  [httpServer
      addRoute:@"GET"
          path:@"/.well-known/oauth-protected-resource"
       handler:^(HttpRequest *request, HttpResponse *response) {
         [self setCorsHeaders:response forRequest:request];
         [self handleProtectedResourceMetadata:request response:response];
       }];

  // Phase 4: Add /oauth/jwks endpoint for publishing public keys
  [httpServer addRoute:@"GET"
                  path:@"/oauth/jwks"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self setCorsHeaders:response forRequest:request];
                 [self handleJWKS:request response:response];
               }];

  // Phase 4: Add /oauth/par endpoint for Pushed Authorization Requests
  [httpServer addRoute:@"POST"
                  path:@"/oauth/par"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self setCorsHeaders:response forRequest:request];
                 [self handlePARRequest:request response:response];
               }];

  // Phase 5: Add /oauth/introspect endpoint for token introspection (RFC 7662)
  [httpServer addRoute:@"POST"
                  path:@"/oauth/introspect"
               handler:^(HttpRequest *request, HttpResponse *response) {
                 [self setCorsHeaders:response forRequest:request];
                 [self handleIntrospectRequest:request response:response];
               }];

  // CORS preflight handlers for ATProto OAuth client compatibility
  void (^corsPreflightHandler)(HttpRequest *, HttpResponse *) =
      ^(HttpRequest *req, HttpResponse *resp) {
        [self setCorsHeaders:resp forRequest:req];
        resp.statusCode = 204;
        resp.statusMessage = @"No Content";
      };
  [httpServer addRoute:@"OPTIONS"
                  path:@"/oauth/authorize"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/oauth/token"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/oauth/par"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/oauth/revoke"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/oauth/introspect"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/.well-known/oauth-authorization-server"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/.well-known/oauth-protected-resource"
               handler:corsPreflightHandler];
  [httpServer addRoute:@"OPTIONS"
                  path:@"/oauth/jwks"
               handler:corsPreflightHandler];
}

#pragma mark - Metadata Endpoints
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request
                                 response:(HttpResponse *)response {
  GZ_LOG_AUTH_DEBUG(@"authorization-server-metadata request: path=%@", request.path);
  NSString *issuer = [self requestOriginForRequest:request];
  if (!issuer.length) {
    issuer = self.oauthServer.issuer;
  }
  if (!issuer) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" :
          @"Server configuration error: issuer not configured"
    }];
    return;
  }

  OAuthServerMetadata *metadata =
      [[OAuthServerMetadata alloc] initWithBaseURL:issuer];
  if (!metadata) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" :
          @"Server configuration error: failed to generate metadata"
    }];
    return;
  }

  [response setJsonBody:metadata.metadata];
  response.statusCode = 200;
}

- (void)handleProtectedResourceMetadata:(HttpRequest *)request
                               response:(HttpResponse *)response {
  GZ_LOG_AUTH_DEBUG(@"protected-resource-metadata request: path=%@", request.path);
  NSString *resource = [self requestOriginForRequest:request];
  if (!resource.length) {
    resource = self.oauthServer.issuer;
  }
  if (!resource) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" :
          @"Server configuration error: issuer not configured"
    }];
    return;
  }

  // RFC 8707: resource identifier must not have a trailing slash
  if ([resource hasSuffix:@"/"]) {
    resource = [resource substringToIndex:resource.length - 1];
  }

  NSDictionary *resourceMetadata = @{
    @"resource" : resource,
    @"authorization_servers" : @[ resource ],
    @"scopes_supported" :
        @[ @"atproto", @"transition:generic", @"transition:chat.bsky",
           @"transition:email" ],
    @"bearer_methods_supported" : @[ @"header" ],
    @"resource_documentation" : @"https://atproto.com/specs/oauth"
  };

  [response setJsonBody:resourceMetadata];
  response.statusCode = 200;
}

#pragma mark - Authorization Endpoint
- (void)handleAuthorizeRequest:(HttpRequest *)request
                      response:(HttpResponse *)response {
  GZ_LOG_AUTH_INFO(@"Starting authorize request for path: %@", request.path);
  // Use request.queryParams if available, otherwise parse manually
  NSMutableDictionary *params =
      [request.queryParams mutableCopy] ?: [NSMutableDictionary dictionary];

  NSString *requestURI = params[@"request_uri"];
  if (requestURI.length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" :
          @"request_uri is required; direct authorization requests are not "
          @"allowed"
    }];
    return;
  }

  if (requestURI.length > 0) {
    NSSet<NSString *> *allowedDirectParams =
        [NSSet setWithArray:@[ @"request_uri", @"client_id" ]];
    for (NSString *key in params.allKeys) {
      if (![allowedDirectParams containsObject:key]) {
        response.statusCode = 400;
        [response setJsonBody:@{
          @"error" : @"invalid_request",
          @"error_description" : @"request_uri cannot be combined with direct "
                                 @"authorization parameters"
        }];
        return;
      }
    }

    NSError *parError = nil;
    NSDictionary *parParams = [self consumePARRequestForURI:requestURI
                                                   clientID:params[@"client_id"]
                                                      error:&parError];
    if (!parParams) {
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"invalid_request_uri",
        @"error_description" : parError.localizedDescription
            ?: @"Invalid request_uri"
      }];
      return;
    }
    params = [parParams mutableCopy];
  }

  // Extract and parse client_metadata parameter if provided
  NSDictionary *clientMetadata =
      [self parseClientMetadataFromInput:params[@"client_metadata"]];

  // Store clientMetadata in handler for use by validateClient
  self.clientMetadata = clientMetadata;

  // Validate client from database
  NSString *clientID = params[@"client_id"];
  if (!clientID) {
    GZ_LOG_AUTH_WARN(@"Missing client_id in authorize request");
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing client_id"
    }];
    return;
  }

  NSError *clientError = nil;
  NSDictionary *client = [self validatedClientForClientID:clientID
                                                     error:&clientError];
  if (!client) {
    GZ_LOG_AUTH_WARN(@"Invalid client_id: %@, error: %@", clientID,
                      clientError.localizedDescription);
    if ([self isClientValidationTimeoutError:clientError]) {
      [self setOAuthErrorResponse:response
                           status:503
                            error:@"server_error"
                 errorDescription:@"Timed out while validating client"];
    } else {
      [self setOAuthErrorResponse:response
                           status:400
                            error:@"unauthorized_client"
                 errorDescription:clientError.localizedDescription
                                      ?: @"Invalid client"];
    }
    return;
  }

  GZ_LOG_AUTH_INFO(@"Found client: %@", clientID);

  // Validate redirect URI against client's registered URIs
  NSString *redirectURI = params[@"redirect_uri"];
  NSError *redirectError = nil;
  if (![self validateRedirectURI:redirectURI
                       forClient:client
                           error:&redirectError]) {
    GZ_LOG_AUTH_WARN(@"Invalid redirect_uri: %@ for client %@, error: %@",
                      redirectURI, clientID,
                      redirectError.localizedDescription);
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : redirectError.localizedDescription
          ?: @"Invalid redirect_uri"
    }];
    return;
  }

  // Validate state parameter (CSRF protection)
  NSString *state = params[@"state"];
  if (!state ||
      [state stringByTrimmingCharactersInSet:[NSCharacterSet
                                                 whitespaceCharacterSet]]
              .length == 0) {
    GZ_LOG_AUTH_WARN(@"Missing state parameter for client: %@", clientID);
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"state parameter required for CSRF protection"
    }];
    return;
  }

  OAuth2AuthorizationRequest *authRequest =
      [[OAuth2AuthorizationRequest alloc] init];
  authRequest.clientID = clientID;
  authRequest.redirectURI = params[@"redirect_uri"];
  authRequest.responseType = params[@"response_type"];
  authRequest.scope = params[@"scope"];
  authRequest.state = params[@"state"];
  authRequest.codeChallenge = params[@"code_challenge"];
  authRequest.codeChallengeMethod = params[@"code_challenge_method"];
  authRequest.nonce = params[@"nonce"];
  authRequest.loginHint = params[@"login_hint"];
  authRequest.dpopJWK = params[@"dpop_jkt"];
  authRequest.responseMode = params[@"response_mode"];
  authRequest.clientMetadata = clientMetadata;

  // RFC 7636: Public clients must use PKCE
  // A client is considered public if it has no secret
  BOOL isPublicClient = (client[@"client_secret"] == nil);
  if (isPublicClient &&
      (!authRequest.codeChallenge || authRequest.codeChallenge.length == 0)) {
    GZ_LOG_AUTH_WARN(@"Public client missing code_challenge: %@", clientID);
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"code_challenge required for public clients"
    }];
    return;
  }

  GZ_LOG_AUTH_INFO(@"Processing authorization for client: %@, hint: %@",
                    clientID, authRequest.loginHint);

  // Instead of auto-authorizing, serve the consent screen
  [self serveAuthorizePage:response params:params client:client];
}

- (void)serveAuthorizePage:(HttpResponse *)response
                    params:(NSDictionary *)params
                    client:(NSDictionary *)client {
  NSString *assetsPath = [self assetsPath];
  NSString *filePath =
      [assetsPath stringByAppendingPathComponent:@"authorize.html"];
  GZ_LOG_AUTH_INFO(@"Serving authorize page from: %@", filePath);

  NSError *error = nil;
  NSString *html = [NSString stringWithContentsOfFile:filePath
                                             encoding:NSUTF8StringEncoding
                                                error:&error];
  if (!html || error) {
    GZ_LOG_AUTH_ERROR(@"Failed to load authorize.html at %@: %@", filePath,
                       error);
    response.statusCode = 500;
    [response
        setBodyString:@"Internal Server Error: Missing authorization assets."];
    return;
  }

  GZ_LOG_AUTH_DEBUG(@"Loaded html, size: %lu", (unsigned long)html.length);

  // Generate CSRF token
  NSString *csrfToken = [[NSUUID UUID] UUIDString];
  html =
      [html stringByReplacingOccurrencesOfString:@"{{csrf_token}}"
                                      withString:[self escapeHtml:csrfToken]];

  // Simple template replacement with HTML escaping
  NSString *clientId = [self escapeHtml:params[@"client_id"] ?: @"Unknown App"];
  NSString *clientName = [self escapeHtml:client[@"client_name"] ?: params[@"client_id"] ?: @"Unknown App"];
  NSString *state = [self escapeHtml:params[@"state"] ?: @""];
  NSString *scope = [self escapeHtml:params[@"scope"] ?: @"atproto"];
  NSString *redirectUri = [self escapeHtml:params[@"redirect_uri"] ?: @""];
  NSString *responseType =
      [self escapeHtml:params[@"response_type"] ?: @"code"];
  NSString *codeChallenge = [self escapeHtml:params[@"code_challenge"] ?: @""];
  NSString *codeChallengeMethod =
      [self escapeHtml:params[@"code_challenge_method"] ?: @"S256"];
  NSString *nonce = [self escapeHtml:params[@"nonce"] ?: @""];

  NSString *loginHint = [self escapeHtml:params[@"login_hint"] ?: @""];
  NSString *responseMode = [self escapeHtml:params[@"response_mode"] ?: @"query"];

  html = [html stringByReplacingOccurrencesOfString:@"{{client_id}}"
                                         withString:clientId];
  html = [html stringByReplacingOccurrencesOfString:@"{{client_name}}"
                                         withString:clientName];
  html =
      [html stringByReplacingOccurrencesOfString:@"{{state}}" withString:state];
  html =
      [html stringByReplacingOccurrencesOfString:@"{{scope}}" withString:scope];
  html = [html stringByReplacingOccurrencesOfString:@"{{redirect_uri}}"
                                         withString:redirectUri];
  html = [html stringByReplacingOccurrencesOfString:@"{{response_type}}"
                                         withString:responseType];
  html = [html stringByReplacingOccurrencesOfString:@"{{code_challenge}}"
                                         withString:codeChallenge];
  html = [html stringByReplacingOccurrencesOfString:@"{{code_challenge_method}}"
                                         withString:codeChallengeMethod];
  html =
      [html stringByReplacingOccurrencesOfString:@"{{nonce}}" withString:nonce];
  html = [html stringByReplacingOccurrencesOfString:@"{{login_hint}}"
                                         withString:loginHint];
  html = [html stringByReplacingOccurrencesOfString:@"{{response_mode}}"
                                         withString:responseMode];

  [response setHeader:[NSString stringWithFormat:@"csrf_token=%@; Path=/oauth; "
                                                 @"HttpOnly; SameSite=Strict",
                                                 csrfToken]
               forKey:@"Set-Cookie"];
  response.statusCode = 200;
  response.contentType = @"text/html; charset=utf-8";
  [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)handleAuthorizeConfirm:(HttpRequest *)request
                      response:(HttpResponse *)response {
  NSString *body = [[NSString alloc] initWithData:request.body
                                         encoding:NSUTF8StringEncoding];
  NSDictionary *params = [self parseFormUrlEncodedString:body];

  NSString *decision = params[@"decision"];
  NSString *clientID = params[@"client_id"];
  NSString *state = params[@"state"];
  NSString *scope = params[@"scope"];

  if ([decision isEqualToString:@"deny"]) {
    NSString *sessionTokenForDeny = params[@"session_token"];
    if (sessionTokenForDeny.length > 0) {
      dispatch_sync(sAuthGlobalsQueue, ^{
        [sPendingConsents removeObjectForKey:sessionTokenForDeny];
      });
    }
    NSString *redirectUri = params[@"redirect_uri"];
    if (redirectUri.length > 0) {
      NSError *clientError = nil;
      NSDictionary *client = [self validatedClientForClientID:clientID
                                                         error:&clientError];
      if (!client && [self isClientValidationTimeoutError:clientError]) {
        [self setOAuthErrorResponse:response
                             status:503
                              error:@"server_error"
                   errorDescription:@"Timed out while validating client"];
        return;
      }
      
      NSError *redirectError = nil;
      if (!client || ![self validateRedirectURI:redirectUri
                                      forClient:client
                                          error:&redirectError]) {
        response.statusCode = 400;
        [response setJsonBody:@{
                    @"error": @"invalid_request",
                    @"error_description": redirectError.localizedDescription ?: clientError.localizedDescription ?: @"Invalid redirect_uri"
                }];
        return;
      }

      NSURLComponents *components =
          [NSURLComponents componentsWithString:redirectUri];
      NSMutableArray *queryItems =
          [components.queryItems mutableCopy] ?: [NSMutableArray array];
      [queryItems
          addObject:[NSURLQueryItem queryItemWithName:@"error"
                                                value:@"access_denied"]];
      [queryItems
          addObject:
              [NSURLQueryItem
                  queryItemWithName:@"error_description"
                              value:@"User denied the authorization request"]];
      if (state.length > 0) {
        [queryItems
            addObject:[NSURLQueryItem queryItemWithName:@"state" value:state]];
      }
      if (self.oauthServer.issuer.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"iss"
                                                           value:self.oauthServer.issuer]];
      }
      // Determine response mode for error redirect
      NSString *denyResponseMode = params[@"response_mode"] ?: @"query";
      if ([denyResponseMode isEqualToString:@"fragment"]) {
        NSMutableArray<NSString *> *fragParts = [NSMutableArray array];
        for (NSURLQueryItem *item in queryItems) {
          NSString *encodedName = [item.name stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
          NSString *encodedValue = item.value ? [item.value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] : @"";
          [fragParts addObject:[NSString stringWithFormat:@"%@=%@", encodedName, encodedValue]];
        }
        components.fragment = [fragParts componentsJoinedByString:@"&"];
      } else {
        components.queryItems = queryItems;
      }

      response.statusCode = 302;
      [response setHeader:components.URL.absoluteString forKey:@"Location"];
    } else {
      response.statusCode = 403;
      [response setJsonBody:@{
        @"error" : @"access_denied",
        @"error_description" : @"User denied the authorization request"
      }];
    }
    return;
  }

  // Validate session token
  NSString *sessionToken = params[@"session_token"];

  if (!sessionToken || sessionToken.length == 0) {
    response.statusCode = 403;
    [response setJsonBody:@{
      @"error" : @"access_denied",
      @"error_description" : @"Missing session token"
    }];
    return;
  }

  __block NSDictionary *consentSession = nil;
  dispatch_sync(sAuthGlobalsQueue, ^{
    [self cleanupExpiredPendingConsentsLocked];
    consentSession = sPendingConsents[sessionToken];
  });

  if (!consentSession) {
    response.statusCode = 403;
    [response setJsonBody:@{
      @"error" : @"access_denied",
      @"error_description" : @"Invalid or expired session token"
    }];
    return;
  }

  NSDate *expires = consentSession[@"expires"];
  if ([expires compare:[NSDate date]] == NSOrderedAscending) {
    dispatch_sync(sAuthGlobalsQueue, ^{
      [sPendingConsents removeObjectForKey:sessionToken];
    });
    response.statusCode = 403;
    [response setJsonBody:@{
      @"error" : @"access_denied",
      @"error_description" : @"Session token expired"
    }];
    return;
  }

  // Clean up used token
  dispatch_sync(sAuthGlobalsQueue, ^{
    [sPendingConsents removeObjectForKey:sessionToken];
  });

  NSError *clientError = nil;
  NSDictionary *client = [self validatedClientForClientID:clientID
                                                     error:&clientError];
  if (!client) {
    if ([self isClientValidationTimeoutError:clientError]) {
      [self setOAuthErrorResponse:response
                           status:503
                            error:@"server_error"
                 errorDescription:@"Timed out while validating client"];
    } else {
      [self setOAuthErrorResponse:response
                           status:400
                            error:@"invalid_client"
                 errorDescription:clientError.localizedDescription ?: @"Invalid client"];
    }
    return;
  }

  NSString *redirectURI = params[@"redirect_uri"];
  NSError *redirectError = nil;
  if (![self validateRedirectURI:redirectURI forClient:client error:&redirectError]) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : redirectError.localizedDescription ?: @"Invalid redirect_uri"
    }];
    return;
  }

  // Proceed with authorization
  OAuth2AuthorizationRequest *authRequest =
      [[OAuth2AuthorizationRequest alloc] init];
  authRequest.clientID = clientID;
  authRequest.state = state;
  authRequest.scope = scope;
  authRequest.redirectURI = params[@"redirect_uri"];
  authRequest.responseType = params[@"response_type"];
  authRequest.codeChallenge = params[@"code_challenge"];
  authRequest.codeChallengeMethod = params[@"code_challenge_method"];
  authRequest.nonce = params[@"nonce"];
  authRequest.responseMode = params[@"response_mode"];
  // Pass the authenticated user's handle so the auth code gets a login_hint_did
  authRequest.loginHint = consentSession[@"handle"];

  GZ_LOG_AUTH_INFO(@"Authorizing request for client: %@, redirect_uri: %@",
                    clientID, authRequest.redirectURI);

  [self.oauthServer
      handleAuthorizationRequest:authRequest
                      completion:^(NSURL *_Nullable authorizationURL,
                                   NSString *_Nullable authorizationCode,
                                   NSError *_Nullable error) {
                        if (error) {
                          response.statusCode = 400;
                          [response setJsonBody:@{
                            @"error" : @"invalid_request",
                            @"error_description" : error.localizedDescription
                          }];
                          return;
                        }

                        if (authorizationURL) {
                          response.statusCode = 302;
                          [response setHeader:authorizationURL.absoluteString
                                       forKey:@"Location"];
                        } else {
                          response.statusCode = 500;
                          [response setBodyString:@"Server Error"];
                        }
                      }];
}

#pragma mark - Passkey Auth
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

#pragma mark - Authorization Sign-In
- (void)handleAuthorizeSignIn:(HttpRequest *)request
                     response:(HttpResponse *)response {
  NSString *body = [[NSString alloc] initWithData:request.body
                                         encoding:NSUTF8StringEncoding];
  NSDictionary *params = [self parseFormUrlEncodedString:body];

  NSString *handle = params[@"handle"];
  NSString *password = params[@"password"];

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

  if (!handle.length || !password.length) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Handle and password are required"
    }];
    return;
  }

  if (!self.accountService) {
    GZ_LOG_AUTH_ERROR(@"Sign-in attempted but no accountService configured");
    response.statusCode = 500;
    [response setJsonBody:@{
      @"ok" : @NO,
      @"error" : @"Authentication service unavailable"
    }];
    return;
  }

  NSError *authError = nil;
  NSDictionary *result = [self.accountService loginWithIdentifier:handle
                                                         password:password
                                                            error:&authError];

  if (result && result[@"did"]) {
    GZ_LOG_AUTH_INFO(@"Sign-in successful for handle: %@", handle);
    NSString *sessionToken = [self createPendingConsentSessionForDid:result[@"did"]
                                                              handle:handle];
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
      @"did" : result[@"did"],
      @"session_token" : sessionToken
    }];
  } else {
    GZ_LOG_AUTH_INFO(@"Sign-in failed for handle: %@, error: %@", handle,
                      authError.localizedDescription ?: @"unknown");
    response.statusCode = 401;
    [response
        setJsonBody:@{@"ok" : @NO, @"error" : @"Invalid handle or password"}];
  }
}

#pragma mark - JSON Parsing
- (NSDictionary *)parseJSONBody:(NSData *)data {
  if (!data || data.length == 0) {
    return nil;
  }

  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (!json || ![json isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  return (NSDictionary *)json;
}

#pragma mark - Consent & Passkey Session Store
- (NSString *)createPendingConsentSessionForDid:(NSString *)did
                                         handle:(NSString *)handle {
  if (did.length == 0) {
    return nil;
  }

  NSString *sessionToken = [[NSUUID UUID] UUIDString];
  NSString *sessionHandle = handle.length > 0 ? handle : did;
  dispatch_sync(sAuthGlobalsQueue, ^{
    [self cleanupExpiredPendingConsentsLocked];
    [self enforcePendingConsentCapacityLocked];
    sPendingConsents[sessionToken] = @{
      @"did" : did,
      @"handle" : sessionHandle,
      @"created" : [NSDate date],
      @"expires" :
          [NSDate dateWithTimeIntervalSinceNow:kPendingConsentTTLSeconds]
    };
  });

  return sessionToken;
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

#pragma mark - Form Parsing
- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input {
  NSMutableDictionary *params = [NSMutableDictionary dictionary];
  // NSURLComponents parses percent-encoded query strings automatically
  NSURLComponents *components = [[NSURLComponents alloc] init];
  components.percentEncodedQuery = input;

  for (NSURLQueryItem *item in components.queryItems) {
    if (item.name) {
      params[item.name] = item.value ?: @"";
    }
  }
  return [params copy];
}

#pragma mark - Token Endpoint
- (void)handleTokenRequest:(HttpRequest *)request
                  response:(HttpResponse *)response {
  [response setHeader:@"no-store" forKey:@"Cache-Control"];
  [response setHeader:@"no-cache" forKey:@"Pragma"];

  NSString *body = [[NSString alloc] initWithData:request.body
                                         encoding:NSUTF8StringEncoding];
  if (!body) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing request body"
    }];
    return;
  }

  NSDictionary *params = nil;
  if ([body hasPrefix:@"{"]) {
    NSError *jsonError = nil;
    params = [NSJSONSerialization JSONObjectWithData:request.body
                                             options:0
                                               error:&jsonError];
  }

  if (!params) {
    params = [self parseFormUrlEncodedString:body];
  }

  NSString *grantType = params[@"grant_type"];

  // Validate client from database
  NSString *clientID = params[@"client_id"];
  GZ_LOG_AUTH_INFO(@"Token request received (grant_type=%@, client_id=%@)",
                    grantType ?: @"", clientID ?: @"");

  NSError *clientError = nil;
  NSDictionary *client = [self validatedClientForClientID:clientID
                                                     error:&clientError];
  if (!client) {
    if ([self isClientValidationTimeoutError:clientError]) {
      [self setOAuthErrorResponse:response
                           status:503
                            error:@"server_error"
                 errorDescription:@"Timed out while validating client"];
    } else {
      [self setOAuthErrorResponse:response
                           status:401
                            error:@"invalid_client"
                 errorDescription:clientError.localizedDescription ?: @"Invalid client"];
    }
    return;
  }
  GZ_LOG_AUTH_DEBUG(@"Token request client validation passed (client_id=%@)",
                     clientID ?: @"");

  // Validate client authentication
  // In ATProto, client authentication can use DPoP binding, client_secret,
  // or JWT assertion (private_key_jwt)
  NSString *clientSecret = params[@"client_secret"];
  NSString *clientAssertion = params[@"client_assertion"];
  NSString *clientAssertionType = params[@"client_assertion_type"];
  NSString *dpopJWK = params[@"dpop_jwk"];
  NSString *dpopProof = [request headerForKey:@"dpop"];
  BOOL hasDpopProof = (dpopProof.length > 0);
  NSString *expectedSecret = client[@"client_secret"];
  NSString *tokenEndpointAuthMethod = client[@"token_endpoint_auth_method"];

  // JWT assertion authentication (private_key_jwt)
  BOOL clientUsesPrivateKeyJWT =
      [tokenEndpointAuthMethod isEqualToString:@"private_key_jwt"];

  if (clientAssertion.length > 0) {
    // JWT assertion provided - validate it
    if (![clientAssertionType
            isEqualToString:
                @"urn:ietf:params:oauth:client-assertion-type:jwt-bearer"]) {
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" :
            @"client_assertion_type must be "
            @"urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
      }];
      return;
    }

    NSError *assertionError = nil;
    if (![self validateJWTAssertion:clientAssertion
                          withClient:client
                               error:&assertionError]) {
      response.statusCode = 401;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" : assertionError.localizedDescription
                                  ?: @"Invalid client assertion"
      }];
      return;
    }
    GZ_LOG_AUTH_DEBUG(
        @"JWT assertion validation passed (client_id=%@)", clientID ?: @"");

  } else if (clientUsesPrivateKeyJWT) {
    // Client is configured for private_key_jwt but no assertion provided
    response.statusCode = 401;
    [response setJsonBody:@{
      @"error" : @"invalid_client",
      @"error_description" :
          @"client_assertion required for private_key_jwt authentication"
    }];
    return;

  } else {
    // Traditional client_secret authentication (constant-time comparison)
    if (clientSecret && expectedSecret &&
        ![OAuthClientAuthPolicy validateClientSecret:clientSecret againstExpected:expectedSecret]) {
      response.statusCode = 401;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" : @"Invalid client credentials"
      }];
      return;
    }

    // Reject if client_secret is required but not provided and no DPoP binding
    if (!clientSecret && !dpopJWK && !hasDpopProof && expectedSecret) {
      response.statusCode = 401;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" : @"Client authentication required"
      }];
      return;
    }
  }

  // Validate redirect URI for authorization_code grant type
  if ([grantType isEqualToString:@"authorization_code"]) {
    NSString *redirectURI = params[@"redirect_uri"];
    // URL-decode the redirect_uri since browsers send it encoded in form data
    if (redirectURI) {
      NSString *decodedRedirectURI =
          [redirectURI stringByRemovingPercentEncoding];
      if (decodedRedirectURI) {
        redirectURI = decodedRedirectURI;
      }
    }
    NSError *redirectError = nil;
    if (![self validateRedirectURI:redirectURI
                         forClient:client
                             error:&redirectError]) {
      GZ_LOG_AUTH_WARN(
          @"Token request redirect_uri validation failed (client_id=%@): %@",
          clientID ?: @"",
          redirectError.localizedDescription ?: @"Invalid redirect_uri");
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"invalid_request",
        @"error_description" : redirectError.localizedDescription
            ?: @"Invalid redirect_uri"
      }];
      return;
    }
  }

  NSString *dpopThumbprint = nil;
  if (![self validateDPoPForRequest:request
                           response:response
                      outThumbprint:&dpopThumbprint]) {
    return;
  }

  OAuth2TokenRequest *tokenRequest = [[OAuth2TokenRequest alloc] init];
  tokenRequest.grantType = params[@"grant_type"];
  tokenRequest.code = params[@"code"];
  tokenRequest.redirectURI = params[@"redirect_uri"];
  tokenRequest.clientID = clientID;
  tokenRequest.codeVerifier = params[@"code_verifier"];
  tokenRequest.refreshToken = params[@"refresh_token"];
  tokenRequest.scope = params[@"scope"];
  tokenRequest.tfaCode = params[@"tfa_code"];
  tokenRequest.dpopProof = dpopProof;
  tokenRequest.dpopKeyThumbprint = dpopThumbprint;

  [self.oauthServer
      handleTokenRequest:tokenRequest
              completion:^(Session *_Nullable session,
                           NSError *_Nullable error) {
                if (error) {
                  response.statusCode = 400;
                  [self attachDPoPNonceToResponseIfMissing:response];
                  NSDictionary *errorResponse = @{
                    @"error" : @"invalid_grant",
                    @"error_description" : error.localizedDescription
                  };

                  // Check for 2FA required
                  if (error.userInfo[@"error"] &&
                      [error.userInfo[@"error"]
                          isEqualToString:@"mfa_required"]) {
                    errorResponse = @{
                      @"error" : @"interaction_required",
                      @"error_description" : error.localizedDescription
                    };
                  }

                  [response setJsonBody:errorResponse];
                  return;
                }

                if (session) {
                  response.statusCode = 200;
                  [self attachDPoPNonceToResponseIfMissing:response];
                  NSMutableDictionary *tokenResp = [@{
                    @"access_token" : session.accessToken,
                    @"token_type" : @"DPoP",
                    @"expires_in" : @3600,
                    @"scope" : session.scope ?: @"atproto"
                  } mutableCopy];
                  if (session.refreshToken)
                    tokenResp[@"refresh_token"] = session.refreshToken;
                  if (session.did)
                    tokenResp[@"sub"] = session.did;
                  [response setJsonBody:tokenResp];
                } else {
                  response.statusCode = 500;
                  [response setJsonBody:@{
                    @"error" : @"server_error",
                    @"error_description" : @"Failed to create session"
                  }];
                }
              }];
}

- (void)handleRevokeRequest:(HttpRequest *)request
                   response:(HttpResponse *)response {
  NSString *body = [[NSString alloc] initWithData:request.body
                                         encoding:NSUTF8StringEncoding];
  if (!body) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing request body"
    }];
    return;
  }

  NSDictionary *params = [self parseFormUrlEncodedString:body];

  // Validate client from database
  NSString *clientID = params[@"client_id"];
  NSString *token = params[@"token"];

  NSError *clientError = nil;
  NSDictionary *client = [self validatedClientForClientID:clientID
                                                     error:&clientError];
  if (!client) {
    if ([self isClientValidationTimeoutError:clientError]) {
      [self setOAuthErrorResponse:response
                           status:503
                            error:@"server_error"
                 errorDescription:@"Timed out while validating client"];
    } else {
      [self setOAuthErrorResponse:response
                           status:401
                            error:@"invalid_client"
                 errorDescription:clientError.localizedDescription ?: @"Invalid client"];
    }
    return;
  }

  if (!token) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing token parameter"
    }];
    return;
  }

  // Find the session for this token (client validation already done above)
  NSString *sessionIdToRemove = nil;
  for (NSString *sessionId in self.oauthServer.activeSessions) {
    Session *session = self.oauthServer.activeSessions[sessionId];
    if ([CryptoUtils constantTimeCompare:session.accessToken to:token] ||
        [CryptoUtils constantTimeCompare:session.refreshToken to:token]) {
      sessionIdToRemove = sessionId;
      break;
    }
  }

  if (sessionIdToRemove) {
    [self.oauthServer.activeSessions removeObjectForKey:sessionIdToRemove];
  } else {
    // Token not found - still return success for security (don't reveal if
    // token exists)
  }

  response.statusCode = 200;
  [response setJsonBody:@{}];
}

- (void)handleIntrospectRequest:(HttpRequest *)request
                       response:(HttpResponse *)response {
  NSString *body = [[NSString alloc] initWithData:request.body
                                         encoding:NSUTF8StringEncoding];
  if (!body) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing request body"
    }];
    return;
  }

  NSDictionary *params = [self parseFormUrlEncodedString:body];

  NSString *clientID = params[@"client_id"];
  NSString *token = params[@"token"];

  if (!token) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing token parameter"
    }];
    return;
  }

  // OAuth Token Introspection (RFC 7662)
  // The token parameter is already validated above

  // Try to parse as JWT access token first
  NSError *jwtError = nil;
  JWT *jwt = [JWT jwtWithToken:token error:&jwtError];

  if (jwt) {
    // Verify JWT signature
    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    if ([verifier verifyJWT:jwt error:&jwtError]) {
      JWTPayload *payload = jwt.payload;

      // Check if token is expired
      NSDate *now = [NSDate date];
      if (payload.exp && [payload.exp compare:now] == NSOrderedAscending) {
        // Token expired
        [response setJsonBody:@{ @"active" : @NO }];
        response.statusCode = 200;
        return;
      }

      // Not yet valid check
      if (payload.nbf && [payload.nbf compare:now] == NSOrderedDescending) {
        [response setJsonBody:@{ @"active" : @NO }];
        response.statusCode = 200;
        return;
      }

      // Build introspection response for valid access token
      NSMutableDictionary *introspection = [NSMutableDictionary dictionary];
      introspection[@"active"] = @YES;
      introspection[@"token_type"] = @"bearer";

      if (payload.iss)
        introspection[@"iss"] = payload.iss;
      if (payload.sub)
        introspection[@"sub"] = payload.sub;
      if (payload.aud)
        introspection[@"aud"] = payload.aud;
      if (clientID)
        introspection[@"client_id"] = clientID;
      if (payload.scope)
        introspection[@"scope"] = payload.scope;
      if (payload.iat)
        introspection[@"iat"] = @((long long)[payload.iat timeIntervalSince1970]);
      if (payload.exp)
        introspection[@"exp"] = @((long long)[payload.exp timeIntervalSince1970]);
      if (payload.nbf)
        introspection[@"nbf"] = @((long long)[payload.nbf timeIntervalSince1970]);
      if (payload.jti)
        introspection[@"jti"] = payload.jti;
      if (payload.did)
        introspection[@"did"] = payload.did;
      if (payload.handle)
        introspection[@"username"] = payload.handle;

      [response setJsonBody:introspection];
      response.statusCode = 200;
      return;
    }
  }

  // Not a valid JWT - check if it's a refresh token in active sessions
  for (NSString *sessionId in self.oauthServer.activeSessions) {
    Session *session = self.oauthServer.activeSessions[sessionId];
    if ([CryptoUtils constantTimeCompare:session.refreshToken to:token]) {
      // Found refresh token in active sessions
      NSMutableDictionary *introspection = [NSMutableDictionary dictionary];
      introspection[@"active"] = @YES;
      introspection[@"token_type"] = @"refresh_token";
      if (clientID)
        introspection[@"client_id"] = clientID;
      if (session.did)
        introspection[@"sub"] = session.did;
      if (session.handle)
        introspection[@"username"] = session.handle;
      if (session.scope)
        introspection[@"scope"] = session.scope;

      [response setJsonBody:introspection];
      response.statusCode = 200;
      return;
    }
  }

  // Also check for access token match in sessions (non-JWT tokens)
  for (NSString *sessionId in self.oauthServer.activeSessions) {
    Session *session = self.oauthServer.activeSessions[sessionId];
    if ([CryptoUtils constantTimeCompare:session.accessToken to:token]) {
      NSMutableDictionary *introspection = [NSMutableDictionary dictionary];
      introspection[@"active"] = @YES;
      introspection[@"token_type"] = @"bearer";
      if (clientID)
        introspection[@"client_id"] = clientID;
      if (session.did)
        introspection[@"sub"] = session.did;
      if (session.handle)
        introspection[@"username"] = session.handle;
      if (session.scope)
        introspection[@"scope"] = session.scope;

      [response setJsonBody:introspection];
      response.statusCode = 200;
      return;
    }
  }

  // Token not found or invalid - return inactive
  // Always return 200 to prevent token enumeration (RFC 7662)
  [response setJsonBody:@{ @"active" : @NO }];
  response.statusCode = 200;
}

#pragma mark - JWKS Endpoint
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response {
  // Access JWKS via the minter
  NSDictionary *jwks = [self.minter toJWKS];
  if (!jwks) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" : @"Failed to export JWKS"
    }];
    return;
  }

  [response setJsonBody:jwks];
  response.statusCode = 200;
  [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
}

#pragma mark - PAR (Pushed Authorization Request)
- (void)handlePARRequest:(HttpRequest *)request
                response:(HttpResponse *)response {
  GZ_LOG_AUTH_INFO(@"Handling PAR request");

  // Parse body parameters
  NSString *body = [[NSString alloc] initWithData:request.body
                                         encoding:NSUTF8StringEncoding];
  GZ_LOG_AUTH_DEBUG(@"PAR request body: %@", body);
  if (!body) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing request body"
    }];
    return;
  }

  NSDictionary *params = nil;
  if ([body hasPrefix:@"{"]) {
    // Try to parse as JSON
    NSError *jsonError = nil;
    params = [NSJSONSerialization JSONObjectWithData:request.body
                                             options:0
                                               error:&jsonError];
    if (jsonError) {
      GZ_LOG_AUTH_ERROR(@"Failed to parse PAR JSON body: %@", jsonError.localizedDescription);
    }
  }

  if (!params) {
    params = [self parseFormUrlEncodedString:body];
  }

  self.clientMetadata = [self parseClientMetadataFromInput:params[@"client_metadata"]];

  // Validate client authentication (either client_secret or DPoP)
  NSString *clientID = params[@"client_id"];
  if (!clientID) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_client",
      @"error_description" : @"Missing client_id"
    }];
    return;
  }

  NSError *clientError = nil;
  NSDictionary *client = [self validatedClientForClientID:clientID
                                                     error:&clientError];
  if (!client) {
    if ([self isClientValidationTimeoutError:clientError]) {
      [self setOAuthErrorResponse:response
                           status:503
                            error:@"server_error"
                 errorDescription:@"Timed out while validating client"];
    } else {
      [self setOAuthErrorResponse:response
                           status:401
                            error:@"invalid_client"
                 errorDescription:clientError.localizedDescription ?: @"Invalid client"];
    }
    return;
  }

  // JWT assertion authentication (private_key_jwt)
  NSString *clientAssertion = params[@"client_assertion"];
  NSString *clientAssertionType = params[@"client_assertion_type"];
  NSString *clientSecret = params[@"client_secret"];
  NSString *expectedSecret = client[@"client_secret"];
  NSString *tokenEndpointAuthMethod = client[@"token_endpoint_auth_method"];
  BOOL clientUsesPrivateKeyJWT =
      [tokenEndpointAuthMethod isEqualToString:@"private_key_jwt"];

  if (clientAssertion.length > 0) {
    // JWT assertion provided - validate it
    if (![clientAssertionType
            isEqualToString:
                @"urn:ietf:params:oauth:client-assertion-type:jwt-bearer"]) {
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" :
            @"client_assertion_type must be "
            @"urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
      }];
      return;
    }

    NSError *assertionError = nil;
    if (![self validateJWTAssertion:clientAssertion
                          withClient:client
                               error:&assertionError]) {
      response.statusCode = 401;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" : assertionError.localizedDescription
                                  ?: @"Invalid client assertion"
      }];
      return;
    }
    GZ_LOG_AUTH_DEBUG(
        @"PAR JWT assertion validation passed (client_id=%@)", clientID ?: @"");

  } else if (clientUsesPrivateKeyJWT) {
    // Client is configured for private_key_jwt but no assertion provided
    response.statusCode = 401;
    [response setJsonBody:@{
      @"error" : @"invalid_client",
      @"error_description" :
          @"client_assertion required for private_key_jwt authentication"
    }];
    return;

  } else {
    // Traditional client_secret authentication (constant-time comparison)
    if (expectedSecret && ![OAuthClientAuthPolicy validateClientSecret:clientSecret againstExpected:expectedSecret]) {
      response.statusCode = 401;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" : @"Invalid client credentials"
      }];
      return;
    }
    if (!clientSecret && expectedSecret.length > 0) {
      response.statusCode = 401;
      [response setJsonBody:@{
        @"error" : @"invalid_client",
        @"error_description" : @"Client authentication required"
      }];
      return;
    }
  }

  if ([params[@"request_uri"] length] > 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"request_uri must not be included in PAR payload"
    }];
    return;
  }

  NSString *responseType = params[@"response_type"];
  if (responseType.length == 0 || ![responseType isEqualToString:@"code"]) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"response_type must be 'code'"
    }];
    return;
  }

  NSString *redirectURI = params[@"redirect_uri"];
  NSError *redirectError = nil;
  if (![self validateRedirectURI:redirectURI
                       forClient:client
                           error:&redirectError]) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : redirectError.localizedDescription
          ?: @"Invalid redirect_uri"
    }];
    return;
  }

  if ([params[@"state"] length] == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"state parameter required for CSRF protection"
    }];
    return;
  }

  // AT Protocol spec: scope must include 'atproto'
  NSString *scope = params[@"scope"];
  if (!OAuthHandlerScopeIsValid(scope)) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_scope",
      @"error_description" :
          @"A valid 'atproto' scope is required for AT Protocol OAuth sessions"
    }];
    return;
  }

  // PKCE is mandatory for all client types per AT Protocol OAuth spec
  if ([params[@"code_challenge"] length] == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"code_challenge is required (PKCE is mandatory)"
    }];
    return;
  }
  if (![params[@"code_challenge_method"] isEqualToString:@"S256"]) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" :
          @"code_challenge_method must be S256 (plain is not allowed)"
    }];
    return;
  }

  // Enforce DPoP for PAR
  NSString *dpopThumbprint = nil;
  if (![self validateDPoPForRequest:request
                           response:response
                      outThumbprint:&dpopThumbprint]) {
    return;
  }

  // Generate request URI
  NSString *requestUUID = [[NSUUID UUID] UUIDString];
  NSString *requestURI = [NSString
      stringWithFormat:@"urn:ietf:params:oauth:request_uri:%@", requestUUID];

  NSMutableDictionary *storedParams = [params mutableCopy];
  [storedParams removeObjectForKey:@"client_secret"];
  if (dpopThumbprint.length > 0) {
    storedParams[@"dpop_jkt"] = dpopThumbprint;
  }

  NSData *paramsData =
      [NSJSONSerialization dataWithJSONObject:storedParams options:0 error:nil];
  if (!paramsData) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" : @"Failed to encode PAR request"
    }];
    return;
  }

  NSTimeInterval expiresIn = 600; // 10 minutes
  NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:expiresIn];
  NSString *expiresAtString = [self iso8601StringFromDate:expiresAt];
  NSString *nowString = [self iso8601StringFromDate:[NSDate date]];

  NSString *createTableSQL =
      @"CREATE TABLE IF NOT EXISTS oauth_par_requests (request_uri TEXT "
      @"PRIMARY KEY, client_id TEXT NOT NULL, params_json TEXT NOT NULL, "
      @"expires_at TEXT NOT NULL, consumed_at TEXT)";
  if (![self.database executeParameterizedUpdate:createTableSQL
                                          params:@[]
                                           error:nil]) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" : @"Failed to initialize PAR storage"
    }];
    return;
  }

  [self.database
      executeParameterizedUpdate:@"DELETE FROM oauth_par_requests WHERE "
                                 @"consumed_at IS NOT NULL OR expires_at < ?"
                          params:@[ nowString ]
                           error:nil];

  NSString *sql =
      @"INSERT INTO oauth_par_requests (request_uri, client_id, params_json, "
      @"expires_at, consumed_at) VALUES (?, ?, ?, ?, NULL)";
  NSError *insertError = nil;
  BOOL inserted = [self.database
      executeParameterizedUpdate:sql
                          params:@[
                            requestURI, clientID,
                            [[NSString alloc] initWithData:paramsData
                                                  encoding:NSUTF8StringEncoding]
                                ?: @"{}",
                            expiresAtString
                          ]
                           error:&insertError];
  if (!inserted) {
    response.statusCode = 500;
    [response setJsonBody:@{
      @"error" : @"server_error",
      @"error_description" :
          [NSString stringWithFormat:@"Failed to persist PAR request: %@",
                                     insertError.localizedDescription]
    }];
    return;
  }

  response.statusCode = 201;
  NSString *nextNonce = [[PDSNonceManager sharedManager] generateNonce];
  if (nextNonce.length > 0) {
    [response setHeader:nextNonce forKey:@"DPoP-Nonce"];
  }
  [response setHeader:@"no-store" forKey:@"Cache-Control"];
  [response setHeader:@"no-cache" forKey:@"Pragma"];
  [response
      setJsonBody:@{@"request_uri" : requestURI, @"expires_in" : @(expiresIn)}];
}

#pragma mark - Client Metadata Parsing
- (NSDictionary *)parseClientMetadataFromInput:(id)clientMetadataInput {
  if ([clientMetadataInput isKindOfClass:[NSDictionary class]]) {
    return (NSDictionary *)clientMetadataInput;
  }

  if ([clientMetadataInput isKindOfClass:[NSString class]]) {
    NSString *clientMetadataString = (NSString *)clientMetadataInput;
    if (clientMetadataString.length == 0) {
      return nil;
    }

    NSData *jsonData =
        [clientMetadataString dataUsingEncoding:NSUTF8StringEncoding];
    if (!jsonData) {
      GZ_LOG_AUTH_WARN(@"Failed to decode client_metadata text as UTF-8");
      return nil;
    }

    NSError *jsonError = nil;
    id parsedJSON = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:0
                                                      error:&jsonError];
    if (jsonError) {
      GZ_LOG_AUTH_WARN(@"Failed to parse client_metadata JSON: %@",
                        jsonError.localizedDescription);
      return nil;
    }
    if (![parsedJSON isKindOfClass:[NSDictionary class]]) {
      GZ_LOG_AUTH_WARN(@"client_metadata is not a JSON object");
      return nil;
    }

    NSDictionary *clientMetadata = (NSDictionary *)parsedJSON;
    GZ_LOG_AUTH_INFO(@"Parsed client_metadata with %lu keys",
                      (unsigned long)clientMetadata.count);
    return clientMetadata;
  }

  return nil;
}

#pragma mark - Date Helpers
- (NSString *)iso8601StringFromDate:(NSDate *)date {
  return [NSDateFormatter atproto_stringFromDate:date];
}

- (NSDate *)dateFromISO8601String:(NSString *)dateString {
  return [NSDateFormatter atproto_dateFromString:dateString];
}

#pragma mark - PAR Request Store
- (NSDictionary *)consumePARRequestForURI:(NSString *)requestURI
                                 clientID:(NSString *)clientID
                                    error:(NSError **)error {
  if (requestURI.length == 0) {
    if (error) {
      *error =
          [NSError errorWithDomain:@"OAuth2"
                              code:400
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"Missing request_uri"
                          }];
    }
    return nil;
  }

  NSArray<NSDictionary *> *rows = [self.database
      executeParameterizedQuery:
          @"SELECT client_id, params_json, expires_at, consumed_at FROM "
          @"oauth_par_requests WHERE request_uri = ? LIMIT 1"
                         params:@[ requestURI ]
                          error:error];
  if (rows.count == 0) {
    if (error && !*error) {
      *error =
          [NSError errorWithDomain:@"OAuth2"
                              code:400
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"Unknown request_uri"
                          }];
    }
    return nil;
  }

  NSDictionary *row = rows.firstObject;
  NSString *storedClientID = row[@"client_id"];
  if (clientID.length > 0 && storedClientID.length > 0 &&
      ![CryptoUtils constantTimeCompare:clientID to:storedClientID]) {
    if (error) {
      *error = [NSError errorWithDomain:@"OAuth2"
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"request_uri client binding mismatch"
                               }];
    }
    return nil;
  }

  NSString *consumedAt = row[@"consumed_at"];
  if (consumedAt.length > 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"request_uri already used"
                 }];
    }
    return nil;
  }

  NSDate *expiresAt = [self dateFromISO8601String:row[@"expires_at"]];
  NSDate *now = [NSDate date];
  if (!expiresAt || [expiresAt compare:now] != NSOrderedDescending) {
    [self.database executeParameterizedUpdate:
                       @"DELETE FROM oauth_par_requests WHERE request_uri = ?"
                                       params:@[ requestURI ]
                                        error:nil];
    if (error) {
      *error =
          [NSError errorWithDomain:@"OAuth2"
                              code:400
                          userInfo:@{
                            NSLocalizedDescriptionKey : @"request_uri expired"
                          }];
    }
    return nil;
  }

  NSString *consumedNow = [self iso8601StringFromDate:now];
  [self.database
      executeParameterizedUpdate:
          @"UPDATE oauth_par_requests SET consumed_at = ? WHERE request_uri = "
          @"? AND consumed_at IS NULL AND expires_at >= ?"
                          params:@[ consumedNow, requestURI, consumedNow ]
                           error:nil];

  NSArray<NSDictionary *> *consumedRows =
      [self.database executeParameterizedQuery:
                         @"SELECT consumed_at, params_json, client_id FROM "
                         @"oauth_par_requests WHERE request_uri = ? LIMIT 1"
                                        params:@[ requestURI ]
                                         error:nil];
  if (consumedRows.count == 0) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"request_uri not available"
                 }];
    }
    return nil;
  }

  NSDictionary *consumedRow = consumedRows.firstObject;
  if (![consumedNow isEqualToString:consumedRow[@"consumed_at"]]) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:400
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"request_uri already consumed"
                 }];
    }
    return nil;
  }

  NSString *paramsJSON = consumedRow[@"params_json"];
  NSData *paramsData = [paramsJSON dataUsingEncoding:NSUTF8StringEncoding];
  if (!paramsData) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"OAuth2"
                     code:500
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Invalid PAR payload encoding"
                 }];
    }
    return nil;
  }

  NSError *jsonError = nil;
  NSDictionary *storedParams =
      [NSJSONSerialization JSONObjectWithData:paramsData
                                      options:0
                                        error:&jsonError];
  if (![storedParams isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = jsonError
                   ?: [NSError errorWithDomain:@"OAuth2"
                                          code:500
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Invalid PAR payload"
                                      }];
    }
    return nil;
  }

  NSMutableDictionary *merged = [storedParams mutableCopy];
  if (storedClientID.length > 0) {
    merged[@"client_id"] = storedClientID;
  }
  return [merged copy];
}

#pragma mark - Consent Session Store
- (void)cleanupExpiredPendingConsentsLocked {
  if (!sPendingConsents || sPendingConsents.count == 0) {
    return;
  }

  NSDate *now = [NSDate date];
  NSMutableArray<NSString *> *expired = [NSMutableArray array];
  [sPendingConsents
      enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSDictionary *session = (NSDictionary *)obj;
        NSString *sessionKey = (NSString *)key;
        NSDate *expires = session[@"expires"];
        if (![expires isKindOfClass:[NSDate class]] ||
            [expires compare:now] != NSOrderedDescending) {
          [expired addObject:sessionKey];
        }
      }];
  [sPendingConsents removeObjectsForKeys:expired];
}

- (void)enforcePendingConsentCapacityLocked {
  if (sPendingConsents.count < kMaxPendingConsents) {
    return;
  }

  NSArray<NSString *> *sortedKeys = [sPendingConsents
      keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *obj1,
                                                           NSDictionary *obj2) {
        NSDate *created1 = obj1[@"created"] ?: obj1[@"expires"] ?: [NSDate distantPast];
        NSDate *created2 = obj2[@"created"] ?: obj2[@"expires"] ?: [NSDate distantPast];
        return [created1 compare:created2];
      }];

  NSUInteger overflow = (sPendingConsents.count - kMaxPendingConsents) + 1;
  for (NSUInteger i = 0; i < overflow && i < sortedKeys.count; i++) {
    [sPendingConsents removeObjectForKey:sortedKeys[i]];
  }
}

- (NSUInteger)pendingConsentCountForTesting {
  __block NSUInteger count = 0;
  dispatch_sync(sAuthGlobalsQueue, ^{
    [self cleanupExpiredPendingConsentsLocked];
    count = sPendingConsents.count;
  });
  return count;
}

- (void)clearPendingConsentsForTesting {
  dispatch_sync(sAuthGlobalsQueue, ^{
    [sPendingConsents removeAllObjects];
  });
}

#pragma mark - Forwarded Header Trust
- (BOOL)requestShouldTrustForwardedHeaders:(HttpRequest *)request {
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *rawTrustProxy = [env[@"PDS_TRUST_PROXY_HEADERS"] lowercaseString];
  BOOL trustProxy = [rawTrustProxy isEqualToString:@"1"] ||
                    [rawTrustProxy isEqualToString:@"true"] ||
                    [rawTrustProxy isEqualToString:@"yes"] ||
                    [rawTrustProxy isEqualToString:@"on"];
  if (!trustProxy) {
    return NO;
  }

  NSString *remote = [[request.remoteAddress ?: @"" lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  if (remote.length == 0) {
    return NO;
  }
  if ([remote hasPrefix:@"127."] || [remote isEqualToString:@"::1"] ||
      [remote isEqualToString:@"localhost"]) {
    return YES;
  }
  if ([remote hasPrefix:@"10."] || [remote hasPrefix:@"192.168."]) {
    return YES;
  }
  if ([remote hasPrefix:@"172."]) {
    NSArray<NSString *> *parts = [remote componentsSeparatedByString:@"."];
    if (parts.count >= 2) {
      NSInteger secondOctet = [parts[1] integerValue];
      if (secondOctet >= 16 && secondOctet <= 31) {
        return YES;
      }
    }
  }
  return NO;
}

#pragma mark - DPoP & Request Origin Helpers
- (NSURL *)expectedDPoPURLForRequest:(HttpRequest *)request {
  NSString *path = request.path ?: @"/";
  NSString *hostHeader = [[request headerForKey:@"host"]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSString *hostLower = [hostHeader lowercaseString];
  BOOL localHostHeader = [hostLower containsString:@"localhost"] ||
                         [hostLower hasPrefix:@"127.0.0.1"] ||
                         [hostLower hasPrefix:@"[::1]"] ||
                         [hostLower isEqualToString:@"::1"];
  BOOL trustedForwarded = [self requestShouldTrustForwardedHeaders:request];

  NSString *scheme = nil;
  if (trustedForwarded) {
    NSString *forwardedProto =
        [[request headerForKey:@"x-forwarded-proto"] lowercaseString];
    if (forwardedProto.length > 0) {
      NSString *firstProto =
          [[forwardedProto componentsSeparatedByString:@","] firstObject];
      firstProto =
          [firstProto stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([firstProto isEqualToString:@"https"] ||
          [firstProto isEqualToString:@"http"]) {
        scheme = firstProto;
      }
    }
  }

  NSURL *issuerURL = [NSURL URLWithString:self.oauthServer.issuer ?: @""];
  if (scheme.length == 0) {
    if (localHostHeader) {
      scheme = @"http";
    } else if (issuerURL.scheme.length > 0) {
      scheme = issuerURL.scheme;
    } else {
      scheme = @"https";
    }
  }

  NSString *authority = nil;
  if (hostHeader.length > 0 && (trustedForwarded || localHostHeader)) {
    authority = hostHeader;
  } else if (issuerURL.host.length > 0) {
    authority = issuerURL.host;
    if (issuerURL.port != nil) {
      BOOL isDefaultPort =
          ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] &&
           issuerURL.port.integerValue == 443) ||
          ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] &&
           issuerURL.port.integerValue == 80);
      if (!isDefaultPort) {
        authority = [NSString
            stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
      }
    }
  }

  if (authority.length == 0) {
    return nil;
  }

  NSMutableString *urlString =
      [NSMutableString stringWithFormat:@"%@://%@%@", scheme, authority, path];
  if (request.queryString.length > 0) {
    [urlString appendFormat:@"?%@", request.queryString];
  }
  return [NSURL URLWithString:urlString];
}

- (NSString *)requestOriginForRequest:(HttpRequest *)request {
  NSString *hostHeader = [[request headerForKey:@"host"]
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  NSString *hostLower = [hostHeader lowercaseString];
  BOOL localHostHeader = [hostLower containsString:@"localhost"] ||
                         [hostLower hasPrefix:@"127.0.0.1"] ||
                         [hostLower hasPrefix:@"[::1]"] ||
                         [hostLower isEqualToString:@"::1"];
  BOOL trustedForwarded = [self requestShouldTrustForwardedHeaders:request];

  NSString *scheme = nil;
  if (trustedForwarded) {
    NSString *forwardedProto =
        [[request headerForKey:@"x-forwarded-proto"] lowercaseString];
    if (forwardedProto.length > 0) {
      NSString *firstProto =
          [[forwardedProto componentsSeparatedByString:@","] firstObject];
      firstProto =
          [firstProto stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([firstProto isEqualToString:@"https"] ||
          [firstProto isEqualToString:@"http"]) {
        scheme = firstProto;
      }
    }
  }

  NSURL *issuerURL = [NSURL URLWithString:self.oauthServer.issuer ?: @""];
  if (scheme.length == 0) {
    if (localHostHeader) {
      scheme = @"http";
    } else if (issuerURL.scheme.length > 0) {
      scheme = issuerURL.scheme;
    } else {
      scheme = @"https";
    }
  }

  NSString *authority = nil;
  if (hostHeader.length > 0 && (trustedForwarded || localHostHeader)) {
    authority = hostHeader;
  } else if (issuerURL.host.length > 0) {
    authority = issuerURL.host;
    if (issuerURL.port != nil) {
      BOOL isDefaultPort =
          ([issuerURL.scheme.lowercaseString isEqualToString:@"https"] &&
           issuerURL.port.integerValue == 443) ||
          ([issuerURL.scheme.lowercaseString isEqualToString:@"http"] &&
           issuerURL.port.integerValue == 80);
      if (!isDefaultPort) {
        authority = [NSString
            stringWithFormat:@"%@:%@", issuerURL.host, issuerURL.port];
      }
    }
  }

  if (authority.length == 0) {
    return self.oauthServer.issuer;
  }
  return [NSString stringWithFormat:@"%@://%@", scheme, authority];
}

#pragma mark - DPoP Validation
- (void)attachDPoPNonceToResponseIfMissing:(HttpResponse *)response {
  NSString *existingNonce = response.headers[@"DPoP-Nonce"] ?: response.headers[@"dpop-nonce"];
  if (existingNonce.length > 0) {
    return;
  }

  NSString *nextNonce = [[PDSNonceManager sharedManager] generateNonce];
  if (nextNonce.length > 0) {
    [response setHeader:nextNonce forKey:@"DPoP-Nonce"];
  }
}

- (BOOL)validateDPoPForRequest:(HttpRequest *)request
                      response:(HttpResponse *)response
                 outThumbprint:(NSString **)outThumbprint {
  NSString *dpopProof = [request headerForKey:@"dpop"];
  if (!dpopProof || dpopProof.length == 0) {
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Missing DPoP proof"
    }];
    return NO;
  }

  NSURL *dpopURL = [self expectedDPoPURLForRequest:request];
  if (!dpopURL) {
    GZ_LOG_AUTH_DEBUG(@"validateDPoPForRequest: Failed to construct DPoP URL");
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_request",
      @"error_description" : @"Unable to construct DPoP URL"
    }];
    return NO;
  }

  NSError *dpopError = nil;
  NSString *dpopThumbprint = nil;
  NSString *requestedNonce = [request headerForKey:@"DPoP-Nonce"];
  if (requestedNonce.length == 0) {
    requestedNonce = nil;
  }

  if (![OAuth2DPoPProof verifyProof:dpopProof
                             method:request.methodString
                                url:dpopURL
                              nonce:requestedNonce
                       requireNonce:YES
                      outThumbprint:&dpopThumbprint
                              error:&dpopError]) {
    if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
      NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
      if (nonce.length > 0) {
        [response setHeader:nonce forKey:@"DPoP-Nonce"];
      }
      [response setHeader:@"DPoP error=\"use_dpop_nonce\""
                   forKey:@"WWW-Authenticate"];
      [response setHeader:@"no-store" forKey:@"Cache-Control"];
      [response setHeader:@"no-cache" forKey:@"Pragma"];
      response.statusCode = 400;
      [response setJsonBody:@{
        @"error" : @"use_dpop_nonce",
        @"error_description" : dpopError.localizedDescription
            ?: @"DPoP nonce required"
      }];
      return NO;
    }
    response.statusCode = 400;
    [response setJsonBody:@{
      @"error" : @"invalid_dpop_proof",
      @"error_description" : dpopError.localizedDescription
          ?: @"Invalid DPoP proof"
    }];
    return NO;
  }

  [self attachDPoPNonceToResponseIfMissing:response];

  if (dpopThumbprint.length > 0) {
    NSString *prefix = dpopThumbprint.length > 8
                           ? [dpopThumbprint substringToIndex:8]
                           : dpopThumbprint;
    GZ_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint_prefix=%@)", prefix);
  } else {
    GZ_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint unavailable)");
  }

  if (outThumbprint) {
    *outThumbprint = dpopThumbprint;
  }
  return YES;
}

#pragma mark - HTML & Asset Helpers
- (NSString *)escapeHtml:(NSString *)input {
  if (!input)
    return @"";
  NSString *escaped = input;
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
  return escaped;
}

- (NSString *)assetsPath {
  if (self.dataDirectory) {
    NSString *path =
        [self.dataDirectory stringByAppendingPathComponent:@"Auth/Assets"];
    GZ_LOG_AUTH_DEBUG(@"Checking for assets in dataDirectory: %@", path);
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      return path;
    }
  }

  // Check standard install path (Docker/packaged deployments)
  NSString *installPath = @"/usr/share/atprotopds/assets/Auth";
  if ([[NSFileManager defaultManager] fileExistsAtPath:installPath]) {
    return installPath;
  }

  // Fallback to project structure if running from source (handling cwd=build/)
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray *candidates = @[
    [cwd stringByAppendingPathComponent:@"Garazyk/Sources/Auth/Assets"],
    [[cwd stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Garazyk/Sources/Auth/Assets"],
    [[[cwd stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Garazyk/Sources/Auth/Assets"]
  ];

  for (NSString *candidate in candidates) {
    GZ_LOG_AUTH_DEBUG(@"Checking for assets in candidate path: %@", candidate);
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
      return candidate;
    }
  }

  GZ_LOG_AUTH_ERROR(
      @"No assets path found for OAuth2Handler (dataDirectory: %@, cwd: %@)",
      self.dataDirectory, cwd);
  return nil;
}

- (NSString *)sharedCSSPath {
  if (self.dataDirectory) {
    NSString *path =
        [self.dataDirectory stringByAppendingPathComponent:
            @"Shared/DesignSystem/css"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      return path;
    }
  }

  // Check standard install path (Docker/packaged deployments)
  NSString *installPath = @"/usr/share/atprotopds/assets/css";
  if ([[NSFileManager defaultManager] fileExistsAtPath:installPath]) {
    return installPath;
  }

  // Fallback to project structure (development from build/ or project root)
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray *candidates = @[
    [cwd stringByAppendingPathComponent:
        @"Garazyk/Sources/Shared/DesignSystem/css"],
    [[cwd stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:
            @"Garazyk/Sources/Shared/DesignSystem/css"],
  ];

  for (NSString *candidate in candidates) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
      return candidate;
    }
  }

  GZ_LOG_AUTH_ERROR(
      @"No shared CSS path found for OAuth2Handler (dataDirectory: %@, cwd: %@)",
      self.dataDirectory, cwd);
  return nil;
}

- (void)handleCSSRequest:(HttpRequest *)request
                response:(HttpResponse *)response {
  NSString *cssDir = [self sharedCSSPath];
  if (!cssDir) {
    response.statusCode = 404;
    [response setBodyString:@"Not Found"];
    return;
  }

  NSString *filename = request.path.lastPathComponent;
  if (![filename hasSuffix:@".css"]) {
    response.statusCode = 403;
    [response setBodyString:@"Forbidden"];
    return;
  }

  // Prevent path traversal
  if ([filename containsString:@".."]) {
    response.statusCode = 403;
    [response setBodyString:@"Forbidden"];
    return;
  }

  NSString *filePath = [cssDir stringByAppendingPathComponent:filename];
  NSString *resolvedPath = filePath.stringByStandardizingPath;
  NSString *resolvedBase = cssDir.stringByStandardizingPath;
  if (![resolvedPath hasPrefix:resolvedBase]) {
    response.statusCode = 403;
    [response setBodyString:@"Forbidden"];
    return;
  }

  NSError *readError = nil;
  NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
  if (!data) {
    response.statusCode = 404;
    [response setBodyString:@"Not Found"];
    return;
  }

  response.statusCode = 200;
  response.contentType = @"text/css; charset=utf-8";
  [response setBodyData:data];
}

#pragma mark - Client Metadata Fetch
- (void)fetchClientMetadataFromURL:(NSString *)urlStr
                        completion:(void (^)(NSDictionary *_Nullable metadata,
                                             NSError *_Nullable error))completion {
  if (!completion)
    return;

  NSURL *url = [NSURL URLWithString:urlStr];
  NSString *host = url.host;

  if (!url || !host) {
    completion(nil, [NSError errorWithDomain:@"OAuth2"
                                        code:400
                                    userInfo:@{
                                      NSLocalizedDescriptionKey :
                                          @"Invalid client_id URL"
                                    }]);
    return;
  }

  GZ_LOG_AUTH_DEBUG(@"Fetching dynamic client metadata from %@", urlStr);

  // For E2E tests in Docker, we may need to map the client's public URL (e.g. localhost)
  // to an internal container name (e.g. oauth-client).
  NSString *effectiveUrlStr = urlStr;
  const char *envHostMap = getenv("GARAZYK_OAUTH_HOST_MAP");
  if (envHostMap) {
      NSString *hostMap = [NSString stringWithUTF8String:envHostMap];
      NSArray *parts = [hostMap componentsSeparatedByString:@"="];
      if (parts.count == 2) {
          effectiveUrlStr = [urlStr stringByReplacingOccurrencesOfString:parts[0]
                                                              withString:parts[1]];
          if (![effectiveUrlStr isEqualToString:urlStr]) {
              GZ_LOG_AUTH_DEBUG(@"Mapped OAuth client URL: %@ -> %@", urlStr, effectiveUrlStr);
          }
      }
  }

  NSURL *fetchUrl = [NSURL URLWithString:effectiveUrlStr];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:fetchUrl];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  request.timeoutInterval = 10.0;

  ATProtoSafeHTTPClientOptions *safeOptions = [[ATProtoSafeHTTPClientOptions alloc] init];
  safeOptions.timeout = 10.0;
  safeOptions.maxResponseBytes = 256 * 1024; // 256 KB
  
  // In development/test environments, we allow fetching metadata from local/private hosts.
  BOOL allowPrivate = NO;
  const char *envAllowPrivate = getenv("GARAZYK_ALLOW_PRIVATE_OAUTH_CLIENTS");
  if (envAllowPrivate && (strcmp(envAllowPrivate, "1") == 0 || strcmp(envAllowPrivate, "true") == 0)) {
    allowPrivate = YES;
  }
  
  safeOptions.allowHTTP = allowPrivate;
  safeOptions.allowPrivateHosts = allowPrivate;
  safeOptions.followRedirects = YES;

  [[ATProtoSafeHTTPClient sharedClient] performSafeDataTaskWithRequest:request
                                                 options:safeOptions
                                              completion:^(NSData *data, NSHTTPURLResponse *httpResponse, NSError *err) {
    // Map ATProtoSafeHTTPClient SSRF errors to OAuth error codes
    if (err && [err.domain isEqualToString:ATProtoSafeHTTPClientErrorDomain]) {
      NSInteger oauthErrorCode = 500;
      NSString *oauthMessage = @"Failed to fetch client metadata";
      if (err.code == ATProtoSafeHTTPClientErrorSSRFBlocked) {
        oauthErrorCode = 403;
        oauthMessage = @"SSRF Protection: Host resolves to private IP address";
        GZ_LOG_AUTH_ERROR(@"Blocked SSRF attempt for dynamic discovery: %@", urlStr);
      } else if (err.code == ATProtoSafeHTTPClientErrorInvalidURL) {
        oauthErrorCode = 400;
        oauthMessage = @"Invalid client_id URL";
      } else if (err.code == ATProtoSafeHTTPClientErrorUnsupportedScheme) {
        oauthErrorCode = 400;
        oauthMessage = @"Only HTTPS is allowed for client metadata";
      } else if (err.code == ATProtoSafeHTTPClientErrorRedirectBlocked) {
        oauthErrorCode = 403;
        oauthMessage = @"SSRF Protection: Redirect target resolves to private IP address";
        GZ_LOG_AUTH_ERROR(@"Blocked SSRF redirect attempt for dynamic discovery: %@", urlStr);
      }
      NSError *oauthError = [NSError errorWithDomain:@"OAuth2"
                                                 code:oauthErrorCode
                                             userInfo:@{
                                               NSLocalizedDescriptionKey: oauthMessage,
                                               NSUnderlyingErrorKey: err
                                             }];
      completion(nil, oauthError);
      return;
    }

    if (err) {
      completion(nil, err);
      return;
    }

    if (httpResponse.statusCode == 200 && data) {
      NSError *jsonError = nil;
      id json = [NSJSONSerialization JSONObjectWithData:data
                                                  options:0
                                                    error:&jsonError];
      if ([json isKindOfClass:[NSDictionary class]]) {
        completion(json, nil);
      } else {
        completion(nil, jsonError ?: [NSError
                             errorWithDomain:@"OAuth2"
                                        code:400
                                    userInfo:@{
                                      NSLocalizedDescriptionKey :
                                          @"Client metadata is not a "
                                          @"JSON object"
                                    }]);
      }
    } else {
      completion(nil, [NSError
                          errorWithDomain:@"OAuth2"
                                     code:httpResponse.statusCode
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       [NSString
                                           stringWithFormat:
                                               @"Failed to fetch "
                                               @"client metadata: %ld",
                                               (long)httpResponse
                                                   .statusCode]
                                 }]);
    }
  }];
}

@end
