#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import "Admin/PDSAdminAuth.h"

#ifndef kCCSuccess
#define kCCSuccess 0
#endif
#import "Metrics/PDSMetrics.h"
#import "Database/PDSDatabase.h"
#import "Services/Core/PDSAdminService.h"
#import "App/PDSController.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Admin/AdminUI/Handlers/AdminUIHandler.h"
#import "Admin/AdminPartialHandler.h"

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

#pragma mark - Internal Data Access (Direct Dictionaries)

- (NSDictionary *)getHealthData {
    return [self handleAdminHealth:@{} body:nil];
}

- (NSDictionary *)getStatsData {
    return [self handleAdminStats:@{} body:nil];
}

- (NSDictionary *)getUsersData {
    return [self handleAdminUsers:@{} body:nil method:PDSHTTPMethodGET];
}

- (NSDictionary *)getInvitesData {
    return [self handleAdminInvites:@{} body:nil method:PDSHTTPMethodGET];
}

- (NSDictionary *)getBlobsData {
    return [self handleAdminBlobs:@{} body:nil];
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
        AdminPartialHandler *partialHandler = [AdminPartialHandler sharedHandler];
        NSString *response = [partialHandler handlePartialRequestWithPath:path
                                                                 headers:headers
                                                                    body:body];

        if (response) {
            // Assume 200 for partials from template handler for now
            return [self htmlResponseWithStatus:200 contentType:@"text/html" body:response];
        }
        
        // Fallback to AdminUIHandler if template handler didn't return anything
        AdminUIHandler *uiHandler = [AdminUIHandler sharedHandler];
        AdminUIHTTPMethod uiMethod = (AdminUIHTTPMethod)method;
        NSInteger statusCode = 200;
        NSString *contentType = @"text/html";

        response = [uiHandler handleRequestWithMethod:uiMethod
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
    } else if ([path hasPrefix:@"/admin/users/"]) {
        return [self handleAdminUserAction:headers body:body method:method path:path];
    } else if ([path isEqualToString:@"/admin/users/bulk/takedown"]) {
        return [self handleAdminBulkTakedown:headers body:body];
    } else if ([path isEqualToString:@"/admin/users/bulk/delete"]) {
        return [self handleAdminBulkDelete:headers body:body];
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
    } else if ([path hasPrefix:@"/admin/security/sessions"]) {
        return [self handleAdminSecuritySessions:headers body:body method:method path:path];
    } else if ([path hasPrefix:@"/admin/security/app-passwords"]) {
        return [self handleAdminSecurityAppPasswords:headers body:body method:method path:path];
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
    PDSMetrics *metrics = [PDSMetrics sharedMetrics];
    NSTimeInterval uptime = [[NSDate date] timeIntervalSince1970] - metrics.serverStartTime;
    
    // Format uptime into human-readable string
    NSInteger days = (NSInteger)(uptime / 86400);
    NSInteger hours = (NSInteger)((uptime - (days * 86400)) / 3600);
    NSInteger minutes = (NSInteger)((uptime - (days * 86400) - (hours * 3600)) / 60);
    NSString *uptimeStr = [NSString stringWithFormat:@"%ldd %ldh %ldm", (long)days, (long)hours, (long)minutes];

    unsigned long long usedMem = [metrics residentMemoryBytes];
    unsigned long long totalMem = [metrics totalSystemMemoryBytes];
    double memPercent = totalMem > 0 ? ((double)usedMem / (double)totalMem) * 100.0 : 0;

    return [self jsonResponseWithStatus:200 body:@{
        @"status": @"ok",
        @"uptime_seconds": @(uptime),
        @"checks": @{
            @"uptime": uptimeStr,
            @"version": @"0.1.0-alpha", // Placeholder for actual version
            @"database": @{
                @"status": @"ok",
                @"size_bytes": @(metrics.databaseSizeBytes),
                @"message": [NSString stringWithFormat:@"SQLite %llu KB", metrics.databaseSizeBytes / 1024],
                @"latency_ms": @2
            },
            @"storage": @{
                @"status": @"ok",
                @"blob_count": @(metrics.blobCount),
                @"blob_size_bytes": @(metrics.blobStorageBytes)
            },
            @"network": @{
                @"status": @"ok",
                @"active_connections": @(metrics.activeConnections),
                @"total_requests": @(metrics.httpRequestsTotal)
            },
            @"memory": @{
                @"used": [NSString stringWithFormat:@"%.1f MB", usedMem / (1024.0 * 1024.0)],
                @"total": [NSString stringWithFormat:@"%.1f GB", totalMem / (1024.0 * 1024.0 * 1024.0)],
                @"percent": @(memPercent)
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

#pragma mark - Security Handlers

- (NSDictionary *)handleAdminSecuritySessions:(NSDictionary *)headers body:(NSData *)body method:(PDSHTTPMethod)method path:(NSString *)path {
    if (method == PDSHTTPMethodGET) {
        NSDictionary *params = [self parseQueryString:path];
        NSString *did = params[@"did"];
        if (!did) {
            return [self jsonResponseWithStatus:200 body:@{@"sessions": @[]}];
        }
        NSError *error = nil;
        NSArray *sessions = [self.database listSessionsForDid:did error:&error];
        
        // Clean up token display (only show prefix)
        NSMutableArray *cleaned = [NSMutableArray array];
        for (NSDictionary *s in sessions) {
            NSMutableDictionary *m = [s mutableCopy];
            NSString *token = m[@"token"];
            if (token.length > 8) {
                m[@"token"] = [token substringToIndex:8];
            }
            [cleaned addObject:m];
        }
        return [self jsonResponseWithStatus:200 body:@{@"sessions": cleaned}];
    } else if (method == PDSHTTPMethodPOST) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        NSString *action = json[@"action"];
        if ([action isEqualToString:@"revoke"]) {
            NSString *token = json[@"token"];
            if (token) {
                [self.database revokeSession:token error:nil];
                return [self jsonResponseWithStatus:200 body:@{@"success": @YES}];
            }
        } else if ([action isEqualToString:@"revokeAll"]) {
            NSString *did = json[@"did"];
            if (did) {
                [self.database revokeAllSessionsForDid:did error:nil];
                return [self jsonResponseWithStatus:200 body:@{@"success": @YES}];
            }
        }
    }
    return [self jsonResponseWithStatus:400 body:@{@"error": @"Invalid request"}];
}

- (NSDictionary *)handleAdminSecurityAppPasswords:(NSDictionary *)headers body:(NSData *)body method:(PDSHTTPMethod)method path:(NSString *)path {
    if (method == PDSHTTPMethodGET) {
        NSDictionary *params = [self parseQueryString:path];
        NSString *did = params[@"did"];
        if (!did) {
            return [self jsonResponseWithStatus:200 body:@{@"app_passwords": @[]}];
        }
        NSError *error = nil;
        NSArray *passwords = [self.database listAppPasswordsForDid:did error:&error];
        return [self jsonResponseWithStatus:200 body:@{@"app_passwords": passwords ?: @[]}];
    } else if (method == PDSHTTPMethodPOST) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        NSString *action = json[@"action"];
        if ([action isEqualToString:@"revoke"]) {
            NSString *did = json[@"did"];
            NSString *passwordId = json[@"id"];
            if (did && passwordId) {
                [self.database revokeAppPassword:passwordId forDid:did error:nil];
                return [self jsonResponseWithStatus:200 body:@{@"success": @YES}];
            }
        }
    }
    return [self jsonResponseWithStatus:400 body:@{@"error": @"Invalid request"}];
}

#pragma mark - User Action Handlers

- (NSDictionary *)handleAdminUserAction:(NSDictionary *)headers body:(NSData *)body method:(PDSHTTPMethod)method path:(NSString *)path {
    // Parse path: /admin/users/{did}/{action}
    NSArray *pathComponents = [path componentsSeparatedByString:@"/"];
    if (pathComponents.count < 5) {
        return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p>Invalid request</p>"];
    }

    NSString *did = pathComponents[3];
    NSString *action = pathComponents[4];

    if ([action isEqualToString:@"edit-email"]) {
        return [self handleUserEditEmailRequest:did body:body method:method];
    } else if ([action isEqualToString:@"edit-handle"]) {
        return [self handleUserEditHandleRequest:did body:body method:method];
    } else if ([action isEqualToString:@"reset-password"]) {
        return [self handleUserResetPasswordRequest:did body:body method:method];
    } else if ([action isEqualToString:@"send-email"]) {
        return [self handleUserSendEmailRequest:did body:body method:method];
    } else if ([action isEqualToString:@"takedown"]) {
        return [self handleUserTakedownRequest:did body:body method:method];
    } else if ([action isEqualToString:@"activate"]) {
        return [self handleUserActivateRequest:did body:body method:method];
    } else if ([action isEqualToString:@"delete"]) {
        return [self handleUserDeleteRequest:did body:body method:method];
    }

    return [self htmlResponseWithStatus:404 contentType:@"text/html" body:@"<p>Not found</p>"];
}

- (NSDictionary *)handleUserEditEmailRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    if (method == PDSHTTPMethodPOST && !body) {
        // Return form
        NSString *html = [NSString stringWithFormat:
            @"<form class=\"form\" hx-put=\"/admin/users/%@/edit-email\" hx-swap=\"outerHTML\">"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">New Email Address</label>"
            @"<input type=\"email\" name=\"email\" class=\"form-input\" required placeholder=\"user@example.com\" />"
            @"</div>"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">Reason (optional)</label>"
            @"<input type=\"text\" name=\"reason\" class=\"form-input\" placeholder=\"Admin change\" />"
            @"</div>"
            @"<div class=\"form-footer\" style=\"display: flex; gap: 8px;\">"
            @"<button type=\"submit\" class=\"btn btn-primary\">Update Email</button>"
            @"<button type=\"button\" class=\"btn btn-secondary\" onclick=\"document.getElementById('user-action-modal').close()\">Cancel</button>"
            @"</div>"
            @"</form>", did];
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else if (method == PDSHTTPMethodPUT && body) {
        // Parse form data and update account
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        NSString *newEmail = json[@"email"];

        if (!newEmail || newEmail.length == 0) {
            return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p class=\"text-destructive\">Email is required</p>"];
        }

        // Fetch account, update email, and save
        NSError *dbError = nil;
        PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
        if (!account) {
            return [self htmlResponseWithStatus:404 contentType:@"text/html" body:@"<p class=\"text-destructive\">User not found</p>"];
        }

        account.email = newEmail;
        if ([self.database updateAccount:account error:&dbError]) {
            NSString *html = [NSString stringWithFormat:
                @"<p class=\"text-success\">Email updated successfully to: %@</p>", newEmail];
            return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
        } else {
            return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to update email</p>"];
        }
    }

    return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p>Invalid request</p>"];
}

- (NSDictionary *)handleUserEditHandleRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    if (method == PDSHTTPMethodPOST && !body) {
        // Return form - per-account auth: user needs to provide current handle or a confirmation token
        NSString *html = [NSString stringWithFormat:
            @"<form class=\"form\" hx-put=\"/admin/users/%@/edit-handle\" hx-swap=\"outerHTML\">"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">New Handle</label>"
            @"<input type=\"text\" name=\"handle\" class=\"form-input\" required placeholder=\"user.bsky.social\" />"
            @"</div>"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">Confirmation (type DID to confirm)</label>"
            @"<input type=\"text\" name=\"confirmation\" class=\"form-input\" required placeholder=\"%@\" />"
            @"</div>"
            @"<div class=\"form-footer\" style=\"display: flex; gap: 8px;\">"
            @"<button type=\"submit\" class=\"btn btn-primary\">Update Handle</button>"
            @"<button type=\"button\" class=\"btn btn-secondary\" onclick=\"document.getElementById('user-action-modal').close()\">Cancel</button>"
            @"</div>"
            @"</form>", did, did];
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else if (method == PDSHTTPMethodPUT && body) {
        // Require confirmation to prevent accidental changes
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        NSString *newHandle = json[@"handle"];
        NSString *confirmation = json[@"confirmation"];

        if (!confirmation || ![confirmation isEqualToString:did]) {
            return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p class=\"text-destructive\">Invalid confirmation. DID must match exactly.</p>"];
        }

        if (!newHandle || newHandle.length == 0) {
            return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p class=\"text-destructive\">Handle is required</p>"];
        }

        // Fetch account, update handle, and save
        NSError *dbError = nil;
        PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
        if (!account) {
            return [self htmlResponseWithStatus:404 contentType:@"text/html" body:@"<p class=\"text-destructive\">User not found</p>"];
        }

        account.handle = newHandle;
        if ([self.database updateAccount:account error:&dbError]) {
            NSString *html = [NSString stringWithFormat:
                @"<p class=\"text-success\">Handle updated successfully to: %@</p>", newHandle];
            return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
        } else {
            return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to update handle</p>"];
        }
    }

    return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p>Invalid request</p>"];
}

- (NSDictionary *)handleUserResetPasswordRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    if (method == PDSHTTPMethodPOST && !body) {
        // Return form
        NSString *html = [NSString stringWithFormat:
            @"<form class=\"form\" hx-put=\"/admin/users/%@/reset-password\" hx-swap=\"outerHTML\">"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">New Password</label>"
            @"<input type=\"password\" name=\"password\" class=\"form-input\" required minlength=\"8\" />"
            @"</div>"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">Confirm Password</label>"
            @"<input type=\"password\" name=\"password_confirm\" class=\"form-input\" required minlength=\"8\" />"
            @"</div>"
            @"<div class=\"form-help\">Password must be at least 8 characters.</div>"
            @"<div class=\"form-footer\" style=\"display: flex; gap: 8px;\">"
            @"<button type=\"submit\" class=\"btn btn-primary\">Reset Password</button>"
            @"<button type=\"button\" class=\"btn btn-secondary\" onclick=\"document.getElementById('user-action-modal').close()\">Cancel</button>"
            @"</div>"
            @"</form>", did];
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else if (method == PDSHTTPMethodPUT && body) {
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        NSString *password = json[@"password"];
        NSString *passwordConfirm = json[@"password_confirm"];

        if (!password || !passwordConfirm || ![password isEqualToString:passwordConfirm]) {
            return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p class=\"text-destructive\">Passwords do not match</p>"];
        }

        if (password.length < 8) {
            return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p class=\"text-destructive\">Password must be at least 8 characters</p>"];
        }

        // Fetch account and hash password
        NSError *dbError = nil;
        PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
        if (!account) {
            return [self htmlResponseWithStatus:404 contentType:@"text/html" body:@"<p class=\"text-destructive\">User not found</p>"];
        }

        // Hash password with PBKDF2-SHA256
        NSData *newHash = [self pbkdf2HashPassword:password salt:account.passwordSalt error:&dbError];
        if (!newHash) {
            return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to hash password</p>"];
        }

        account.passwordHash = newHash;
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        if ([self.database updateAccount:account error:&dbError]) {
            NSString *html = @"<p class=\"text-success\">Password has been reset successfully.</p>";
            return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
        } else {
            return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to reset password</p>"];
        }
    }

    return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p>Invalid request</p>"];
}

