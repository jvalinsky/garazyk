// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "OAuthServerMetadata.h"

@implementation OAuthServerMetadata

- (instancetype)initWithBaseURL:(NSString *)baseURL {
  // Validate base URL
  if (!baseURL || [baseURL length] == 0) {
    return nil;
  }

  // Basic URL validation
  NSURL *url = [NSURL URLWithString:baseURL];
  if (!url || !url.host || [url.host length] == 0) {
    return nil;
  }

  // Reject non-HTTPS URLs except for localhost (local development)
  if (![url.scheme isEqualToString:@"https"]) {
    NSString *host = [url.host lowercaseString];
    BOOL isLocalhost = [host isEqualToString:@"localhost"] ||
                       [host isEqualToString:@"127.0.0.1"] ||
                       [host isEqualToString:@"::1"] ||
                       [host hasSuffix:@".localhost"] ||
                       [host hasSuffix:@".local"];
    if (!isLocalhost) {
      return nil;
    }
  }

  self = [super init];
  if (self) {
    // Ensure standard URL formatting: issuer must NOT have a trailing slash
    // per RFC 8414 (OAuth 2.0 Authorization Server Metadata).
    NSString *issuer = baseURL;
    if ([issuer hasSuffix:@"/"]) {
      issuer = [issuer substringToIndex:issuer.length - 1];
    }

    _metadata = @{
      @"issuer" : issuer,
      @"authorization_endpoint" :
          [[url URLByAppendingPathComponent:@"oauth/authorize"] absoluteString],
      @"token_endpoint" :
          [[url URLByAppendingPathComponent:@"oauth/token"] absoluteString],
      @"jwks_uri" :
          [[url URLByAppendingPathComponent:@"oauth/jwks"] absoluteString],
      @"pushed_authorization_request_endpoint" :
          [[url URLByAppendingPathComponent:@"oauth/par"] absoluteString],
      @"require_pushed_authorization_requests" : @YES,
      @"response_types_supported" : @[ @"code" ],
      @"response_modes_supported" : @[ @"query", @"fragment" ],
      @"grant_types_supported" : @[ @"authorization_code", @"refresh_token" ],
      @"code_challenge_methods_supported" : @[ @"S256" ],
      @"token_endpoint_auth_methods_supported" :
          @[ @"none", @"private_key_jwt" ],
      @"token_endpoint_auth_signing_alg_values_supported" : @[ @"ES256", @"ES256K" ],
      @"authorization_response_iss_parameter_supported" : @YES,
      @"dpop_signing_alg_values_supported" : @[ @"ES256", @"ES256K" ],
      @"require_request_uri_registration" : @YES,
      @"client_id_metadata_document_supported" : @YES,
      @"scopes_supported" :
          @[ @"atproto", @"transition:generic", @"transition:chat.bsky",
             @"transition:email" ]
    };
  }
  return self;
}

@end
