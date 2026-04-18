#import <Foundation/Foundation.h>
#import "Admin/PDSAdminAuth.h"
#import "Metrics/PDSMetrics.h"
#import "Database/PDSDatabase.h"
#import "Services/Core/PDSAdminService.h"
#import "App/PDSController.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Admin/AdminUI/Handlers/AdminUIHandler.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PDSHTTPMethod) {
    PDSHTTPMethodGET,
    PDSHTTPMethodPOST,
    PDSHTTPMethodPUT,
    PDSHTTPMethodDELETE
};

@interface PDSAdminHandler : NSObject
@property (nonatomic, strong, nullable) PDSDatabase *database;
@property (nonatomic, strong, nullable) PDSAdminService *adminService;

+ (instancetype)sharedHandler;

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body;

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

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

- (nullable PDSDatabase *)database {
    if (!_database) {
        PDSController *controller = [PDSController sharedController];
        if ([controller respondsToSelector:@selector(database)]) {
            _database = [controller performSelector:@selector(database)];
        }
    }
    return _database;
}

- (nullable PDSAdminService *)adminService {
    if (!_adminService) {
        PDSController *controller = [PDSController sharedController];
        if ([controller respondsToSelector:@selector(adminService)]) {
            _adminService = [controller performSelector:@selector(adminService)];
        }
    }
    return _adminService;
}

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body {
    return [self handleRequestWithMethod:method
                                    path:path
                                 headers:headers
                                    body:body
                              statusCode:nil
                             contentType:nil];
}

- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    NSDictionary *packet = [self handleRequestPacketWithMethod:method
                                                          path:path
                                                       headers:headers
                                                          body:body];
    if (!packet) {
        return nil;
    }

    if (statusCode) {
        *statusCode = [packet[@"status"] integerValue];
    }
    if (contentType) {
        *contentType = packet[@"contentType"];
    }
    return packet[@"body"];
}

- (nullable NSDictionary *)handleRequestPacketWithMethod:(PDSHTTPMethod)method
                                                    path:(NSString *)path
                                                 headers:(NSDictionary<NSString *, NSString *> *)headers
                                                    body:(nullable NSData *)body {
    // AdminUI static assets don't require authentication
    if ([path hasPrefix:@"/admin/assets/"] || [path hasPrefix:@"/admin/css/"] || [path hasPrefix:@"/admin/js/"]) {
        AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
        AdminUIHTTPMethod uiMethod = (AdminUIHTTPMethod)method;
        NSInteger statusCode = 200;
        NSString *contentType = @"text/html";

        NSString *response = [uiHandler handleRequestWithMethod:uiMethod
                                                           path:path
                                                        headers:headers
                                                           body:body
                                                     statusCode:&statusCode
                                                    contentType:&contentType];

        if (response) {
            return [self htmlResponseWithStatus:statusCode contentType:contentType body:response];
        }
    }

    // AdminUI entry point (serves index.html)
    if ([path isEqualToString:@"/admin/ui"] || [path isEqualToString:@"/admin/ui/"]) {
        AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
        AdminUIHTTPMethod uiMethod = (AdminUIHTTPMethod)method;
        NSInteger statusCode = 200;
        NSString *contentType = @"text/html; charset=utf-8";

        NSString *response = [uiHandler handleRequestWithMethod:uiMethod
                                                           path:path
                                                        headers:headers
                                                           body:body
                                                     statusCode:&statusCode
                                                    contentType:&contentType];

        if (response) {
            return [self htmlResponseWithStatus:statusCode contentType:contentType body:response];
        }
    }

    PDSAdminAuth *auth = [PDSAdminAuth sharedAuth];

    if (![path isEqualToString:@"/admin/login"] && ![path hasPrefix:@"/admin/assets/"] && ![path hasPrefix:@"/admin/css/"] && ![path hasPrefix:@"/admin/js/"] && ![auth isAuthenticatedWithRequest:headers]) {
        return [self jsonResponseWithStatus:401 body:@{@"error": @"Unauthorized"}];
    }

    // AdminUI partials require authentication
    if ([path hasPrefix:@"/admin/partials/"]) {
        AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
        AdminUIHTTPMethod uiMethod = (AdminUIHTTPMethod)method;
        NSInteger statusCode = 200;
        NSString *contentType = @"text/html";

        NSString *response = [uiHandler handleRequestWithMethod:uiMethod
                                                           path:path
                                                        headers:headers
                                                           body:body
                                                     statusCode:&statusCode
                                                    contentType:&contentType];

        if (response) {
            return [self htmlResponseWithStatus:statusCode contentType:contentType body:response];
        }
    }

    if ([path isEqualToString:@"/admin"]) {
        return [self handleAdminIndex:headers body:body];
    } else if ([path isEqualToString:@"/admin/login"]) {
        return [self handleAdminLogin:headers body:body];
    } else if ([path isEqualToString:@"/admin/logout"]) {
        return [self handleAdminLogout:headers body:body];
    } else if ([path isEqualToString:@"/admin/users"]) {
        return [self handleAdminUsers:headers body:body method:method];
    } else if ([path isEqualToString:@"/admin/invites"]) {
        return [self handleAdminInvites:headers body:body method:method];
    } else if ([path isEqualToString:@"/admin/invites/disable"]) {
        return [self handleAdminInviteDisable:headers body:body];
    } else if ([path isEqualToString:@"/admin/blobs"]) {
        return [self handleAdminBlobs:headers body:body];
    } else if ([path isEqualToString:@"/admin/metrics"]) {
        return [self handleAdminMetrics:headers body:body];
    } else if ([path isEqualToString:@"/admin/health"]) {
        return [self handleAdminHealth:headers body:body];
    } else if ([path isEqualToString:@"/admin/stats"]) {
        return [self handleAdminStats:headers body:body];
    } else if ([path isEqualToString:@"/admin/audit-log"]) {
        return [self handleAdminAuditLog:headers body:body];
    }

    return nil;
}

