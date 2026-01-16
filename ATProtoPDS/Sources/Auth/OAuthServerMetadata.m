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
        // Ensure standard URL formatting (remove trailing slash for issuer, use for path appending)
        // Note: URLByAppendingPathComponent handles slashes correctly
        
        _metadata = @{
            @"issuer": baseURL,
            @"authorization_endpoint": [[url URLByAppendingPathComponent:@"oauth/authorize"] absoluteString],
            @"token_endpoint": [[url URLByAppendingPathComponent:@"oauth/token"] absoluteString],
            @"jwks_uri": [[url URLByAppendingPathComponent:@"oauth/jwks"] absoluteString],
            @"response_types_supported": @[@"code"],
            @"grant_types_supported": @[@"authorization_code", @"refresh_token"],
            @"token_endpoint_auth_methods_supported": @[@"client_secret_basic"],
            @"scopes_supported": @[@"atproto"]
        };
    }
    return self;
}

@end