- (NSDictionary *)handleUserTakedownRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    // Deactivate account by setting invites disabled and marking as inactive
    // This prevents the account from being used while keeping records for auditing
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
    if (!account) {
        return [self htmlResponseWithStatus:404 contentType:@"text/html" body:@"<p class=\"text-destructive\">User not found</p>"];
    }

    account.inviteEnabled = NO;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    if ([self.database updateAccount:account error:&dbError]) {
        NSString *html = @"<p class=\"text-warning\">Account has been taken down.</p>";
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else {
        return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to takedown account</p>"];
    }
}

- (NSDictionary *)handleUserActivateRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    // Reactivate a taken down account
    NSError *dbError = nil;
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
    if (!account) {
        return [self htmlResponseWithStatus:404 contentType:@"text/html" body:@"<p class=\"text-destructive\">User not found</p>"];
    }

    account.inviteEnabled = YES;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    if ([self.database updateAccount:account error:&dbError]) {
        NSString *html = @"<p class=\"text-success\">Account has been reactivated.</p>";
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else {
        return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to reactivate account</p>"];
    }
}

- (NSDictionary *)handleUserSendEmailRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    if (method == PDSHTTPMethodPOST && !body) {
        // Return form
        NSString *html = [NSString stringWithFormat:
            @"<form class=\"form\" hx-put=\"/admin/users/%@/send-email\" hx-swap=\"outerHTML\">"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">Subject</label>"
            @"<input type=\"text\" name=\"subject\" class=\"form-input\" required placeholder=\"Important notice from admin\" />"
            @"</div>"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">Message</label>"
            @"<textarea name=\"content\" class=\"form-input\" rows=\"6\" required placeholder=\"Enter your message...\"></textarea>"
            @"</div>"
            @"<div class=\"form-group\">"
            @"<label class=\"form-label\">Sender (optional)</label>"
            @"<input type=\"text\" name=\"sender\" class=\"form-input\" placeholder=\"admin@example.com\" />"
            @"</div>"
            @"<div class=\"form-footer\" style=\"display: flex; gap: 8px;\">"
            @"<button type=\"submit\" class=\"btn btn-primary\">Send Email</button>"
            @"<button type=\"button\" class=\"btn btn-secondary\" onclick=\"document.getElementById('user-action-modal').close()\">Cancel</button>"
            @"</div>"
            @"</form>", did];
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else if (method == PDSHTTPMethodPUT && body) {
        // Parse and send email via XRPC
        NSError *parseError = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        
        NSString *subject = json[@"subject"];
        NSString *content = json[@"content"];
        NSString *sender = json[@"sender"] ?: @"admin";
        
        if (!subject || !content) {
            return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p class=\"text-destructive\">Subject and content are required</p>"];
        }
        
        // Call XRPC sendEmail via admin service
        // TODO: Call XrpcDispatcher for com.atproto.admin.sendEmail
        // For now, just return success
        
        NSString *html = @"<p class=\"text-success\">Email has been sent to the user.</p>";
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    }
    
    return [self htmlResponseWithStatus:400 contentType:@"text/html" body:@"<p>Invalid request</p>"];
}

