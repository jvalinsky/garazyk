#import "OAuthServerMetadata.h"

@implementation OAuthServerMetadata

+ (instancetype)defaultMetadata {
    OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] init];
    metadata.issuer = @"https://localhost:2583";
    metadata.authorizationEndpoint = @"https://localhost:2583/oauth/authorize";
    metadata.tokenEndpoint = @"https://localhost:2583/oauth/token";
    metadata.pushedAuthorizationRequestEndpoint = @"https://localhost:2583/oauth/par";
    metadata.responseTypesSupported = @[@"code"];
    metadata.grantTypesSupported = @[@"authorization_code", @"refresh_token"];
    metadata.codeChallengeMethodsSupported = @[@"S256"];
    metadata.tokenEndpointAuthMethodsSupported = @[@"none", @"private_key_jwt"];
    metadata.tokenEndpointAuthSigningAlgValuesSupported = @[@"ES256"];
    metadata.scopesSupported = @[@"atproto", @"transition:generic", @"transition:chat.bsky", @"transition:email"];
    metadata.dpopSigngingAlgValuesSupported = @[@"ES256"];
    metadata.authorizationResponseIssParameterSupported = YES;
    metadata.requirePushedAuthorizationRequests = YES;
    metadata.clientIdMetadataDocumentSupported = YES;
    metadata.requireRequestUriRegistration = YES;
    return metadata;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"issuer"] = self.issuer;
    dict[@"authorization_endpoint"] = self.authorizationEndpoint;
    dict[@"token_endpoint"] = self.tokenEndpoint;
    dict[@"pushed_authorization_request_endpoint"] = self.pushedAuthorizationRequestEndpoint;
    dict[@"response_types_supported"] = self.responseTypesSupported;
    dict[@"grant_types_supported"] = self.grantTypesSupported;
    dict[@"code_challenge_methods_supported"] = self.codeChallengeMethodsSupported;
    dict[@"token_endpoint_auth_methods_supported"] = self.tokenEndpointAuthMethodsSupported;
    dict[@"token_endpoint_auth_signing_alg_values_supported"] = self.tokenEndpointAuthSigningAlgValuesSupported;
    dict[@"scopes_supported"] = self.scopesSupported;
    dict[@"dpop_signing_alg_values_supported"] = self.dpopSigngingAlgValuesSupported;
    dict[@"authorization_response_iss_parameter_supported"] = @(self.authorizationResponseIssParameterSupported);
    dict[@"require_pushed_authorization_requests"] = @(self.requirePushedAuthorizationRequests);
    dict[@"client_id_metadata_document_supported"] = @(self.clientIdMetadataDocumentSupported);
    dict[@"require_request_uri_registration"] = @(self.requireRequestUriRegistration);

    return [dict copy];
}

@end