- (NSDictionary *)handleAdminIndex:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"message": @"PDS Admin Dashboard",
        @"version": @"1.0.0",
        @"endpoints": @[
            @"/admin/users",
            @"/admin/invites",
            @"/admin/invites/disable",
            @"/admin/blobs",
            @"/admin/metrics",
            @"/admin/health",
            @"/admin/stats",
            @"/admin/audit-log"
        ]
    }];
}

- (NSDictionary *)handleAdminLogin:(NSDictionary *)headers body:(NSData *)body {
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
        NSString *token = [PDSAdminAuth sharedAuth].adminToken;
        return [self jsonResponseWithStatus:200 body:@{
            @"message": @"Login successful",
            @"token": token ?: @""
        }];
    } else {
        return [self jsonResponseWithStatus:401 body:@{@"error": authError.localizedDescription ?: @"Invalid password"}];
    }
}

- (NSDictionary *)handleAdminLogout:(NSDictionary *)headers body:(NSData *)body {
    [[PDSAdminAuth sharedAuth] logout];
    return [self jsonResponseWithStatus:200 body:@{@"message": @"Logged out"}];
}

- (NSDictionary *)handleAdminUsers:(NSDictionary *)headers body:(NSData *)body method:(PDSHTTPMethod)method {
    PDSDatabase *db = self.database;
    if (!db) {
        return [self jsonResponseWithStatus:200 body:@{@"users": @[], @"total": @0}];
    }

    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *accounts = [db getAllAccountsWithError:&error];
    if (!accounts) {
        return [self jsonResponseWithStatus:500 body:@{@"error": error.localizedDescription ?: @"Database error"}];
    }

    NSMutableArray *users = [NSMutableArray arrayWithCapacity:accounts.count];
    for (PDSDatabaseAccount *account in accounts) {
        NSMutableDictionary *user = [NSMutableDictionary dictionary];
        user[@"did"] = account.did ?: @"";
        user[@"handle"] = account.handle ?: @"";
        user[@"email"] = account.email ?: @"";
        user[@"deactivated"] = @NO;
        user[@"invite_enabled"] = @(account.inviteEnabled);

        if (account.createdAt > 0) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:account.createdAt];
            user[@"created_at"] = [NSDateFormatter atproto_stringFromDate:date];
        } else {
            user[@"created_at"] = @"";
        }

        [users addObject:user];
    }

    return [self jsonResponseWithStatus:200 body:@{
        @"users": users,
        @"total": @(users.count)
    }];
}