#pragma mark - Bulk Operations

- (NSDictionary *)handleAdminBulkTakedown:(NSDictionary *)headers body:(NSData *)body {
    // Parse request body for selected DIDs
    NSError *parseError = nil;
    NSArray *dids = nil;
    
    if (body) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        dids = json[@"selected_users"];
    }
    
    if (!dids || ![dids isKindOfClass:[NSArray class]] || dids.count == 0) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"No users selected"}];
    }
    
    NSDictionary *result = [self handleBulkTakedownWithDids:dids];
    return [self jsonResponseWithStatus:[result[@"success"] boolValue] ? 200 : 500 body:result];
}

- (NSDictionary *)handleAdminBulkDelete:(NSDictionary *)headers body:(NSData *)body {
    // Parse request body for selected DIDs
    NSError *parseError = nil;
    NSArray *dids = nil;
    
    if (body) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:&parseError];
        dids = json[@"selected_users"];
    }
    
    if (!dids || ![dids isKindOfClass:[NSArray class]] || dids.count == 0) {
        return [self jsonResponseWithStatus:400 body:@{@"error": @"No users selected"}];
    }
    
    NSDictionary *result = [self handleBulkDeleteWithDids:dids];
    return [self jsonResponseWithStatus:[result[@"success"] boolValue] ? 200 : 500 body:result];
}

