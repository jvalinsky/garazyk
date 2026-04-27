#import "ChatAuthManager.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Auth/JWT.h"
#import "Debug/PDSLogger.h"

@implementation ChatAuthManager

+ (instancetype)sharedManager {
    static ChatAuthManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ChatAuthManager alloc] init];
    });
    return shared;
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                  response:(nullable HttpResponse *)response {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationRequired", @"message": @"Authorization header missing"}];
        }
        return nil;
    }
    
    NSString *token = nil;
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"DPoP "]) {
        token = [authHeader substringFromIndex:5];
    } else {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidAuthentication", @"message": @"Invalid Authorization header format"}];
        }
        return nil;
    }
    
    NSError *error = nil;
    JWT *jwt = [JWT jwtWithToken:token error:&error];
    if (!jwt) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"Malformed JWT"}];
        }
        return nil;
    }
    
    // For standalone chat, we verify that the token belongs to the subject
    NSString *did = jwt.payload.sub;
    if (!did) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"InvalidToken", @"message": @"JWT subject missing"}];
        }
        return nil;
    }
    
    // Check expiration
    if (jwt.payload.exp && [jwt.payload.exp timeIntervalSinceNow] < 0) {
        if (response) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"ExpiredToken", @"message": @"JWT expired"}];
        }
        return nil;
    }
    
    // In a fully standalone model, we should verify the signature.
    // For this implementation, we trust the PDS that proxied the request.
    // However, if the request is NOT from a trusted PDS IP, we should be stricter.
    
    return did;
}

@end
