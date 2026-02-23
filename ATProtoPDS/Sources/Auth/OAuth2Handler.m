#import "Auth/OAuth2Handler.h"
#import "Network/HttpServer.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/Session.h"
#import "Auth/CryptoUtils.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import "Auth/OAuthServerMetadata.h"

#import "Debug/PDSLogger.h"
#import "App/PDSConfiguration.h"
#import "App/Services/PDSAccountService.h"

@interface OAuth2Handler ()
@property (nonatomic, strong) PDSDatabase *database;

- (void)handleAuthorizeRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAuthorizeConfirm:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAuthorizeSignIn:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleTokenRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRevokeRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleProtectedResourceMetadata:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePARRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (BOOL)validateDPoPForRequest:(HttpRequest *)request response:(HttpResponse *)response outThumbprint:(NSString **)outThumbprint;
- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata error:(NSError **)error;
- (BOOL)isLoopbackRedirect:(NSString *)redirectURI;
- (NSString *)assetsPath;
- (NSString *)escapeHtml:(NSString *)input;
- (void)serveAuthorizePage:(HttpResponse *)response params:(NSDictionary *)params;
@end

static NSMutableDictionary *sPendingConsents = nil;

@implementation OAuth2Handler {
    JWTMinter *_minter;
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
        if (!sPendingConsents) sPendingConsents = [NSMutableDictionary dictionary];
        self.oauthServer = [[OAuth2Server alloc] initWithDatabase:database];
        self.oauthServer.jwtMinter = self.minter;

        // Keep env override behavior for tests/runtime while canonicalizing issuer shape.
        PDSConfiguration *configuration = [PDSConfiguration sharedConfiguration];
        NSString *envIssuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"];
        NSString *issuer = nil;
        if (envIssuer.length > 0) {
            PDSConfiguration *envConfiguration = [[PDSConfiguration alloc] init];
            envConfiguration.issuer = envIssuer;
            issuer = [envConfiguration canonicalIssuerWithPortHint:0];
        } else {
            issuer = [configuration canonicalIssuerWithPortHint:0];
        }
        self.oauthServer.issuer = issuer;

        self.oauthServer.authorizationEndpoint = [NSString stringWithFormat:@"%@/oauth/authorize", issuer];
        self.oauthServer.tokenEndpoint = [NSString stringWithFormat:@"%@/oauth/token", issuer];
        self.oauthServer.jwksURI = [NSString stringWithFormat:@"%@/oauth/jwks", issuer];
    }
    return self;
}

- (instancetype)init {
    // Legacy init - create temporary database for backward compatibility
    // In production, use initWithDatabase: instead
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"oauth_temp.db"];
    PDSDatabase *tempDB = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:tempPath]];
    NSError *error = nil;
    if (![tempDB openWithError:&error]) {
        PDS_LOG_AUTH_ERROR(@"Failed to create temporary OAuth database: %@", error);
        return nil;
    }
    return [self initWithDatabase:tempDB];
}

- (NSDictionary *)validateClient:(NSString *)clientID error:(NSError **)error {
    if (!clientID) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing client_id"}];
        }
        return nil;
    }

    // First attempt: Query database (existing path - preserve this exactly)
    NSDictionary *client = [self.database getClientWithID:clientID error:error];
    if (client) {
        // Database lookup succeeded - return the client
        return client;
    }
    
    // Database lookup failed - check if client_metadata is available
    if (self.clientMetadata) {
        PDS_LOG_AUTH_INFO(@"Client not in database, attempting validation via client_metadata for client_id: %@", clientID);
        
        // Validate using client_metadata
        NSError *metadataError = nil;
        NSDictionary *validatedClient = [self validateClientMetadata:self.clientMetadata error:&metadataError];
        
        if (validatedClient) {
            PDS_LOG_AUTH_INFO(@"Client validated successfully via client_metadata: %@", clientID);
            return validatedClient;
        } else {
            // Metadata validation failed
            if (error) {
                *error = metadataError;
            }
            return nil;
        }
    }
    
    // Not found in database AND no client_metadata provided
    if (error) {
        *error = [NSError errorWithDomain:@"OAuth2" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Invalid client"}];
    }
    return nil;
}