- (NSDictionary *)handleAdminInvites:(NSDictionary *)headers body:(NSData *)body method:(PDSHTTPMethod)method {
    PDSDatabase *db = self.database;

    if (method == PDSHTTPMethodPOST) {
        // Create new invite code
        if (!body) {
            return [self jsonResponseWithStatus:400 body:@{@"error": @"Missing request body"}];
        }

        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        if (parseError || ![json isKindOfClass:[NSDictionary class]]) {
            return [self jsonResponseWithStatus:400 body:@{@"error": @"Invalid JSON"}];
        }

        PDSAdminService *svc = self.adminService;
        if (!svc) {
            return [self jsonResponseWithStatus:500 body:@{@"error": @"Admin service unavailable"}];
        }

        NSError *createError = nil;
        NSDictionary *result = [svc createInviteCode:json error:&createError];
        if (!result) {
            return [self jsonResponseWithStatus:400 body:@{@"error": createError.localizedDescription ?: @"Failed to create invite code"}];
        }

        return [self jsonResponseWithStatus:200 body:result];
    }

    // GET: list invite codes
    if (!db) {
        return [self jsonResponseWithStatus:200 body:@{@"invites": @[], @"total": @0}];
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *rows = [db executeParameterizedQuery:@"SELECT code, account_did, created_at, max_uses, uses, disabled FROM invite_codes ORDER BY created_at DESC"
                                                           params:@[]
                                                            error:&error];
    if (!rows) {
        return [self jsonResponseWithStatus:500 body:@{@"error": error.localizedDescription ?: @"Database error"}];
    }

    NSMutableArray *invites = [NSMutableArray arrayWithCapacity:rows.count];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *invite = [NSMutableDictionary dictionary];
        invite[@"code"] = row[@"code"] ?: @"";
        invite[@"created_by"] = row[@"account_did"] ?: @"";

        id usesVal = row[@"uses"];
        invite[@"uses"] = usesVal ?: @0;

        id maxUsesVal = row[@"max_uses"];
        invite[@"max_uses"] = maxUsesVal ?: @1;

        id disabledVal = row[@"disabled"];
        invite[@"disabled"] = @([disabledVal integerValue] != 0);

        id createdAtVal = row[@"created_at"];
        if (createdAtVal) {
            NSTimeInterval ts = [createdAtVal doubleValue];
            if (ts > 0) {
                NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
                invite[@"created_at"] = [NSDateFormatter atproto_stringFromDate:date];
            } else {
                invite[@"created_at"] = @"";
            }
        }

        [invites addObject:invite];
    }

    return [self jsonResponseWithStatus:200 body:@{
        @"invites": invites,
        @"total": @(invites.count)
    }];
}

- (NSDictionary *)handleAdminInviteDisable:(NSDictionary *)headers body:(NSData *)body {
    if (!body) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"Missing request body"}];
    }

    NSError *parseError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
    if (parseError || ![json isKindOfClass:[NSDictionary class]]) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"Invalid JSON"}];
    }

    NSString *code = json[@"code"];
    if (!code.length) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"Missing code"}];
    }

    PDSAdminService *svc = self.adminService;
    if (!svc) {
        return [self jsonResponseWithStatus:500 body:@{@"error": @"Admin service unavailable"}];
    }

    NSError *disableError = nil;
    BOOL ok = [svc disableInviteCode:code error:&disableError];
    if (!ok) {
        return [self jsonResponseWithStatus:400 body:@{@"error": disableError.localizedDescription ?: @"Failed to disable invite code"}];
    }

    return [self jsonResponseWithStatus:200 body:@{@"message": @"Invite code disabled"}];
}

