#import "Video/VideoJWTAuthProvider.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"

@implementation VideoJWTAuthProvider

- (instancetype)initWithExpectedAudience:(NSString *)audience
                            signingKeyJWK:(nullable NSDictionary *)signingKeyJWK {
    self = [super init];
    if (self) {
        _audience = [audience copy];
        _signingKeyJWK = signingKeyJWK;
    }
    return self;
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                   response:(HttpResponse *)response {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader || authHeader.length == 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"AuthRequired",
            @"message": @"Valid authorization required"
        }];
        return nil;
    }

    NSString *token = nil;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
    }

    if (!token || token.length == 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"AuthRequired",
            @"message": @"Invalid authorization header format"
        }];
        return nil;
    }

    // Parse and verify the JWT
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (!jwt) {
        PDS_LOG_WARN(@"Service Auth JWT parsing failed: %@", error);
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token parsing failed"
        }];
        return nil;
    }

    JWTVerifier *verifier = [[JWTVerifier alloc] init];
    verifier.expectedAudience = self.audience;
    if (![verifier verifyJWT:jwt error:&error]) {
        PDS_LOG_WARN(@"Service Auth JWT verification failed: %@", error);
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token verification failed"
        }];
        return nil;
    }

    // Verify audience
    NSString *aud = jwt.payload.aud;
    if (aud && ![aud isEqualToString:self.audience]) {
        PDS_LOG_WARN(@"Service Auth JWT audience mismatch: expected %@, got %@", self.audience, aud);
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token audience mismatch"
        }];
        return nil;
    }

    // Verify scope (lxm for Service Auth tokens)
    NSString *scope = jwt.payload.scope;
    if (scope && ![scope isEqualToString:@"com.atproto.repo.uploadBlob"] &&
        ![scope isEqualToString:@"app.bsky.video.uploadVideo"]) {
        PDS_LOG_WARN(@"Service Auth JWT scope mismatch: %@", scope);
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{
            @"error": @"Forbidden",
            @"message": @"Token does not authorize this operation"
        }];
        return nil;
    }

    // Verify expiration
    NSDate *exp = jwt.payload.exp;
    if (exp && [exp timeIntervalSinceNow] < 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"ExpiredToken",
            @"message": @"Token has expired"
        }];
        return nil;
    }

    // Extract issuer DID
    NSString *iss = jwt.payload.iss;
    if (!iss || iss.length == 0) {
        response.statusCode = HttpStatusUnauthorized;
        [response setJsonBody:@{
            @"error": @"InvalidToken",
            @"message": @"Token missing issuer"
        }];
        return nil;
    }

    return iss;
}

@end
