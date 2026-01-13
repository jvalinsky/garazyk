#import "Auth/OAuth2Handler.h"
#import "Network/HttpServer.h"
#import "Auth/OAuth2.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"

@interface OAuth2Handler ()
@property (nonatomic, strong) PDSDatabase *database;
@end

@implementation OAuth2Handler

@synthesize minter = _minter;

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        self.oauthServer = [[OAuth2Server alloc] init];
        self.oauthServer.jwtMinter = self.minter;

        // Use configurable issuer from environment, default to localhost
        NSString *issuer = [[NSProcessInfo processInfo] environment][@"PDS_ISSUER"] ?: @"https://pds.local:8443";
        self.oauthServer.issuer = issuer;

        // Build other endpoints relative to issuer
        self.oauthServer.authorizationEndpoint = [NSString stringWithFormat:@"%@/oauth/authorize", issuer];
        self.oauthServer.tokenEndpoint = [NSString stringWithFormat:@"%@/oauth/token", issuer];
        self.oauthServer.jwksURI = [NSString stringWithFormat:@"%@/.well-known/jwks.json", issuer];

        #ifdef DEBUG
        // Seed test client for development only
        NSError *seedError = nil;
        if (![_database seedTestClient:&seedError]) {
            NSLog(@"Warning: Failed to seed test OAuth client: %@", seedError.localizedDescription);
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
        NSLog(@"Failed to create temp database: %@", error);
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
    [httpServer addRoute:@"GET" path:@"/oauth/authorize" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleAuthorizeRequest:request response:response];
    }];

    [httpServer addRoute:@"POST" path:@"/oauth/token" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleTokenRequest:request response:response];
    }];

    [httpServer addRoute:@"POST" path:@"/oauth/revoke" handler:^(HttpRequest *request, HttpResponse *response) {
        [self handleRevokeRequest:request response:response];
    }];
}

- (void)handleAuthorizeRequest:(HttpRequest *)request response:(HttpResponse *)response {
    // Use request.queryParams if available, otherwise parse manually
    NSMutableDictionary *params = [request.queryParams mutableCopy] ?: [NSMutableDictionary dictionary];

    // Validate client from database
    NSString *clientID = params[@"client_id"];
    NSError *clientError = nil;
    NSDictionary *client = [self validateClient:clientID error:&clientError];
    if (!client) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"unauthorized_client",
            @"error_description": clientError.localizedDescription ?: @"Invalid client"
        }];
        return;
    }

    // Validate redirect URI against client's registered URIs
    NSString *redirectURI = params[@"redirect_uri"];
    NSError *redirectError = nil;
    if (![self validateRedirectURI:redirectURI forClient:client error:&redirectError]) {
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
    
    [self.oauthServer handleAuthorizationRequest:authRequest completion:^(NSURL * _Nullable authorizationURL, NSString * _Nullable authorizationCode, NSError * _Nullable error) {
        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"invalid_request",
                @"error_description": error.localizedDescription
            }];
            return;
        }
        
        if (authorizationURL) {
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
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSArray *pairs = [body componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *keyValue = [pair componentsSeparatedByString:@"="];
        if (keyValue.count == 2) {
            NSString *key = [keyValue[0] stringByRemovingPercentEncoding];
            NSString *value = [keyValue[1] stringByRemovingPercentEncoding];
            if (key && value) {
                params[key] = value;
            }
        }
    }

    // Validate client from database
    NSString *clientID = params[@"client_id"];
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

    // Validate client secret
    // Note: In a production environment, this should use a constant-time comparison
    // to prevent timing attacks (e.g., CRYPTO_memcmp or similar).
    NSString *clientSecret = params[@"client_secret"];
    if (!clientSecret || ![clientSecret isEqualToString:client[@"client_secret"]]) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": @"Invalid client credentials"
        }];
        return;
    }

    // Validate redirect URI for authorization_code grant type
    NSString *grantType = params[@"grant_type"];
    if ([grantType isEqualToString:@"authorization_code"]) {
        NSString *redirectURI = params[@"redirect_uri"];
        NSError *redirectError = nil;
        if (![self validateRedirectURI:redirectURI forClient:client error:&redirectError]) {
            response.statusCode = 400;
            [response setJsonBody:@{
                @"error": @"invalid_request",
                @"error_description": redirectError.localizedDescription ?: @"Invalid redirect_uri"
            }];
            return;
        }
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
    
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSArray *pairs = [body componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *keyValue = [pair componentsSeparatedByString:@"="];
        if (keyValue.count == 2) {
            NSString *key = [keyValue[0] stringByRemovingPercentEncoding];
            NSString *value = [keyValue[1] stringByRemovingPercentEncoding];
            if (key && value) {
                params[key] = value;
            }
        }
    }

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

@end