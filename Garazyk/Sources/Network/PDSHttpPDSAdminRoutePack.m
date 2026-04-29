#import "Network/PDSHttpPDSAdminRoutePack.h"

#import "Admin/PDSAdminAuth.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

static NSString *PDSAdminPathParameter(HttpRequest *request, NSString *key) {
    NSString *value = request.pathParameters[key];
    if (![value isKindOfClass:[NSString class]]) {
        return @"";
    }
    NSString *decoded = [value stringByRemovingPercentEncoding];
    return decoded.length > 0 ? decoded : value;
}

static BOOL PDSAdminAuthorize(HttpRequest *request, HttpResponse *response) {
    NSError *authError = nil;
    if ([[PDSAdminAuth sharedAuth] authenticateHeaders:request.headers error:&authError]) {
        return YES;
    }

    NSInteger statusCode = authError.code;
    if (statusCode < 400 || statusCode > 599) {
        statusCode = HttpStatusUnauthorized;
    }
    response.statusCode = statusCode;
    [response setJsonBody:@{
        @"error": statusCode == HttpStatusForbidden ? @"Forbidden" : @"Unauthorized",
        @"message": authError.localizedDescription ?: @"Admin authentication required"
    }];
    return NO;
}

static BOOL PDSAdminRequireDatabases(PDSServiceDatabases *serviceDatabases,
                                     HttpResponse *response) {
    if (serviceDatabases) {
        return YES;
    }
    response.statusCode = HttpStatusServiceUnavailable;
    [response setJsonBody:@{
        @"error": @"ServiceUnavailable",
        @"message": @"Service databases are not configured"
    }];
    return NO;
}

@implementation PDSHttpPDSAdminRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases {
    PDSServiceDatabases *capturedServiceDatabases = serviceDatabases;

    [server addRoute:@"GET"
                path:@"/admin/api/accounts/:did/sessions"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *did = PDSAdminPathParameter(request, @"did");
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"DID is required"}];
            return;
        }

        NSError *error = nil;
        NSArray<NSDictionary *> *sessions = [databases listRefreshTokenSessionsForAccountDid:did error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SessionListFailed", @"message": error.localizedDescription ?: @"Failed to list sessions"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"sessions": sessions ?: @[]}];
    }];

    [server addRoute:@"POST"
                path:@"/admin/api/accounts/:did/sessions/revoke"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *did = PDSAdminPathParameter(request, @"did");
        NSString *sessionID = request.jsonBody[@"id"];
        if (did.length == 0 || sessionID.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"DID and session id are required"}];
            return;
        }

        NSError *error = nil;
        BOOL revoked = [databases revokeRefreshTokenSessionForAccountDid:did sessionID:sessionID error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"SessionRevokeFailed", @"message": error.localizedDescription ?: @"Failed to revoke session"}];
            return;
        }
        if (!revoked) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"SessionNotFound", @"message": @"Session not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [server addRoute:@"GET"
                path:@"/admin/api/accounts/:did/app-passwords"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *did = PDSAdminPathParameter(request, @"did");
        if (did.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"DID is required"}];
            return;
        }

        NSError *error = nil;
        NSArray<NSDictionary *> *storedPasswords = [databases listAppPasswordsForAccount:did error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"AppPasswordListFailed", @"message": error.localizedDescription ?: @"Failed to list app passwords"}];
            return;
        }

        NSMutableArray<NSDictionary *> *passwords = [NSMutableArray arrayWithCapacity:storedPasswords.count];
        for (NSDictionary *password in storedPasswords ?: @[]) {
            NSMutableDictionary *entry = [password mutableCopy];
            entry[@"did"] = did;
            [passwords addObject:[entry copy]];
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"passwords": passwords ?: @[]}];
    }];

    [server addRoute:@"POST"
                path:@"/admin/api/accounts/:did/app-passwords"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *did = PDSAdminPathParameter(request, @"did");
        NSDictionary *body = request.jsonBody ?: @{};
        NSString *name = body[@"name"];
        BOOL privileged = [body[@"privileged"] respondsToSelector:@selector(boolValue)] ? [body[@"privileged"] boolValue] : NO;
        if (did.length == 0 || name.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"DID and app password name are required"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *created = [databases createAppPasswordForAccount:did
                                                                  name:name
                                                            privileged:privileged
                                                                 error:&error];
        if (!created) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"AppPasswordCreateFailed", @"message": error.localizedDescription ?: @"Failed to create app password"}];
            return;
        }

        NSMutableDictionary *result = [created mutableCopy];
        result[@"did"] = did;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:[result copy]];
    }];

    [server addRoute:@"POST"
                path:@"/admin/api/accounts/:did/app-passwords/revoke"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *did = PDSAdminPathParameter(request, @"did");
        NSString *name = request.jsonBody[@"name"];
        if (did.length == 0 || name.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"DID and app password name are required"}];
            return;
        }

        NSError *error = nil;
        BOOL revoked = [databases revokeAppPasswordForAccount:did name:name error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"AppPasswordRevokeFailed", @"message": error.localizedDescription ?: @"Failed to revoke app password"}];
            return;
        }
        if (!revoked) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"AppPasswordNotFound", @"message": @"App password not found"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [server addRoute:@"GET"
                path:@"/admin/api/video/jobs"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *stateFilter = [request queryParamForKey:@"state"];
        if (stateFilter.length == 0) stateFilter = nil;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSUInteger limit = limitStr.length > 0 ? (NSUInteger)limitStr.integerValue : 25;
        if (limit == 0 || limit > 100) limit = 25;

        NSString *cursorStr = [request queryParamForKey:@"cursor"];
        NSUInteger offset = cursorStr.length > 0 ? (NSUInteger)cursorStr.integerValue : 0;

        NSError *error = nil;
        PDSDatabase *db = [databases serviceDatabaseWithError:&error];
        if (!db) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"DatabaseUnavailable", @"message": error.localizedDescription ?: @"Failed to acquire database"}];
            return;
        }

        NSArray<NSDictionary *> *jobs = [db listVideoJobsWithState:stateFilter limit:limit offset:offset error:&error];
        if (error) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"VideoJobListFailed", @"message": error.localizedDescription ?: @"Failed to list video jobs"}];
            return;
        }

        NSString *nextCursor = nil;
        if (jobs.count >= limit) {
            nextCursor = [NSString stringWithFormat:@"%lu", (unsigned long)(offset + limit)];
        }

        NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:jobs ?: @[] forKey:@"jobs"];
        if (nextCursor) body[@"cursor"] = nextCursor;

        response.statusCode = HttpStatusOK;
        [response setJsonBody:[body copy]];
    }];

    [server addRoute:@"POST"
                path:@"/admin/api/video/jobs/:jobId/retry"
             handler:^(HttpRequest *request, HttpResponse *response) {
        if (!PDSAdminAuthorize(request, response)) return;
        PDSServiceDatabases *databases = capturedServiceDatabases;
        if (!PDSAdminRequireDatabases(databases, response)) return;

        NSString *jobId = PDSAdminPathParameter(request, @"jobId");
        if (jobId.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Job ID is required"}];
            return;
        }

        NSError *error = nil;
        PDSDatabase *db = [databases serviceDatabaseWithError:&error];
        if (!db) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"DatabaseUnavailable", @"message": error.localizedDescription ?: @"Failed to acquire database"}];
            return;
        }

        BOOL success = [db incrementVideoJobRetry:jobId error:&error];
        if (!success) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"VideoJobRetryFailed", @"message": error.localizedDescription ?: @"Failed to retry video job"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

@end
