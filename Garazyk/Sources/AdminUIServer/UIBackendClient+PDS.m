// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+PDS.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (PDS)

- (BOOL)refreshPDSAdminToken {
    NSString *password = self.configuration.pdsAdminPassword;
    if (password.length == 0) {
        return NO;
    }

    NSURL *url = [self URLByAppendingPath:@"/admin/login"
                               queryItems:nil
                                  baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"password": password};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                     method:@"POST"
                                                       body:body
                                                  bearerToken:nil
                                                   statusCode:&status
                                                        error:&error];
    if (status == 200 && response[@"token"]) {
        self.configuration.pdsAdminToken = response[@"token"];
        return YES;
    }
    return NO;
}

- (NSDictionary *)fetchServiceOverview {
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("com.garazyk.service.probes", DISPATCH_QUEUE_CONCURRENT);

    NSMutableArray<NSDictionary *> *services = [NSMutableArray array];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);

    NSArray<NSDictionary *> *probeSpecs = [self serviceProbeSpecifications];

    for (NSDictionary *spec in probeSpecs) {
        dispatch_group_enter(group);
        dispatch_async(queue, ^{
            NSString *name = spec[@"name"];
            NSURL *baseURL = spec[@"baseURL"];
            id xrpcPath = spec[@"xrpcPath"];
            id tokenValue = spec[@"token"];
            NSString *token = [tokenValue isKindOfClass:[NSNull class]] ? nil : tokenValue;

            NSDictionary *result = [self probeServiceNamed:name
                                                   baseURL:baseURL
                                                 xrpcPath:[xrpcPath isKindOfClass:[NSNull class]] ? nil : xrpcPath
                                             bearerToken:token];

            dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC));
            [services addObject:result];
            dispatch_semaphore_signal(semaphore);

            dispatch_group_leave(group);
        });
    }

    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50.0 * NSEC_PER_SEC)));

    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSString *generatedAt = [formatter stringFromDate:[NSDate date]];
    return @{@"services": services, @"generatedAt": generatedAt ?: @""};
}

- (NSDictionary *)testConnectionForService:(NSString *)serviceName {
    NSString *normalized = [[serviceName ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    for (NSDictionary *spec in [self serviceProbeSpecifications]) {
        if ([[spec[@"name"] lowercaseString] isEqualToString:normalized]) {
            id tokenValue = spec[@"token"];
            NSString *token = [tokenValue isKindOfClass:[NSNull class]] ? nil : tokenValue;
            return [self probeServiceNamed:spec[@"name"]
                                   baseURL:spec[@"baseURL"]
                                  xrpcPath:spec[@"xrpcPath"]
                               bearerToken:token];
        }
    }
    return @{@"name": normalized ?: @"", @"status": @"error", @"error": @"Unknown service"};
}

- (NSDictionary *)testConnectionForService:(NSString *)serviceName
                                   baseURL:(NSURL *)baseURL
                                adminToken:(nullable NSString *)adminToken {
    NSString *normalized = [[serviceName ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    for (NSDictionary *spec in [self serviceProbeSpecifications]) {
        if ([[spec[@"name"] lowercaseString] isEqualToString:normalized]) {
            return [self probeServiceNamed:spec[@"name"]
                                   baseURL:baseURL
                                  xrpcPath:spec[@"xrpcPath"]
                               bearerToken:adminToken];
        }
    }
    return @{@"name": normalized ?: @"", @"status": @"error", @"error": @"Unknown service"};
}

- (NSDictionary *)searchAccountsWithQuery:(NSString *)query {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.searchAccounts"
                              queryItems:@{
                                @"limit": @"25",
                                @"q": query.length > 0 ? query : @""
                              }
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url
                                                      method:@"GET"
                                                        body:nil
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"pds_search_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Search request failed",
                 @"accounts": @[]};
    }
    NSMutableDictionary *result = [response mutableCopy];
    if (![result[@"accounts"] isKindOfClass:[NSArray class]]) {
        result[@"accounts"] = @[];
    }
    return [result copy];
}

- (NSDictionary *)fetchInviteCodes {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getInviteCodes"
                              queryItems:@{@"limit": @"25"}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url
                                                      method:@"GET"
                                                        body:nil
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"pds_invites_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Invite request failed",
                 @"codes": @[]};
    }
    NSMutableDictionary *result = [response mutableCopy];
    if (![result[@"codes"] isKindOfClass:[NSArray class]]) {
        result[@"codes"] = @[];
    }
    return [result copy];
}

