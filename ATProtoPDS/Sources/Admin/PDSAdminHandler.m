#import <Foundation/Foundation.h>
#import "Admin/PDSAdminAuth.h"
#import "Metrics/PDSMetrics.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDSHTTPMethod) {
    PDSHTTPMethodDELETE,
    PDSHTTPMethodGET,
    PDSHTTPMethodPOST,
    PDSHTTPMethodPUT
};

@interface PDSAdminHandler : NSObject

+ (instancetype)sharedHandler;

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                        path:(NSString *)path
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                        body:(nullable NSData *)body;

@end

@implementation PDSAdminHandler

+ (instancetype)sharedHandler {
    static PDSAdminHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSAdminHandler alloc] init];
    });
    return shared;
}

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                        path:(NSString *)path
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                        body:(nullable NSData *)body {
    PDSAdminAuth *auth = [PDSAdminAuth sharedAuth];

    if (![path isEqualToString:@"/admin/login"] && ![auth isAuthenticatedWithRequest:headers]) {
        return [self jsonResponseWithStatus:401 body:@{@"error": @"Unauthorized"}];
    }

    if ([path isEqualToString:@"/admin"]) {
        return [self handleAdminIndex:headers body:body];
    } else if ([path isEqualToString:@"/admin/login"]) {
        return [self handleAdminLogin:headers body:body];
    } else if ([path isEqualToString:@"/admin/logout"]) {
        return [self handleAdminLogout:headers body:body];
    } else if ([path isEqualToString:@"/admin/users"]) {
        return [self handleAdminUsers:headers body:body];
    } else if ([path isEqualToString:@"/admin/invites"]) {
        return [self handleAdminInvites:headers body:body];
    } else if ([path isEqualToString:@"/admin/blobs"]) {
        return [self handleAdminBlobs:headers body:body];
    } else if ([path isEqualToString:@"/admin/metrics"]) {
        return [self handleAdminMetrics:headers body:body];
    } else if ([path isEqualToString:@"/admin/health"]) {
        return [self handleAdminHealth:headers body:body];
    }

    return nil;
}

- (NSString *)handleAdminIndex:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"message": @"PDS Admin Dashboard",
        @"version": @"1.0.0",
        @"endpoints": @[
            @"/admin/users",
            @"/admin/invites",
            @"/admin/blobs",
            @"/admin/metrics",
            @"/admin/health"
        ]
    }];
}

- (NSString *)handleAdminLogin:(NSDictionary *)headers body:(NSData *)body {
    if (!body) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"Missing request body"}];
    }

    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&error];
    if (error || ![json isKindOfClass:[NSDictionary class]]) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"Invalid JSON"}];
    }

    NSString *password = json[@"password"];
    if (!password) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"Missing password"}];
    }

    NSError *authError = nil;
    BOOL success = [[PDSAdminAuth sharedAuth] authenticateWithPassword:password error:&authError];

    if (success) {
        return [self jsonResponseWithStatus:200 body:@{@"message": @"Login successful"}];
    } else {
        return [self jsonResponseWithStatus:401 body:@{@"error": authError.localizedDescription ?: @"Invalid password"}];
    }
}

- (NSString *)handleAdminLogout:(NSDictionary *)headers body:(NSData *)body {
    [[PDSAdminAuth sharedAuth] logout];
    return [self jsonResponseWithStatus:200 body:@{@"message": @"Logged out"}];
}

- (NSString *)handleAdminUsers:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"users": @[
            @{
                @"did": @"did:plc:ewvi7nxzyoun6zhxrhs64oiz",
                @"handle": @"user.example.com",
                @"email": @"user@example.com",
                @"email_confirmed": @YES,
                @"deactivated": @NO,
                @"created_at": @"2026-01-01T00:00:00Z"
            },
            @{
                @"did": @"did:plc:7HjwGtP5cLyq3vD5nDzDgXYZ",
                @"handle": @"admin.example.com",
                @"email": @"admin@example.com",
                @"email_confirmed": @YES,
                @"deactivated": @NO,
                @"created_at": @"2025-12-15T00:00:00Z"
            }
        ],
        @"total": @2
    }];
}

- (NSString *)handleAdminInvites:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"invites": @[
            @{
                @"code": @"ABCD-1234-EFGH-5678",
                @"created_by": @"admin@example.com",
                @"uses": @0,
                @"max_uses": @1,
                @"disabled": @NO,
                @"created_at": @"2026-01-01T00:00:00Z"
            },
            @{
                @"code": @"WXYZ-9012-RSTU-3456",
                @"created_by": @"admin@example.com",
                @"uses": @2,
                @"max_uses": @5,
                @"disabled": @NO,
                @"expires_at": @"2026-02-01T00:00:00Z",
                @"created_at": @"2025-12-20T00:00:00Z"
            }
        ],
        @"total": @2
    }];
}

- (NSString *)handleAdminBlobs:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"blobs": @[],
        @"total": @0
    }];
}

- (NSString *)handleAdminMetrics:(NSDictionary *)headers body:(NSData *)body {
    NSString *accept = headers[@"Accept"] ?: headers[@"accept"] ?: @"";
    PDSMetrics *metrics = [PDSMetrics sharedMetrics];

    if ([accept containsString:@"text/plain"] || [accept containsString:@"*/*"]) {
        return [self textResponseWithStatus:200 body:[metrics exportPrometheus]];
    }

    return [self jsonResponseWithStatus:200 body:@{
        @"http_requests_total": @([[PDSMetrics sharedMetrics] httpRequestsTotal]),
        @"repository_count": @([[PDSMetrics sharedMetrics] repositoryCount]),
        @"blob_count": @([[PDSMetrics sharedMetrics] blobCount]),
        @"blob_storage_bytes": @([[PDSMetrics sharedMetrics] blobStorageBytes]),
        @"active_connections": @([[PDSMetrics sharedMetrics] activeConnections])
    }];
}

- (NSString *)handleAdminHealth:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"status": @"ok",
        @"checks": @{
            @"database": @{
                @"status": @"ok",
                @"latency_ms": @5
            },
            @"storage": @{
                @"status": @"ok"
            },
            @"memory": @{
                @"status": @"ok"
            }
        }
    }];
}

- (NSString *)jsonResponseWithStatus:(NSInteger)status body:(NSDictionary *)body {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    if (error) {
        return [NSString stringWithFormat:@"HTTP/1.1 %ld\r\nContent-Type: text/plain\r\n\r\nInternal Error", (long)status];
    }
    return [NSString stringWithFormat:@"HTTP/1.1 %ld\r\nContent-Type: application/json\r\nContent-Length: %lu\r\n\r\n%@",
            (long)status, (unsigned long)data.length, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
}

- (NSString *)textResponseWithStatus:(NSInteger)status body:(NSString *)body {
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:@"HTTP/1.1 %ld\r\nContent-Type: text/plain\r\nContent-Length: %lu\r\n\r\n%@",
            (long)status, (unsigned long)data.length, body];
}

@end

NS_ASSUME_NONNULL_END
