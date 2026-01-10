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
        _metadata = @{
            @"issuer": baseURL,
            @"authorization_endpoint": [baseURL stringByAppendingPathComponent:@"/oauth/authorize"],
            @"token_endpoint": [baseURL stringByAppendingPathComponent:@"/oauth/token"],
            @"jwks_uri": [baseURL stringByAppendingPathComponent:@"/oauth/jwks"],
            @"response_types_supported": @[@"code"],
            @"grant_types_supported": @[@"authorization_code", @"refresh_token"],
            @"token_endpoint_auth_methods_supported": @[@"client_secret_basic"],
            @"scopes_supported": @[@"atproto"]
        };
    }
    return self;
}

@end