// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Admin/AdminMiddleware.h"
#import "Admin/PDSAdminAuth.h"
#import "Auth/Session.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h" // Added import
#import "Compat/PDSTypes.h"

NSString * const AdminMiddlewareErrorDomain = @"com.atproto.pds.admin.middleware";

@interface AdminMiddleware ()

@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t accessQueue;

@end

@implementation AdminMiddleware

+ (instancetype)sharedMiddleware {
    static AdminMiddleware *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _adminDids = @[];
        _accessQueue = dispatch_queue_create("com.atproto.pds.admin.middleware", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)setAdminDids:(NSArray<NSString *> *)adminDids {
    _adminDids = [adminDids copy];
}

- (BOOL)verifyAdminAccessForRequest:(HttpRequest *)request
                           response:(HttpResponse *)response
                              error:(NSError **)error {
    NSError *sessionError = nil;
    Session *session = [self extractSessionFromRequest:request error:&sessionError];
    
    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:AdminMiddlewareErrorDomain
                                         code:AdminMiddlewareErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid or missing authentication token"}];
        }
        response.statusCode = 401;
        [response setJsonBody:@{
            @"error": @"Unauthorized",
            @"message": @"Valid authentication token required"
        }];
        return NO;
    }
    
    __block BOOL isAdmin = NO;
    
    dispatch_sync(self.accessQueue, ^{
        isAdmin = [self.adminDids containsObject:session.did];
    });

    if (!isAdmin) {
        isAdmin = [[PDSAdminAuth sharedAuth] isAdminDid:session.did];
    }
    
    if (!isAdmin && self.customAdminCheck) {
        isAdmin = self.customAdminCheck(session);
    }
    
    if (!isAdmin) { // Kept original condition `!isAdmin`
        GZ_LOG_ADMIN_WARN(@"Non-admin user %@ attempted to access admin endpoint", session.did); // Replaced NSLog
        
        if (error) {
            *error = [NSError errorWithDomain:AdminMiddlewareErrorDomain
                                         code:AdminMiddlewareErrorNotAdmin
                                     userInfo:@{NSLocalizedDescriptionKey: @"User is not authorized as admin"}];
        }
        response.statusCode = 403;
        [response setJsonBody:@{
            @"error": @"Forbidden",
            @"message": @"Admin access required"
        }];
        return NO;
    }
    
    GZ_LOG_ADMIN_INFO(@"Admin action by user %@", session.did); // Replaced NSLog
    
    return YES;
}

- (nullable Session *)extractSessionFromRequest:(HttpRequest *)request error:(NSError **)error {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    
    if (!authHeader) {
        if (error) {
            *error = [NSError errorWithDomain:AdminMiddlewareErrorDomain
                                         code:AdminMiddlewareErrorNoAuthHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing Authorization header"}];
        }
        return nil;
    }
    
    NSString *token = nil;
    
    if ([authHeader hasPrefix:@"Bearer "]) {
        token = [authHeader substringFromIndex:7];
    } else if ([authHeader hasPrefix:@"Bearer="]) {
        token = [authHeader substringFromIndex:7];
    } else {
        token = authHeader;
    }
    
    if (!token || token.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:AdminMiddlewareErrorDomain
                                         code:AdminMiddlewareErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid token format"}];
        }
        return nil;
    }
    
    SessionStore *store = [SessionStore sharedStore];
    NSError *sessionError = nil;
    Session *session = [store getSessionByAccessToken:token error:&sessionError];
    
    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:AdminMiddlewareErrorDomain
                                         code:AdminMiddlewareErrorInvalidToken
                                     userInfo:@{NSLocalizedDescriptionKey: sessionError.localizedDescription ?: @"Invalid or expired token"}];
        }
        return nil;
    }
    
    return session;
}

@end