- (NSDictionary *)validateClientMetadata:(NSDictionary *)metadata error:(NSError **)error {
    if (!metadata || ![metadata isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"client_metadata must be a JSON object"}];
        }
        return nil;
    }
    
    // Validate client_id is HTTPS URL (required by ATProto spec)
    NSString *clientID = metadata[@"client_id"];
    if (!clientID || ![clientID isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"client_id is required in client_metadata"}];
        }
        return nil;
    }
    
    if (![clientID hasPrefix:@"https://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"client_id must be an HTTPS URL per ATProto OAuth specification"}];
        }
        return nil;
    }
    
    // Validate it's a valid URL
    NSURL *clientIDURL = [NSURL URLWithString:clientID];
    if (!clientIDURL || !clientIDURL.host) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"client_id must be a valid HTTPS URL"}];
        }
        return nil;
    }
    
    // Validate redirect_uris array is present, non-empty, and contains valid URIs
    NSArray *redirectURIs = metadata[@"redirect_uris"];
    if (!redirectURIs || ![redirectURIs isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"redirect_uris array is required in client_metadata"}];
        }
        return nil;
    }
    
    if (redirectURIs.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"redirect_uris array must contain at least one URI"}];
        }
        return nil;
    }
    
    // Validate each redirect_uri is a valid URI string
    for (id redirectURI in redirectURIs) {
        if (![redirectURI isKindOfClass:[NSString class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"All redirect_uris must be strings"}];
            }
            return nil;
        }
        
        NSString *uriString = (NSString *)redirectURI;
        NSURL *uri = [NSURL URLWithString:uriString];
        if (!uri || !uri.scheme) {
            if (error) {
                *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid redirect_uri: %@", uriString]}];
            }
            return nil;
        }
    }
    
    // Extract client_name (optional but recommended)
    NSString *clientName = metadata[@"client_name"];
    if (clientName && ![clientName isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"client_name must be a string"}];
        }
        return nil;
    }
    
    // Extract grant_types (optional, default to "authorization_code refresh_token")
    id grantTypes = metadata[@"grant_types"];
    NSString *grantTypesString = nil;
    if (grantTypes) {
        if ([grantTypes isKindOfClass:[NSArray class]]) {
            // Convert array to space-separated string
            grantTypesString = [(NSArray *)grantTypes componentsJoinedByString:@" "];
        } else if ([grantTypes isKindOfClass:[NSString class]]) {
            grantTypesString = (NSString *)grantTypes;
        } else {
            if (error) {
                *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"grant_types must be an array or string"}];
            }
            return nil;
        }
    } else {
        grantTypesString = @"authorization_code refresh_token";
    }
    
    // Extract scope (optional, default to "atproto")
    NSString *scope = metadata[@"scope"];
    if (scope && ![scope isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"scope must be a string"}];
        }
        return nil;
    }
    if (!scope) {
        scope = @"atproto";
    }
    
    // Return normalized client dictionary matching database format for consistency
    return @{
        @"client_id": clientID,
        @"redirect_uris": redirectURIs,
        @"client_name": clientName ?: clientID,
        @"grant_types": grantTypesString,
        @"scope": scope
    };
}

- (BOOL)isLoopbackRedirect:(NSString *)redirectURI {
    if (!redirectURI) return NO;
    NSURL *url = [NSURL URLWithString:redirectURI];
    if (!url || !url.host) return NO;
    if (![[url.scheme lowercaseString] isEqualToString:@"http"]) return NO;
    
    NSString *host = [url.host lowercaseString];
    return ([host isEqualToString:@"127.0.0.1"] ||
            [host isEqualToString:@"localhost"] ||
            [host isEqualToString:@"::1"] ||
            [host isEqualToString:@"[::1]"]);
}

- (BOOL)validateRedirectURI:(NSString *)redirectURI forClient:(NSDictionary *)client error:(NSError **)error {
    if (!redirectURI) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing redirect_uri"}];
        }
        return NO;
    }

    NSURL *url = [NSURL URLWithString:redirectURI];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid redirect_uri format"}];
        }
        return NO;
    }

    BOOL isLoopback = [self isLoopbackRedirect:redirectURI];

    // Scheme validation: HTTPS required unless it's a loopback redirect (RFC 8252)
    if (!isLoopback) {
        #ifndef DEBUG
        if (![url.scheme isEqualToString:@"https"]) {
            if (error) {
                *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"redirect_uri must use HTTPS in production"}];
            }
            return NO;
        }
        #else
        if ([url.scheme isEqualToString:@"http"]) {
            NSString *host = url.host;
            if (![host isEqualToString:@"localhost"] && ![host isEqualToString:@"127.0.0.1"]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"HTTP redirect_uri only allowed for localhost in development"}];
                }
                return NO;
            }
        }
        #endif
    }

    // Check if the redirect URI is in the client's registered URIs
    NSArray *allowedURIs = client[@"redirect_uris"];
    if (!allowedURIs || ![allowedURIs isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Client has no registered redirect URIs"}];
        }
        return NO;
    }

    PDS_LOG_AUTH_DEBUG(@"Validating redirect_uri: '%@' against allowed: %@", redirectURI, allowedURIs);

    for (NSString *allowedURI in allowedURIs) {
        // Exact match (standard OAuth 2.0 security best practice)
        if ([redirectURI isEqualToString:allowedURI]) {
            PDS_LOG_AUTH_DEBUG(@"Successfully matched redirect_uri: %@", allowedURI);
            return YES;
        }

        // Loopback port wildcard matching per RFC 8252 §7.3:
        // If the allowed URI is a loopback address, match ignoring port.
        if (isLoopback && [self isLoopbackRedirect:allowedURI]) {
            NSURL *allowedURL = [NSURL URLWithString:allowedURI];
            if (allowedURL &&
                [[url.host lowercaseString] isEqualToString:[allowedURL.host lowercaseString]] &&
                [[url.path ?: @"/" lowercaseString] isEqualToString:[allowedURL.path ?: @"/" lowercaseString]]) {
                PDS_LOG_AUTH_DEBUG(@"Loopback port-wildcard matched redirect_uri: %@ (allowed: %@)", redirectURI, allowedURI);
                return YES;
            }
        }
    }
    
    PDS_LOG_AUTH_DEBUG(@"No match found for redirect_uri: %@", redirectURI);

    if (error) {
        *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid redirect_uri"}];
    }
    return NO;
}

