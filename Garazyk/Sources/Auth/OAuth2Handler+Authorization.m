// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Auth/OAuth2Handler+Authorization.h"

#import "Auth/OAuth2.h"
#import "Security/PDSSecurityCompare.h"
#import "Services/PDS/PDSAccountService.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (Authorization)

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

@end
