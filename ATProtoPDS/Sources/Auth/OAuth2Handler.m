#import "Auth/OAuth2Handler.h"
#import "Network/HttpServer.h"
#import "Auth/OAuth2.h"
#import "Auth/PDSNonceManager.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import "Auth/OAuthServerMetadata.h"
#import "Auth/KeyRotationManager.h"
#import "Debug/PDSLogger.h"

@interface OAuth2Handler ()
@property (nonatomic, strong) PDSDatabase *database;

- (void)handleAuthorizeRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleTokenRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleRevokeRequest:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleAuthorizationServerMetadata:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleProtectedResourceMetadata:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handleJWKS:(HttpRequest *)request response:(HttpResponse *)response;
- (void)handlePARRequest:(HttpRequest *)request response:(HttpResponse *)response;
@end

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
        self.oauthServer = [[OAuth2Server alloc] initWithDatabase:database];
        self.oauthServer.jwtMinter = self.minter;

        // Use configurable issuer from environment, default to localhost
        NSString *issuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
        self.oauthServer.issuer = issuer;

        // Build other endpoints relative to issuer
        self.oauthServer.authorizationEndpoint = [NSString stringWithFormat:@"%@/oauth/authorize", issuer];
        self.oauthServer.tokenEndpoint = [NSString stringWithFormat:@"%@/oauth/token", issuer];
        self.oauthServer.jwksURI = [NSString stringWithFormat:@"%@/oauth/jwks", issuer];

        #ifdef DEBUG
        // Seed test client for development only
        NSError *seedError = nil;
        if (![_database seedTestClient:&seedError]) {
            PDS_LOG_AUTH_WARN(@"Failed to seed test OAuth client: %@", seedError.localizedDescription);
        }
        #endif
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

    NSDictionary *client = [self.database getClientWithID:clientID error:error];
    if (!client) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:401 userInfo:@{NSLocalizedDescriptionKey: @"Invalid client"}];
        }
        return nil;
    }

    return client;
}

- (BOOL)validateRedirectURI:(NSString *)redirectURI forClient:(NSDictionary *)client error:(NSError **)error {
    if (!redirectURI) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Missing redirect_uri"}];
        }
        return NO;
    }

    // Validate URL scheme (HTTPS required in production, HTTP allowed for localhost in debug)
    NSURL *url = [NSURL URLWithString:redirectURI];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid redirect_uri format"}];
        }
        return NO;
    }

    #ifndef DEBUG
    // Production: require HTTPS
    if (![url.scheme isEqualToString:@"https"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"redirect_uri must use HTTPS in production"}];
        }
        return NO;
    }
    #else
    // Development: allow HTTP for localhost only
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

    // Check if the redirect URI is in the client's registered URIs
    NSArray *allowedURIs = client[@"redirect_uris"];
    if (!allowedURIs || ![allowedURIs isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"OAuth2" code:500 userInfo:@{NSLocalizedDescriptionKey: @"Client has no registered redirect URIs"}];
        }
        return NO;
    }

    // Exact match required (OAuth 2.0 security best practice)
    for (NSString *allowedURI in allowedURIs) {
        if ([redirectURI isEqualToString:allowedURI]) {
            return YES;
        }
    }

    if (error) {
        *error = [NSError errorWithDomain:@"OAuth2" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid redirect_uri"}];
    }
    return NO;
}