- (void)registerRoutesWithServer:(HttpServer *)httpServer {
    [httpServer addRoute:@"GET" path:@"/oauth/authorize" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleAuthorizeRequest:request response:response];
    }];
    
    [httpServer addRoute:@"POST" path:@"/oauth/authorize/confirm" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleAuthorizeConfirm:request response:response];
    }];

    [httpServer addRoute:@"POST" path:@"/oauth/authorize/sign-in" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleAuthorizeSignIn:request response:response];
    }];

    [httpServer addRoute:@"POST" path:@"/oauth/token" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleTokenRequest:request response:response];
    }];
    
    [httpServer addRoute:@"POST" path:@"/oauth/revoke" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleRevokeRequest:request response:response];
    }];

    [httpServer addRoute:@"GET" path:@"/.well-known/oauth-authorization-server" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleAuthorizationServerMetadata:request response:response];
    }];

    [httpServer addRoute:@"GET" path:@"/.well-known/oauth-protected-resource" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleProtectedResourceMetadata:request response:response];
    }];

    // Phase 4: Add /oauth/jwks endpoint for publishing public keys
    [httpServer addRoute:@"GET" path:@"/oauth/jwks" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleJWKS:request response:response];
    }];

    // Phase 4: Add /oauth/par endpoint for Pushed Authorization Requests
    [httpServer addRoute:@"POST" path:@"/oauth/par" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handlePARRequest:request response:response];
    }];

    // CORS preflight handlers for ATProto OAuth client compatibility
    void (^corsPreflightHandler)(HttpRequest *, HttpResponse *) = ^(HttpRequest *req, HttpResponse *resp) {
        [resp setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
        [resp setHeader:@"GET, POST, OPTIONS" forKey:@"Access-Control-Allow-Methods"];
        [resp setHeader:@"Authorization, Content-Type, DPoP, DPoP-Nonce" forKey:@"Access-Control-Allow-Headers"];
        [resp setHeader:@"86400" forKey:@"Access-Control-Max-Age"];
        resp.statusCode = 204;
    };
    [httpServer addRoute:@"OPTIONS" path:@"/oauth/authorize" handler:corsPreflightHandler];
    [httpServer addRoute:@"OPTIONS" path:@"/oauth/token" handler:corsPreflightHandler];
    [httpServer addRoute:@"OPTIONS" path:@"/oauth/par" handler:corsPreflightHandler];
    [httpServer addRoute:@"OPTIONS" path:@"/oauth/revoke" handler:corsPreflightHandler];
}

- (void)handleAuthorizationServerMetadata:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *issuer = self.oauthServer.issuer;
    if (!issuer) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"Server configuration error: issuer not configured"}];
        return;
    }

    OAuthServerMetadata *metadata = [[OAuthServerMetadata alloc] initWithBaseURL:issuer];
    if (!metadata) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"Server configuration error: failed to generate metadata"}];
        return;
    }

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setJsonBody:metadata.metadata];
    response.statusCode = 200;
}

- (void)handleProtectedResourceMetadata:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *issuer = self.oauthServer.issuer;
    if (!issuer) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"Server configuration error: issuer not configured"}];
        return;
    }

    NSDictionary *resourceMetadata = @{
        @"resource": issuer,
        @"authorization_servers": @[
            @{
                @"authorization_server": issuer,
                @"resource_servers": @[issuer]
            }
        ],
        @"protected_resources": @[
            @{
                @"resource": issuer,
                @"resource_scopes": @[@"atproto"],
                @"bearer_methods_supported": @[@"header"],
                @"access_token_types_supported": @[@"Bearer", @"DPoP"]
            }
        ]
    };

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setJsonBody:resourceMetadata];
    response.statusCode = 200;
}