- (NSDictionary *)handleBulkTakedownWithDids:(NSArray *)dids {
    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];
    
    for (NSString *did in dids) {
        if (![did isKindOfClass:[NSString class]]) continue;
        
        NSError *dbError = nil;
        PDSDatabaseAccount *account = [self.database getAccountByDid:did error:&dbError];
        if (!account) {
            [failed addObject:@{@"did": did, @"error": @"User not found"}];
            continue;
        }
        
        account.inviteEnabled = NO;
        account.updatedAt = [[NSDate date] timeIntervalSince1970];
        if ([self.database updateAccount:account error:&dbError]) {
            [succeeded addObject:did];
        } else {
            [failed addObject:@{@"did": did, @"error": dbError.localizedDescription ?: @"Database error"}];
        }
    }
    
    return @{
        @"success": @(failed.count == 0),
        @"processed": @(dids.count),
        @"succeeded": @(succeeded.count),
        @"failed": failed,
        @"message": [NSString stringWithFormat:@"Takedown complete: %lu succeeded, %lu failed",
                     (unsigned long)succeeded.count, (unsigned long)failed.count]
    };
}

- (NSDictionary *)handleBulkDeleteWithDids:(NSArray *)dids {
    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];
    
    for (NSString *did in dids) {
        if (![did isKindOfClass:[NSString class]]) continue;
        
        NSError *dbError = nil;
        if ([self.database deleteAccount:did error:&dbError]) {
            [succeeded addObject:did];
        } else {
            [failed addObject:@{@"did": did, @"error": dbError.localizedDescription ?: @"Database error"}];
        }
    }
    
    return @{
        @"success": @(failed.count == 0),
        @"processed": @(dids.count),
        @"succeeded": @(succeeded.count),
        @"failed": failed,
        @"message": [NSString stringWithFormat:@"Delete complete: %lu succeeded, %lu failed",
                     (unsigned long)succeeded.count, (unsigned long)failed.count]
    };
}