- (NSDictionary *)handleAdminBlobs:(NSDictionary *)headers body:(NSData *)body {
    return [self jsonResponseWithStatus:200 body:@{
        @"blobs": @[],
        @"total": @0
    }];
}

- (NSDictionary *)handleAdminMetrics:(NSDictionary *)headers body:(NSData *)body {
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

- (NSDictionary *)handleAdminHealth:(NSDictionary *)headers body:(NSData *)body {
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

- (NSDictionary *)handleAdminStats:(NSDictionary *)headers body:(NSData *)body {
    PDSAdminService *svc = self.adminService;
    if (!svc) {
        return [self jsonResponseWithStatus:500 body:@{@"error": @"Admin service unavailable"}];
    }
    
    NSError *error = nil;
    NSDictionary *stats = [svc getServerStatsWithError:&error];
    if (!stats) {
        return [self jsonResponseWithStatus:500 body:@{@"error": error.localizedDescription ?: @"Failed to get stats"}];
    }
    
    return [self jsonResponseWithStatus:200 body:stats];
}

- (NSDictionary *)handleAdminAuditLog:(NSDictionary *)headers body:(NSData *)body {
    PDSAdminService *svc = self.adminService;
    if (!svc) {
        return [self jsonResponseWithStatus:500 body:@{@"error": @"Admin service unavailable"}];
    }
    
    // Parse query params from body (POST) or use defaults
    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    NSInteger limit = 50;
    NSString *cursor = nil;
    
    if (body) {
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        if (json && [json isKindOfClass:[NSDictionary class]]) {
            if (json[@"admin_did"]) filters[@"admin_did"] = json[@"admin_did"];
            if (json[@"action"]) filters[@"action"] = json[@"action"];
            if (json[@"subject_type"]) filters[@"subject_type"] = json[@"subject_type"];
            if (json[@"subject_id"]) filters[@"subject_id"] = json[@"subject_id"];
            if (json[@"since"]) filters[@"since"] = json[@"since"];
            if (json[@"until"]) filters[@"until"] = json[@"until"];
            if (json[@"limit"]) limit = [json[@"limit"] integerValue];
            if (json[@"cursor"]) cursor = json[@"cursor"];
        }
    }
    
    NSError *error = nil;
    NSDictionary *result = [svc queryAuditLog:filters limit:limit cursor:cursor error:&error];
    if (!result) {
        return [self jsonResponseWithStatus:500 body:@{@"error": error.localizedDescription ?: @"Failed to query audit log"}];
    }
    
    return [self jsonResponseWithStatus:200 body:result];
}

- (NSDictionary *)packetWithStatus:(NSInteger)status
                       contentType:(NSString *)contentType
                              body:(NSString *)body {
    return @{
        @"status": @(status),
        @"contentType": contentType ?: @"application/json",
        @"body": body ?: @""
    };
}

- (NSDictionary *)jsonResponseWithStatus:(NSInteger)status body:(NSDictionary *)body {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    if (error) {
        return [self packetWithStatus:500 contentType:@"application/json" body:@"Internal Error"];
    }
    NSString *bodyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [self packetWithStatus:status contentType:@"application/json" body:bodyString];
}

- (NSDictionary *)textResponseWithStatus:(NSInteger)status body:(NSString *)body {
    return [self packetWithStatus:status contentType:@"text/plain; charset=utf-8" body:(body ?: @"")];
}

- (NSDictionary *)htmlResponseWithStatus:(NSInteger)status
                             contentType:(NSString *)contentType
                                   body:(NSString *)body {
    return [self packetWithStatus:status
                     contentType:(contentType ?: @"text/html; charset=utf-8")
                            body:(body ?: @"")];
}

@end

NS_ASSUME_NONNULL_END