- (void)handleAuthorizeRequest:(HttpRequest *)request response:(HttpResponse *)response {
    PDS_LOG_AUTH_INFO(@"Starting authorize request for path: %@", request.path);
    // Use request.queryParams if available, otherwise parse manually
    NSMutableDictionary *params = [request.queryParams mutableCopy] ?: [NSMutableDictionary dictionary];

    // Extract and parse client_metadata parameter if provided
    NSString *clientMetadataString = params[@"client_metadata"];
    NSDictionary *clientMetadata = nil;
    if (clientMetadataString && clientMetadataString.length > 0) {
        NSError *jsonError = nil;
        NSData *jsonData = [clientMetadataString dataUsingEncoding:NSUTF8StringEncoding];
        if (jsonData) {
            id parsedJSON = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
            if (jsonError) {
                PDS_LOG_AUTH_WARN(@"Failed to parse client_metadata JSON: %@", jsonError.localizedDescription);
                // Continue without metadata - will be handled by validation
            } else if ([parsedJSON isKindOfClass:[NSDictionary class]]) {
                clientMetadata = (NSDictionary *)parsedJSON;
                PDS_LOG_AUTH_INFO(@"Parsed client_metadata with %lu keys", (unsigned long)clientMetadata.count);
            } else {
                PDS_LOG_AUTH_WARN(@"client_metadata is not a JSON object");
            }
        }
    }
    
    // Store clientMetadata in handler for use by validateClient
    self.clientMetadata = clientMetadata;

    // Validate client from database
    NSString *clientID = params[@"client_id"];
    if (!clientID) {
        PDS_LOG_AUTH_WARN(@"Missing client_id in authorize request");
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Missing client_id"
        }];
        return;
    }

    NSError *clientError = nil;
    NSDictionary *client = [self validateClient:clientID error:&clientError];
    if (!client) {
        PDS_LOG_AUTH_WARN(@"Invalid client_id: %@, error: %@", clientID, clientError.localizedDescription);
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"unauthorized_client",
            @"error_description": clientError.localizedDescription ?: @"Invalid client"
        }];
        return;
    }

    PDS_LOG_AUTH_INFO(@"Found client: %@", clientID);

    // Validate redirect URI against client's registered URIs
    NSString *redirectURI = params[@"redirect_uri"];
    NSError *redirectError = nil;
    if (![self validateRedirectURI:redirectURI forClient:client error:&redirectError]) {
        PDS_LOG_AUTH_WARN(@"Invalid redirect_uri: %@ for client %@, error: %@", redirectURI, clientID, redirectError.localizedDescription);
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": redirectError.localizedDescription ?: @"Invalid redirect_uri"
        }];
        return;
    }

    // Validate state parameter (CSRF protection)
    NSString *state = params[@"state"];
    if (!state || [state stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0) {
        PDS_LOG_AUTH_WARN(@"Missing state parameter for client: %@", clientID);
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"state parameter required for CSRF protection"
        }];
        return;
    }
    
    OAuth2AuthorizationRequest *authRequest = [[OAuth2AuthorizationRequest alloc] init];
    authRequest.clientID = clientID;
    authRequest.redirectURI = params[@"redirect_uri"];
    authRequest.responseType = params[@"response_type"];
    authRequest.scope = params[@"scope"];
    authRequest.state = params[@"state"];
    authRequest.codeChallenge = params[@"code_challenge"];
    authRequest.codeChallengeMethod = params[@"code_challenge_method"];
    authRequest.nonce = params[@"nonce"];
    authRequest.loginHint = params[@"login_hint"];
    authRequest.clientMetadata = clientMetadata;
    
    // RFC 7636: Public clients must use PKCE
    // A client is considered public if it has no secret
    BOOL isPublicClient = (client[@"client_secret"] == nil);
    if (isPublicClient && (!authRequest.codeChallenge || authRequest.codeChallenge.length == 0)) {
        PDS_LOG_AUTH_WARN(@"Public client missing code_challenge: %@", clientID);
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"code_challenge required for public clients"
        }];
        return;
    }
    
    PDS_LOG_AUTH_INFO(@"Processing authorization for client: %@, hint: %@", clientID, authRequest.loginHint);

    // Instead of auto-authorizing, serve the consent screen
    [self serveAuthorizePage:response params:params];
}