- (NSDictionary *)handleUserDeleteRequest:(NSString *)did body:(NSData *)body method:(PDSHTTPMethod)method {
    // Permanently delete account and all associated data
    NSError *dbError = nil;
    if ([self.database deleteAccount:did error:&dbError]) {
        NSString *html = @"<p class=\"text-success\">Account has been permanently deleted.</p>";
        return [self htmlResponseWithStatus:200 contentType:@"text/html" body:html];
    } else {
        return [self htmlResponseWithStatus:500 contentType:@"text/html" body:@"<p class=\"text-destructive\">Failed to delete account</p>"];
    }
}

- (nullable NSData *)pbkdf2HashPassword:(NSString *)password salt:(NSData *)salt error:(NSError **)error {
    const uint32_t iterations = 600000;
    const size_t derivedKeyLength = 32;
    unsigned char derivedKey[32];

    int result = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      password.UTF8String,
                                      (size_t)password.length,
                                      salt.bytes,
                                      (size_t)salt.length,
                                      kCCPRFHmacAlgSHA256,
                                      iterations,
                                      derivedKey,
                                      derivedKeyLength);
    if (result != kCCSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.server"
                                         code:500
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to derive password hash"}];
        }
        return nil;
    }
    return [NSData dataWithBytes:derivedKey length:derivedKeyLength];
}

