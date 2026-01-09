#import "Auth/OAuth2Handler.h"
#import "Network/HttpServer.h"
#import "Auth/OAuth2.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@interface OAuth2Handler ()
@property (nonatomic, strong) OAuth2Server *oauthServer;
@end

@implementation OAuth2Handler

- (instancetype)init {
    self = [super init];
    if (self) {
        _oauthServer = [[OAuth2Server alloc] init];
        _oauthServer.issuer = @"https://pds.local:8443";
        _oauthServer.authorizationEndpoint = @"https://pds.local:8443/oauth/authorize";
        _oauthServer.tokenEndpoint = @"https://pds.local:8443/oauth/token";
        _oauthServer.jwksURI = @"https://pds.local:8443/.well-known/jwks.json";
    }
    return self;
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
    
    // Hardcoded client validation for test-client
    NSString *clientID = params[@"client_id"];
    if (!clientID || ![clientID isEqualToString:@"test-client"]) {
        response.statusCode = 400;
        [response setJsonBody:@{
            @"error": @"unauthorized_client",
            @"error_description": @"Only 'test-client' is supported"
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
    
    // Hardcoded client validation
    NSString *clientID = params[@"client_id"];
    if (!clientID || ![clientID isEqualToString:@"test-client"]) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": @"Only 'test-client' is supported"
        }];
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
    
    // Hardcoded client validation
    NSString *clientID = params[@"client_id"];
    NSString *token = params[@"token"];
    
    if (!clientID || ![clientID isEqualToString:@"test-client"]) {
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"invalid_client",
            @"error_description": @"Only 'test-client' is supported"
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
    
    // For now, just remove from active sessions
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
    }
    
    response.statusCode = 200;
    [response setJsonBody:@{}];
}

@end