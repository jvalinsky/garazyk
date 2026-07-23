// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+TokenEndpoint.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuthClientAuthPolicy.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (TokenEndpoint)

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

@end
