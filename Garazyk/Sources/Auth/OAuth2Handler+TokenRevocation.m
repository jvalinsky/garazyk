// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+TokenRevocation.h"
#import "Auth/OAuth2.h"
#import "Auth/Session.h"
#import "Auth/CryptoUtils.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@implementation OAuth2Handler (TokenRevocation)

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

@end