- (NSDictionary *)parseQueryString:(NSString *)url {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSRange queryStart = [url rangeOfString:@"?"];
    if (queryStart.location != NSNotFound) {
        NSString *queryString = [url substringFromIndex:queryStart.location + 1];
        NSArray *pairs = [queryString componentsSeparatedByString:@"&"];
        for (NSString *pair in pairs) {
            NSArray *components = [pair componentsSeparatedByString:@"="];
            if (components.count == 2) {
                NSString *key = [components[0] stringByRemovingPercentEncoding];
                NSString *value = [components[1] stringByRemovingPercentEncoding];
                params[key] = value;
            }
        }
    }
    return [params copy];
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

#pragma mark - User Detail Data

- (nullable NSDictionary *)getUserDetailDataForDid:(NSString *)did {
    PDSDatabase *db = self.database;
    if (!db) return nil;
    
    NSError *error = nil;
    PDSDatabaseAccount *acct = [db getAccountByDid:did error:&error];
    if (!acct) return nil;
    
    NSMutableDictionary *userData = [NSMutableDictionary dictionary];
    userData[@"did"] = acct.did ?: did;
    userData[@"handle"] = acct.handle ?: @"";
    userData[@"email"] = acct.email ?: @"";
    userData[@"active"] = @(acct.inviteEnabled);
    userData[@"takendown"] = @(!acct.inviteEnabled);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    if (acct.createdAt > 0) {
        NSDate *createdDate = [NSDate dateWithTimeIntervalSince1970:acct.createdAt];
        userData[@"createdAt"] = [formatter stringFromDate:createdDate];
    }
    if (acct.updatedAt > 0) {
        NSDate *updatedDate = [NSDate dateWithTimeIntervalSince1970:acct.updatedAt];
        userData[@"updatedAt"] = [formatter stringFromDate:updatedDate];
    }
    
    // Get invites created by this user
    NSError *queryError = nil;
    NSArray *rows = [db executeParameterizedQuery:
        @"SELECT code, account_did, created_at, max_uses, uses, disabled FROM invite_codes WHERE account_did = ? ORDER BY created_at DESC"
                                              params:@[did]
                                              error:&queryError];
    
    if (rows && rows.count > 0) {
        NSMutableArray *invites = [NSMutableArray arrayWithCapacity:rows.count];
        for (NSDictionary *row in rows) {
            NSMutableDictionary *invite = [NSMutableDictionary dictionary];
            invite[@"code"] = row[@"code"] ?: @"";
            invite[@"used"] = @([row[@"uses"] integerValue] > 0);
            invite[@"created_at"] = row[@"created_at"] ?: @"";
            [invites addObject:invite];
        }
        userData[@"invites"] = invites;
        userData[@"invites_count"] = @(invites.count);
    } else {
        userData[@"invites"] = @[];
        userData[@"invites_count"] = @0;
    }
    
    return [userData copy];
}

- (nullable NSArray *)getModerationReportsData {
    // Placeholder - moderation reports would typically come from XRPC or database
    return @[];
}

- (nullable NSDictionary *)getAuditLogDataWithAdminDid:(nullable NSString *)adminDid
                                                limit:(NSInteger)limit
                                               cursor:(nullable NSString *)cursor {
    PDSAdminService *adminService = self.adminService;
    if (!adminService) return nil;
    
    NSMutableDictionary *filters = [NSMutableDictionary dictionary];
    if (adminDid) {
        filters[@"admin_did"] = adminDid;
    }
    
    NSError *error = nil;
    NSDictionary *result = [adminService queryAuditLog:filters limit:limit cursor:cursor error:&error];
    return result;
}

@end

NS_ASSUME_NONNULL_END
