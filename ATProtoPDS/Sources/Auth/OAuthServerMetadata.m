#import "OAuthServerMetadata.h"

@implementation OAuthServerMetadata

- (instancetype)initWithBaseURL:(NSString *)baseURL {
  // Validate base URL
  if (!baseURL || [baseURL length] == 0) {
    return nil;
  }

  // Ensure base URL uses HTTPS
  if (![baseURL hasPrefix:@"https://"]) {
    return nil;
  }

  // Basic URL validation
  NSURL *url = [NSURL URLWithString:baseURL];
  if (!url || !url.host || [url.host length] == 0) {
    return nil;
  }

  self = [super init];
  if (self) {
    // Ensure standard URL formatting (remove trailing slash for issuer, use for
    // path appending) Note: URLByAppendingPathComponent handles slashes
    // correctly
    _metadata = @{
      @"issuer" : baseURL,
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
      @"response_modes_supported" : @[ @"query" ],
      @"grant_types_supported" : @[ @"authorization_code", @"refresh_token" ],
      @"code_challenge_methods_supported" : @[ @"S256" ],
      @"token_endpoint_auth_methods_supported" :
          @[ @"none", @"private_key_jwt", @"client_secret_basic" ],
      @"token_endpoint_auth_signing_alg_values_supported" :
          @[ @"ES256", @"RS256" ],
      @"authorization_response_iss_parameter_supported" : @YES,
      @"dpop_signing_alg_values_supported" : @[ @"ES256" ],
      @"client_id_metadata_document_supported" : @YES,
      @"scopes_supported" :
          @[ @"atproto", @"transition:generic", @"transition:chat.bsky" ]
    };
  }
  return self;
}

@end
