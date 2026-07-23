// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+PAR.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuthClientAuthPolicy.h"
#import "Auth/CryptoUtils.h"
#import "Auth/PDSNonceManager.h"
#import "Database/PDSDatabase.h"
#import "Security/PDSSecurityCompare.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (PAR)

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

@end