- (void)serveAuthorizePage:(HttpResponse *)response params:(NSDictionary *)params {
    NSString *assetsPath = [self assetsPath];
    NSString *filePath = [assetsPath stringByAppendingPathComponent:@"authorize.html"];
    PDS_LOG_AUTH_INFO(@"Serving authorize page from: %@", filePath);
    
    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error];
    if (!html || error) {
        PDS_LOG_AUTH_ERROR(@"Failed to load authorize.html at %@: %@", filePath, error);
        response.statusCode = 500;
        [response setBodyString:@"Internal Server Error: Missing authorization assets."];
        return;
    }
    
    PDS_LOG_AUTH_DEBUG(@"Loaded html, size: %lu", (unsigned long)html.length);
    
    // Generate CSRF token
    NSString *csrfToken = [[NSUUID UUID] UUIDString];
    html = [html stringByReplacingOccurrencesOfString:@"{{csrf_token}}" withString:[self escapeHtml:csrfToken]];
    
    // Simple template replacement with HTML escaping
    NSString *clientId = [self escapeHtml:params[@"client_id"] ?: @"Unknown App"];
    NSString *state = [self escapeHtml:params[@"state"] ?: @""];
    NSString *scope = [self escapeHtml:params[@"scope"] ?: @"atproto"];
    NSString *redirectUri = [self escapeHtml:params[@"redirect_uri"] ?: @""];
    NSString *responseType = [self escapeHtml:params[@"response_type"] ?: @"code"];
    NSString *codeChallenge = [self escapeHtml:params[@"code_challenge"] ?: @""];
    NSString *codeChallengeMethod = [self escapeHtml:params[@"code_challenge_method"] ?: @"S256"];
    NSString *nonce = [self escapeHtml:params[@"nonce"] ?: @""];

    NSString *loginHint = [self escapeHtml:params[@"login_hint"] ?: @""];
    
    html = [html stringByReplacingOccurrencesOfString:@"{{client_id}}" withString:clientId];
    html = [html stringByReplacingOccurrencesOfString:@"{{state}}" withString:state];
    html = [html stringByReplacingOccurrencesOfString:@"{{scope}}" withString:scope];
    html = [html stringByReplacingOccurrencesOfString:@"{{redirect_uri}}" withString:redirectUri];
    html = [html stringByReplacingOccurrencesOfString:@"{{response_type}}" withString:responseType];
    html = [html stringByReplacingOccurrencesOfString:@"{{code_challenge}}" withString:codeChallenge];
    html = [html stringByReplacingOccurrencesOfString:@"{{code_challenge_method}}" withString:codeChallengeMethod];
    html = [html stringByReplacingOccurrencesOfString:@"{{nonce}}" withString:nonce];
    html = [html stringByReplacingOccurrencesOfString:@"{{login_hint}}" withString:loginHint];
    
    [response setHeader:[NSString stringWithFormat:@"csrf_token=%@; Path=/oauth; HttpOnly; SameSite=Strict", csrfToken] forKey:@"Set-Cookie"];
    response.statusCode = 200;
    response.contentType = @"text/html; charset=utf-8";
    [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)handleAuthorizeConfirm:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *body = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    NSDictionary *params = [self parseFormUrlEncodedString:body];
    
    NSString *decision = params[@"decision"];
    NSString *clientID = params[@"client_id"];
    NSString *state = params[@"state"];
    NSString *scope = params[@"scope"];
    
    if ([decision isEqualToString:@"deny"]) {
        NSString *redirectUri = params[@"redirect_uri"];
        if (redirectUri.length > 0) {
            NSURLComponents *components = [NSURLComponents componentsWithString:redirectUri];
            NSMutableArray *queryItems = [components.queryItems mutableCopy] ?: [NSMutableArray array];
            [queryItems addObject:[NSURLQueryItem queryItemWithName:@"error" value:@"access_denied"]];
            [queryItems addObject:[NSURLQueryItem queryItemWithName:@"error_description" value:@"User denied the authorization request"]];
            if (state.length > 0) {
                [queryItems addObject:[NSURLQueryItem queryItemWithName:@"state" value:state]];
            }
            components.queryItems = queryItems;
            response.statusCode = 302;
            [response setHeader:components.URL.absoluteString forKey:@"Location"];
        } else {
            response.statusCode = 403;
            [response setJsonBody:@{@"error": @"access_denied", @"error_description": @"User denied the authorization request"}];
        }
        return;
    }
    
    // Validate session token
    NSString *sessionToken = params[@"session_token"];
    
    if (!sessionToken || sessionToken.length == 0) {
        response.statusCode = 403;
        [response setJsonBody:@{@"error": @"access_denied", @"error_description": @"Missing session token"}];
        return;
    }
    
    NSDictionary *consentSession = nil;
    @synchronized (sPendingConsents) {
        consentSession = sPendingConsents[sessionToken];
    }
    
    if (!consentSession) {
        response.statusCode = 403;
        [response setJsonBody:@{@"error": @"access_denied", @"error_description": @"Invalid or expired session token"}];
        return;
    }
    
    NSDate *expires = consentSession[@"expires"];
    if ([expires compare:[NSDate date]] == NSOrderedAscending) {
        @synchronized (sPendingConsents) {
            [sPendingConsents removeObjectForKey:sessionToken];
        }
        response.statusCode = 403;
        [response setJsonBody:@{@"error": @"access_denied", @"error_description": @"Session token expired"}];
        return;
    }
    
    // Clean up used token
    @synchronized (sPendingConsents) {
        [sPendingConsents removeObjectForKey:sessionToken];
    }
    
    // Proceed with authorization
    OAuth2AuthorizationRequest *authRequest = [[OAuth2AuthorizationRequest alloc] init];
    authRequest.clientID = clientID;
    authRequest.state = state;
    authRequest.scope = scope;
    authRequest.redirectURI = params[@"redirect_uri"];
    authRequest.responseType = params[@"response_type"];
    authRequest.codeChallenge = params[@"code_challenge"];
    authRequest.codeChallengeMethod = params[@"code_challenge_method"];
    authRequest.nonce = params[@"nonce"];
    // Pass the authenticated user's handle so the auth code gets a login_hint_did
    authRequest.loginHint = consentSession[@"handle"];
    
    PDS_LOG_AUTH_INFO(@"Authorizing request for client: %@, redirect_uri: %@", clientID, authRequest.redirectURI);
    
    [self.oauthServer handleAuthorizationRequest:authRequest completion:^(NSURL * _Nullable authorizationURL, NSString * _Nullable authorizationCode, NSError * _Nullable error) {
        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"invalid_request", @"error_description": error.localizedDescription}];
            return;
        }
        
        if (authorizationURL) {
            response.statusCode = 302;
            [response setHeader:authorizationURL.absoluteString forKey:@"Location"];
        } else {
            response.statusCode = 500;
            [response setBodyString:@"Server Error"];
        }
    }];
}

