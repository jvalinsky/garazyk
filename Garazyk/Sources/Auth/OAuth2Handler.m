// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler_Internal.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuthClientAuthPolicy.h"
#import "Database/PDSDatabase.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Security/Space/PDSSpaceScope.h"
#import "Debug/GZLogger.h"

#import "Auth/OAuth2Handler+Helpers.h"
#import "Auth/OAuth2Handler+ConsentStore.h"
#import "Auth/OAuth2Handler+Metadata.h"
#import "Auth/OAuth2Handler+Assets.h"
#import "Auth/OAuth2Handler+TokenRevocation.h"
#import "Auth/OAuth2Handler+TokenEndpoint.h"
#import "Auth/OAuth2Handler+DPoP.h"
#import "Auth/OAuth2Handler+PasskeyAuth.h"
#import "Auth/OAuth2Handler+ClientMetadataFetch.h"
#import "Auth/OAuth2Handler+PAR.h"
#import "Auth/OAuth2Handler+Authorization.h"
#import "Auth/OAuth2Handler+ClientValidation.h"

#pragma mark - Shared State
NSMutableDictionary *sPendingConsents = nil;
NSMutableDictionary *sPasskeyChallenges = nil;
dispatch_queue_t sPasskeyChallengeQueue = nil;
dispatch_queue_t sAuthGlobalsQueue = nil;
dispatch_queue_t sClientMetadataQueue = nil;
NSCache *sClientMetadataCache = nil;

const NSTimeInterval kPendingConsentTTLSeconds = 300.0;
const NSTimeInterval kPasskeyChallengeTTLSeconds = 300.0;
const NSUInteger kMaxPendingConsents = 1024;
const NSTimeInterval kClientValidationTimeoutSeconds = 10.0;
NSInteger const kClientValidationTimeoutCode = 504;

dispatch_once_t sClientCacheOnceToken;
static dispatch_once_t sPasskeyChallengeOnceToken;
static dispatch_once_t sAuthGlobalsQueueOnceToken;

BOOL OAuthHandlerScopeIsValid(NSString *scope) {
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

@end
