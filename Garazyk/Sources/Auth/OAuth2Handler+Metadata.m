// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+Metadata.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuthServerMetadata.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (Metadata)

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

@end