- (void)handleAuthorizeSignIn:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *body = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    NSDictionary *params = [self parseFormUrlEncodedString:body];
    
    NSString *handle = params[@"handle"];
    NSString *password = params[@"password"];
    
    // CSRF validation
    NSString *csrfHeader = [request headerForKey:@"X-CSRF-Token"];
    NSString *cookieHeader = [request headerForKey:@"Cookie"];
    NSString *csrfCookie = nil;
    if (cookieHeader) {
        for (NSString *cookie in [cookieHeader componentsSeparatedByString:@";"]) {
            NSString *trimmed = [cookie stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed hasPrefix:@"csrf_token="]) {
                csrfCookie = [trimmed substringFromIndex:@"csrf_token=".length];
                break;
            }
        }
    }
    if (!csrfHeader || !csrfCookie || ![csrfHeader isEqualToString:csrfCookie]) {
        response.statusCode = 403;
        [response setJsonBody:@{@"ok": @NO, @"error": @"Invalid CSRF token"}];
        return;
    }
    
    if (!handle.length || !password.length) {
        response.statusCode = 400;
        [response setJsonBody:@{@"ok": @NO, @"error": @"Handle and password are required"}];
        return;
    }
    
    if (!self.accountService) {
        PDS_LOG_AUTH_ERROR(@"Sign-in attempted but no accountService configured");
        response.statusCode = 500;
        [response setJsonBody:@{@"ok": @NO, @"error": @"Authentication service unavailable"}];
        return;
    }
    
    NSError *authError = nil;
    NSDictionary *result = [self.accountService loginWithIdentifier:handle
                                                          password:password
                                                             error:&authError];
    
    if (result && result[@"did"]) {
        PDS_LOG_AUTH_INFO(@"Sign-in successful for handle: %@", handle);
        NSString *sessionToken = [[NSUUID UUID] UUIDString];
        @synchronized (sPendingConsents) {
            sPendingConsents[sessionToken] = @{
                @"did": result[@"did"],
                @"handle": handle,
                @"expires": [NSDate dateWithTimeIntervalSinceNow:300]
            };
        }
        response.statusCode = 200;
        [response setJsonBody:@{@"ok": @YES, @"did": result[@"did"], @"session_token": sessionToken}];
    } else {
        PDS_LOG_AUTH_INFO(@"Sign-in failed for handle: %@, error: %@", handle, authError.localizedDescription ?: @"unknown");
        response.statusCode = 401;
        [response setJsonBody:@{@"ok": @NO, @"error": @"Invalid handle or password"}];
    }
}

- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    // NSURLComponents parses percent-encoded query strings automatically
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.percentEncodedQuery = input;
    
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name) {
            params[item.name] = item.value ?: @"";
        }
    }
    return [params copy];
}

- (void)handleTokenRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *body = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    if (!body) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Missing request body"
        }];
        return;
    }
    
    NSDictionary *params = [self parseFormUrlEncodedString:body];

    NSString *grantType = params[@"grant_type"];

    // Validate client from database
    NSString *clientID = params[@"client_id"];
    PDS_LOG_AUTH_INFO(@"Token request received (grant_type=%@, client_id=%@)", grantType ?: @"", clientID ?: @"");
    NSError *clientError = nil;
    NSDictionary *client = [self validateClient:clientID error:&clientError];
    if (!client) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": clientError.localizedDescription ?: @"Invalid client"
        }];
        return;
    }
    PDS_LOG_AUTH_DEBUG(@"Token request client validation passed (client_id=%@)", clientID ?: @"");

    // Validate client secret (optional for DPoP-based clients)
    // In ATProto, client authentication can use DPoP binding instead of client_secret
    NSString *clientSecret = params[@"client_secret"];
    NSString *dpopJWK = params[@"dpop_jwk"];
    NSString *dpopProof = [request headerForKey:@"dpop"];
    BOOL hasDpopProof = (dpopProof.length > 0);
    NSString *expectedSecret = client[@"client_secret"];

    if (clientSecret && expectedSecret && ![clientSecret isEqualToString:expectedSecret]) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": @"Invalid client credentials"
        }];
        return;
    }

    // Reject if client_secret is required but not provided and no DPoP binding
    if (!clientSecret && !dpopJWK && !hasDpopProof && expectedSecret) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": @"Client authentication required"
        }];
        return;
    }

    // Validate redirect URI for authorization_code grant type
    if ([grantType isEqualToString:@"authorization_code"]) {
        NSString *redirectURI = params[@"redirect_uri"];
        // URL-decode the redirect_uri since browsers send it encoded in form data
        if (redirectURI) {
            NSString *decodedRedirectURI = [redirectURI stringByRemovingPercentEncoding];
            if (decodedRedirectURI) {
                redirectURI = decodedRedirectURI;
            }
        }
        NSError *redirectError = nil;
        if (![self validateRedirectURI:redirectURI forClient:client error:&redirectError]) {
            PDS_LOG_AUTH_WARN(@"Token request redirect_uri validation failed (client_id=%@): %@",
                              clientID ?: @"",
                              redirectError.localizedDescription ?: @"Invalid redirect_uri");
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"invalid_request",
                @"error_description": redirectError.localizedDescription ?: @"Invalid redirect_uri"
            }];
            return;
        }
    }
    
    NSString *dpopThumbprint = nil;
    if (![self validateDPoPForRequest:request response:response outThumbprint:&dpopThumbprint]) {
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
    
    [self.oauthServer handleTokenRequest:tokenRequest completion:^(Session * _Nullable session, NSError * _Nullable error) {
        if (error) {
            response.statusCode = 400;
            NSDictionary *errorResponse = @{
                @"error": @"invalid_grant",
                @"error_description": error.localizedDescription
            };
            
            // Check for 2FA required
            if (error.userInfo[@"error"] && [error.userInfo[@"error"] isEqualToString:@"mfa_required"]) {
                errorResponse = @{
                    @"error": @"interaction_required",
                    @"error_description": error.localizedDescription
                };
            }
            
            [response setJsonBody:errorResponse];
            return;
        }
        
        if (session) {
            response.statusCode = 200;
            NSMutableDictionary *tokenResp = [@{
                @"access_token": session.accessToken,
                @"token_type": @"DPoP",
                @"expires_in": @3600,
                @"scope": session.scope ?: @"atproto"
            } mutableCopy];
            if (session.refreshToken) tokenResp[@"refresh_token"] = session.refreshToken;
            if (session.did) tokenResp[@"sub"] = session.did;
            [response setJsonBody:tokenResp];
        } else {
            response.statusCode = 500;
            [response setJsonBody:@{
                @"error": @"server_error",
                @"error_description": @"Failed to create session"
            }];
        }
    }];
}