- (NSDictionary *)disableInvitesForAccount:(NSString *)account {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @{@"error": @"invalid_account", @"message": @"Account DID is required"};
    }

    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.disableAccountInvites"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"account": trimmed};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url
                                                      method:@"POST"
                                                        body:body
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"disable_invites_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Disable invites failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchAccountInfoForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                              queryItems:@{@"did": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"account_info_failed", @"message": error.localizedDescription ?: @"Account info fetch failed"};
    }
    return response;
}

- (NSDictionary *)updateAccountHandle:(NSString *)handle forDID:(NSString *)did {
    if (did.length == 0 || handle.length == 0) return @{@"error": @"invalid_params", @"message": @"DID and handle required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.updateAccountHandle" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did, @"handle": handle};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"handle_update_failed", @"message": error.localizedDescription ?: @"Handle update failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteAccount:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.deleteAccount" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"account_delete_failed", @"message": error.localizedDescription ?: @"Account deletion failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)bulkTakedownAccounts:(NSArray<NSString *> *)dids {
    if (dids.count == 0) return @{@"error": @"invalid_params", @"message": @"No accounts specified"};
    
    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];
    
    for (NSString *did in dids) {
        NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.takeDownAccount" queryItems:nil baseURL:self.configuration.pdsBaseURL];
        NSDictionary *body = @{@"subject": @{@"$type": @"com.atproto.admin.defs#repoRef", @"did": did}};
        NSInteger status = 0;
        NSError *error = nil;
        [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
        
        if (status >= 200 && status < 300) {
            [succeeded addObject:did];
        } else {
            [failed addObject:@{@"did": did, @"error": error.localizedDescription ?: @"Request failed"}];
        }
    }
    
    return @{
        @"success": @(failed.count == 0),
        @"processed": @(dids.count),
        @"succeeded": @(succeeded.count),
        @"failed": failed,
        @"message": [NSString stringWithFormat:@"Bulk takedown complete: %lu succeeded, %lu failed",
                     (unsigned long)succeeded.count, (unsigned long)failed.count]
    };
}

- (NSDictionary *)bulkDeleteAccounts:(NSArray<NSString *> *)dids {
    if (dids.count == 0) return @{@"error": @"invalid_params", @"message": @"No accounts specified"};
    
    NSMutableArray *succeeded = [NSMutableArray array];
    NSMutableArray *failed = [NSMutableArray array];
    
    for (NSString *did in dids) {
        NSDictionary *result = [self deleteAccount:did];
        if (!result[@"error"]) {
            [succeeded addObject:did];
        } else {
            [failed addObject:@{@"did": did, @"error": result[@"message"]}];
        }
    }
    
    return @{
        @"success": @(failed.count == 0),
        @"processed": @(dids.count),
        @"succeeded": @(succeeded.count),
        @"failed": failed,
        @"message": [NSString stringWithFormat:@"Bulk delete complete: %lu succeeded, %lu failed",
                     (unsigned long)succeeded.count, (unsigned long)failed.count]
    };
}

- (NSDictionary *)enableInvitesForAccount:(NSString *)account {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @{@"error": @"invalid_account", @"message": @"Account DID is required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.enableAccountInvites" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"account": trimmed};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"enable_invites_failed", @"message": error.localizedDescription ?: @"Enable invites failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchServerStats {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getServerStats" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"server_stats_failed", @"message": error.localizedDescription ?: @"Server stats failed"};
    }
    return response;
}

- (NSDictionary *)fetchAuditLogWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.queryAuditLog" queryItems:params baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"audit_log_failed", @"message": error.localizedDescription ?: @"Audit log fetch failed"};
    }
    return response;
}

- (NSDictionary *)fetchReportsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getModerationReports" queryItems:params baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"reports_fetch_failed", @"message": error.localizedDescription ?: @"Reports fetch failed"};
    }
    return response;
}

- (NSDictionary *)resolveReport:(NSString *)reportID action:(NSString *)action {
    if (reportID.length == 0) return @{@"error": @"invalid_report", @"message": @"Report ID required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.resolveReport" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithObject:reportID forKey:@"id"];
    if (action.length > 0) body[@"action"] = action;
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"report_resolve_failed", @"message": error.localizedDescription ?: @"Report resolution failed"};
    }
    return response ?: @{};
}

@end