- (void)registerRoutesWithServer:(HttpServer *)httpServer {
    __weak typeof(self) weakSelf = self;

    [httpServer addRoute:@"GET" path:@"/oauth/authorize" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleAuthorizeRequest:request response:response];
    }];

    [httpServer addRoute:@"POST" path:@"/oauth/token" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleTokenRequest:request response:response];
    }];

    [httpServer addRoute:@"POST" path:@"/oauth/revoke" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleRevokeRequest:request response:response];
    }];

    [httpServer addRoute:@"GET" path:@"/.well-known/oauth-authorization-server" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleAuthorizationServerMetadata:request response:response];
    }];

    [httpServer addRoute:@"GET" path:@"/.well-known/oauth-protected-resource" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleProtectedResourceMetadata:request response:response];
    }];

    // Phase 4: Add /oauth/jwks endpoint for publishing public keys
    [httpServer addRoute:@"GET" path:@"/oauth/jwks" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handleJWKS:request response:response];
    }];

    // Phase 4: Add /oauth/par endpoint for Pushed Authorization Requests
    [httpServer addRoute:@"POST" path:@"/oauth/par" handler:^(HttpRequest *request, HttpResponse *response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf handlePARRequest:request response:response];
    }];
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

    [self.oauthServer handleAuthorizationRequest:authRequest completion:^(NSURL * _Nullable authorizationURL, NSString * _Nullable authorizationCode, NSError * _Nullable error) {
        if (error) {
            PDS_LOG_AUTH_ERROR(@"Authorization failed: %@", error.localizedDescription);
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"invalid_request",
                @"error_description": error.localizedDescription
            }];
            return;
        }
        
        if (authorizationURL) {
            PDS_LOG_AUTH_INFO(@"Authorization successful, redirecting to: %@", authRequest.redirectURI);
            // For demo purposes, redirect with code
            response.statusCode = 302;
            NSString *redirectURL = [NSString stringWithFormat:@"%@?code=%@", 
                                   authRequest.redirectURI ?: @"http://localhost:3000/callback",
                                   authorizationCode];
            if (authRequest.state) {
                redirectURL = [NSString stringWithFormat:@"%@&state=%@", redirectURL, authRequest.state];
            }
            [response setHeader:redirectURL forKey:@"Location"];
        } else {
            response.statusCode = 500;
            [response setJsonBody:@{
                @"error": @"server_error",
                @"error_description": @"Failed to generate authorization"
            }];
        }
    }];
}

- (NSDictionary *)parseFormUrlEncodedString:(NSString *)input {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    // NSURLComponents parses percent-encoded query strings automatically
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.query = input;
    
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
        PDS_LOG_AUTH_DEBUG(@"Token request redirect_uri validation passed (client_id=%@)", clientID ?: @"");
    }
    
    if (!dpopProof || dpopProof.length == 0) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Missing DPoP proof"
        }];
        return;
    }

    NSString *host = [request headerForKey:@"host"];
    NSString *scheme = [request headerForKey:@"x-forwarded-proto"];
    if (!scheme) {
        // Default to http for localhost/127.0.0.1, otherwise https
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
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"invalid_request",
            @"error_description": @"Unable to construct DPoP URL"
        }];
        return;
    }

    NSError *dpopError = nil;
    NSString *dpopThumbprint = nil;
    if (![OAuth2DPoPProof verifyProof:dpopProof
                               method:request.methodString
                                  url:dpopURL
                                nonce:nil
                         requireNonce:NO
                        outThumbprint:&dpopThumbprint
                                error:&dpopError]) {
        if (dpopError.userInfo[@"use_dpop_nonce"]) {
            [response setHeader:[[PDSNonceManager sharedManager] generateNonce] forKey:@"DPoP-Nonce"];
        }
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"use_dpop_nonce",
            @"error_description": dpopError.localizedDescription ?: @"Invalid DPoP proof"
        }];
        return;
    }
    if (dpopThumbprint.length > 0) {
        NSString *prefix = dpopThumbprint.length > 8 ? [dpopThumbprint substringToIndex:8] : dpopThumbprint;
        PDS_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint_prefix=%@)", prefix);
    } else {
        PDS_LOG_AUTH_DEBUG(@"DPoP proof verified (thumbprint unavailable)");
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
            [response setJsonBody:@{
                @"access_token": session.accessToken,
                @"token_type": @"DPoP",
                @"expires_in": @3600,
                @"refresh_token": session.refreshToken,
                @"scope": session.scope
            }];
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
        if ([session.accessToken isEqualToString:token] || [session.refreshToken isEqualToString:token]) {
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

@end