- (void)handleRevokeRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *body = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    if (!body) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Missing request body"
        }];
        return;
    }
    
    NSDictionary *params = [self parseFormUrlEncodedString:body];

    // Validate client from database
    NSString *clientID = params[@"client_id"];
    NSString *token = params[@"token"];

    NSError *clientError = nil;
    NSDictionary *client = [self validateClient:clientID error:&clientError];
    if (!client) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": clientError.localizedDescription ?: @"Invalid client"
        }];
        return;
    }
    
    if (!token) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Missing token parameter"
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
        // Token not found - still return success for security (don't reveal if token exists)
    }
    
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response {
    // Access JWKS via the minter
    NSDictionary *jwks = [self.minter toJWKS];
    if (!jwks) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"server_error", @"error_description": @"Failed to export JWKS"}];
        return;
    }

    [response setHeader:@"*" forKey:@"Access-Control-Allow-Origin"];
    [response setJsonBody:jwks];
    response.statusCode = 200;
}

- (void)handlePARRequest:(HttpRequest *)request response:(HttpResponse *)response {
    PDS_LOG_AUTH_INFO(@"Handling PAR request");
    
    // Parse body parameters
    NSString *body = [[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding];
    NSDictionary *params = [self parseFormUrlEncodedString:body];
    
    // Validate client authentication (either client_secret or DPoP)
    NSString *clientID = params[@"client_id"];
    if (!clientID) {
        response.statusCode = 400;
        [response setJsonBody:@{@"error": @"invalid_client", @"error_description": @"Missing client_id"}];
        return;
    }
    
    NSError *clientError = nil;
    NSDictionary *client = [self validateClient:clientID error:&clientError];
    if (!client) {
        response.statusCode = 401;
        [response setJsonBody:@{@"error": @"invalid_client", @"error_description": clientError.localizedDescription ?: @"Invalid client"}];
        return;
    }

    NSString *clientSecret = params[@"client_secret"];
    // Note: DPoP check logic is similar to token endpoint, simplified here for now
    NSString *expectedSecret = client[@"client_secret"];
    if (expectedSecret && ![clientSecret isEqualToString:expectedSecret]) {
         response.statusCode = 401;
         [response setJsonBody:@{@"error": @"invalid_client", @"error_description": @"Invalid client credentials"}];
         return;
    }

    // Enforce DPoP for PAR
    NSString *dpopThumbprint = nil;
    if (![self validateDPoPForRequest:request response:response outThumbprint:&dpopThumbprint]) {
        return;
    }
    
    // Generate request URI
    NSString *requestUUID = [[NSUUID UUID] UUIDString];
    NSString *requestURI = [NSString stringWithFormat:@"urn:ietf:params:oauth:request_uri:%@", requestUUID];
    
    // Store parameters in database (using a new table or generic storage)
    // For now, we will store it in a temporary table or generic cache if available.
    // Since we don't have a specific PAR table, we'll assume a `oauth_par_requests` table exists or should be created.
    // To conform to the plan, we need to store this.
    // Let's create the table if needed (lazy init) or just insert.
    NSData *paramsData = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
    NSTimeInterval expiresIn = 600; // 10 minutes
    NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:expiresIn];
    
    // Simple table schema: request_uri TEXT PRIMARY KEY, params_json TEXT, expires_at TEXT
    NSString *createTableSQL = @"CREATE TABLE IF NOT EXISTS oauth_par_requests (request_uri TEXT PRIMARY KEY, params_json TEXT, expires_at TEXT)";
    [self.database executeParameterizedUpdate:createTableSQL params:@[] error:nil];
    
    NSString *sql = @"INSERT INTO oauth_par_requests (request_uri, params_json, expires_at) VALUES (?, ?, ?)";
    [self.database executeParameterizedUpdate:sql params:@[requestURI, [[NSString alloc] initWithData:paramsData encoding:NSUTF8StringEncoding], [self iso8601StringFromDate:expiresAt]] error:nil];
    
    response.statusCode = 201;
    [response setJsonBody:@{
        @"request_uri": requestURI,
        @"expires_in": @(expiresIn)
    }];
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return [formatter stringFromDate:date];
}

- (BOOL)validateDPoPForRequest:(HttpRequest *)request response:(HttpResponse *)response outThumbprint:(NSString **)outThumbprint {
    NSString *dpopProof = [request headerForKey:@"dpop"];
    if (!dpopProof || dpopProof.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Missing DPoP proof"
        }];
        return NO;
    }

    NSString *host = [request headerForKey:@"host"];
    NSString *scheme = [request headerForKey:@"x-forwarded-proto"];
    if (!scheme) {
        NSString *lowercaseHost = [host lowercaseString];
        if ([lowercaseHost containsString:@"localhost"] || [lowercaseHost hasPrefix:@"127.0.0.1"] || [lowercaseHost hasPrefix:@"::1"]) {
            scheme = @"http";
        } else {
            scheme = @"https";
        }
    }
    
    NSString *path = request.path ?: @"/";
    NSMutableString *urlString = nil;
    if (host.length > 0) {
        urlString = [NSMutableString stringWithFormat:@"%@://%@%@", scheme, host, path];
        if (request.queryString.length > 0) {
            [urlString appendFormat:@"?%@", request.queryString];
        }
    } else if (self.oauthServer.issuer.length > 0) {
        NSURL *issuerURL = [NSURL URLWithString:self.oauthServer.issuer];
        urlString = [NSMutableString stringWithFormat:@"%@://%@%@", issuerURL.scheme ?: scheme, issuerURL.host ?: @"", path];
        if (request.queryString.length > 0) {
            [urlString appendFormat:@"?%@", request.queryString];
        }
    }

    NSURL *dpopURL = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
    if (!dpopURL) {
        PDS_LOG_AUTH_DEBUG(@"validateDPoPForRequest: Failed to construct dpopURL from: %@", urlString);
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Unable to construct DPoP URL"
        }];
        return NO;
    }

    NSError *dpopError = nil;
    NSString *dpopThumbprint = nil;
    NSString *requestedNonce = [request headerForKey:@"DPoP-Nonce"];
    if (requestedNonce.length == 0) {
        requestedNonce = nil;
    }
    
    if (![OAuth2DPoPProof verifyProof:dpopProof
                                method:request.methodString
                                   url:dpopURL
                                 nonce:requestedNonce
                          requireNonce:YES
                         outThumbprint:&dpopThumbprint
                                 error:&dpopError]) {
        if ([dpopError.userInfo[@"use_dpop_nonce"] boolValue]) {
            NSString *nonce = [[PDSNonceManager sharedManager] generateNonce];
            if (nonce.length > 0) {
                [response setHeader:nonce forKey:@"DPoP-Nonce"];
            }
            [response setHeader:@"DPoP error=\"use_dpop_nonce\"" forKey:@"WWW-Authenticate"];
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"use_dpop_nonce",
                @"error_description": dpopError.localizedDescription ?: @"DPoP nonce required"
            }];
            return NO;
        }
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_dpop_proof",
            @"error_description": dpopError.localizedDescription ?: @"Invalid DPoP proof"
        }];
        return NO;
    }

    if (dpopThumbprint.length > 0) {
        NSString *prefix = dpopThumbprint.length > 8 ? [dpopThumbprint substringToIndex:8] : dpopThumbprint;
        PDS_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint_prefix=%@)", prefix);
    } else {
        PDS_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint unavailable)");
    }
    
    if (outThumbprint) {
        *outThumbprint = dpopThumbprint;
    }
    return YES;
}

- (NSString *)escapeHtml:(NSString *)input {
    if (!input) return @"";
    NSString *escaped = input;
    escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
    return escaped;
}

- (NSString *)assetsPath {
    if (self.dataDirectory) {
        NSString *path = [self.dataDirectory stringByAppendingPathComponent:@"Auth/Assets"];
        PDS_LOG_AUTH_DEBUG(@"Checking for assets in dataDirectory: %@", path);
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }
    
    // Fallback to project structure if running from source
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *sourcePath = [cwd stringByAppendingPathComponent:@"ATProtoPDS/Sources/Auth/Assets"];
    PDS_LOG_AUTH_DEBUG(@"Checking for assets in sourcePath: %@", sourcePath);
    if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
        return sourcePath;
    }
    
    PDS_LOG_AUTH_ERROR(@"No assets path found for OAuth2Handler (dataDirectory: %@, cwd: %@)", self.dataDirectory, cwd);
    return nil;
}

@end
