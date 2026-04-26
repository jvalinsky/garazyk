#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"

@interface UIBackendClient ()

@property(nonatomic, strong) UIServiceConfig *configuration;

@end

@implementation UIBackendClient

- (instancetype)initWithConfiguration:(UIServiceConfig *)configuration {
    self = [super init];
    if (self) {
        _configuration = configuration;
    }
    return self;
}

- (NSDictionary *)fetchServiceOverview {
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("com.garazyk.service.probes", DISPATCH_QUEUE_CONCURRENT);

    NSMutableArray<NSDictionary *> *services = [NSMutableArray array];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);

    // Define probe specifications: name, baseURL, xrpcPath, token
    // Use NSNull for nil tokens to avoid dictionary literal crash
    NSArray<NSDictionary *> *probeSpecs = @[
        @{@"name": @"pds", @"baseURL": self.configuration.pdsBaseURL, @"xrpcPath": @"/xrpc/com.atproto.server.describeServer", @"token": self.configuration.pdsAdminToken ?: [NSNull null]},
        @{@"name": @"plc", @"baseURL": self.configuration.plcBaseURL, @"xrpcPath": [NSNull null], @"token": self.configuration.plcAdminToken ?: [NSNull null]},
        @{@"name": @"relay", @"baseURL": self.configuration.relayBaseURL, @"xrpcPath": @"/xrpc/com.atproto.sync.listRepos?limit=1", @"token": self.configuration.relayAdminToken ?: [NSNull null]},
        @{@"name": @"appview", @"baseURL": self.configuration.appViewBaseURL, @"xrpcPath": @"/xrpc/app.bsky.feed.getTimeline?limit=1", @"token": self.configuration.appViewAdminToken ?: [NSNull null]},
        @{@"name": @"chat", @"baseURL": self.configuration.chatBaseURL, @"xrpcPath": @"/xrpc/chat.bsky.convo.listConvos?limit=1", @"token": self.configuration.chatAdminToken ?: [NSNull null]}
    ];

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

            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
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

- (NSDictionary *)searchAccountsWithQuery:(NSString *)query {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.searchAccounts"
                              queryItems:@{
                                @"limit": @"25",
                                @"q": query.length > 0 ? query : @""
                              }
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                      method:@"GET"
                                                        body:nil
                                                 bearerToken:self.configuration.pdsAdminToken
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
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                      method:@"GET"
                                                        body:nil
                                                 bearerToken:self.configuration.pdsAdminToken
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
    NSDictionary *response = [self performJSONRequestWithURL:url
                                                      method:@"POST"
                                                        body:body
                                                 bearerToken:self.configuration.pdsAdminToken
                                                  statusCode:&status
                                                       error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"disable_invites_failed",
                 @"status": @(status),
                 @"message": error.localizedDescription ?: @"Disable invites failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchAppViewMetrics {
    NSURL *url = [self URLByAppendingPath:@"/admin/appview/metrics/stats" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"appview_metrics_failed", @"message": error.localizedDescription ?: @"AppView metrics failed"};
    }
    return response;
}

- (NSDictionary *)fetchIngestHealth {
    NSURL *url = [self URLByAppendingPath:@"/admin/ingest/health" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"ingest_health_failed", @"message": error.localizedDescription ?: @"Ingest health failed"};
    }
    return response;
}

- (NSDictionary *)fetchBackfillQueueWithStatus:(NSString *)status limit:(NSUInteger)limit cursor:(NSString *)cursor {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (status.length > 0) params[@"status"] = status;
    if (cursor.length > 0) params[@"cursor"] = cursor;
    
    NSURL *url = [self URLByAppendingPath:@"/admin/backfill/queue" queryItems:params baseURL:self.configuration.appViewBaseURL];
    NSInteger httpStatus = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&httpStatus error:&error];
    if (httpStatus < 200 || httpStatus >= 300 || !response) {
        return @{@"error": @"backfill_queue_failed", @"message": error.localizedDescription ?: @"Fetch backfill queue failed", @"entries": @[]};
    }
    return response;
}

- (NSDictionary *)retryBackfillForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/admin/backfill/repos/%@/retry", did] queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"backfill_retry_failed", @"message": error.localizedDescription ?: @"Retry failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)cancelBackfillForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/admin/backfill/repos/%@/cancel", did] queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"backfill_cancel_failed", @"message": error.localizedDescription ?: @"Cancel failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)enqueueBackfillDIDs:(NSArray<NSString *> *)dids {
    if (dids.count == 0) return @{@"error": @"invalid_dids", @"message": @"DIDs required"};
    NSURL *url = [self URLByAppendingPath:@"/admin/backfill/repos" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSDictionary *body = @{@"dids": dids};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"enqueue_failed", @"message": error.localizedDescription ?: @"Enqueue failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)rebuildBackfillScope {
    NSURL *url = [self URLByAppendingPath:@"/admin/backfill/scope/rebuild" queryItems:nil baseURL:self.configuration.appViewBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:nil bearerToken:self.configuration.appViewAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"rebuild_scope_failed", @"message": error.localizedDescription ?: @"Rebuild scope failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchRelayMetrics {
    NSURL *url = [self URLByAppendingPath:@"/api/relay/metrics" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"relay_metrics_failed", @"message": error.localizedDescription ?: @"Relay metrics failed"};
    }
    return response;
}

- (NSDictionary *)fetchRelayUpstreams {
    NSURL *url = [self URLByAppendingPath:@"/api/relay/upstreams" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"relay_upstreams_failed", @"message": error.localizedDescription ?: @"Relay upstreams failed"};
    }
    return response;
}

- (NSDictionary *)fetchRelayHealth {
    NSURL *url = [self URLByAppendingPath:@"/api/relay/health" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"relay_health_failed", @"message": error.localizedDescription ?: @"Relay health failed"};
    }
    return response;
}

- (NSDictionary *)requestCrawlForHostname:(NSString *)hostname {
    if (hostname.length == 0) return @{@"error": @"invalid_hostname", @"message": @"Hostname required"};
    NSURL *url = [self URLByAppendingPath:@"/api/relay/requestCrawl" queryItems:nil baseURL:self.configuration.relayBaseURL];
    NSDictionary *body = @{@"hostname": hostname};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.relayAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"crawl_request_failed", @"message": error.localizedDescription ?: @"Crawl request failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)lookupDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/%@", did] queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        NSLog(@"[DEBUG] PLC Lookup failed for URL: %@, status: %ld, error: %@, response: %@", url, (long)status, error, response);
        return @{@"error": @"plc_lookup_failed", @"message": error.localizedDescription ?: @"DID lookup failed"};
    }
    return response;
}

- (NSDictionary *)fetchPLCLogForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/%@/log", did] queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"plc_log_failed", @"message": error.localizedDescription ?: @"PLC log fetch failed"};
    }
    return response;
}

- (NSDictionary *)fetchPLCHealth {
    NSURL *url = [self URLByAppendingPath:@"/_health" queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"plc_health_failed", @"message": error.localizedDescription ?: @"PLC health check failed"};
    }
    return response ?: @{@"status": @"ok"};
}

- (NSDictionary *)fetchPLCMetrics {
    NSURL *url = [self URLByAppendingPath:@"/_metrics" queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"GET"];
    if (self.configuration.plcAdminToken) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.configuration.plcAdminToken] forHTTPHeaderField:@"Authorization"];
    }
    NSInteger status = 0;
    NSError *error = nil;
    NSData *data = [self performStringRequestWithURL:url method:@"GET" bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !data) {
        return @{@"error": @"plc_metrics_failed", @"message": error.localizedDescription ?: @"PLC metrics fetch failed", @"text": @""};
    }
    NSString *metricsText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return @{@"text": metricsText ?: @""};
}

- (NSDictionary *)fetchPLCList {
    NSURL *url = [self URLByAppendingPath:@"/_list" queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"plc_list_failed", @"message": error.localizedDescription ?: @"PLC list fetch failed"};
    }
    return response ?: @{@"dids": @[]};
}

- (NSDictionary *)fetchPLCExportWithAfter:(nullable NSString *)after count:(NSUInteger)count {
    NSMutableDictionary *queryItems = [NSMutableDictionary dictionary];
    if (after && after.length > 0) {
        queryItems[@"after"] = after;
    }
    if (count > 0) {
        queryItems[@"count"] = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    }
    NSURL *url = [self URLByAppendingPath:@"/export" queryItems:queryItems baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSData *data = [self performStringRequestWithURL:url method:@"GET" bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !data) {
        return @{@"error": @"plc_export_failed", @"message": error.localizedDescription ?: @"PLC export fetch failed", @"text": @""};
    }
    NSString *exportText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return @{@"text": exportText ?: @""};
}

- (NSDictionary *)fetchAccountInfoForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getAccountInfo"
                              queryItems:@{@"did": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
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
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
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
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
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
        [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
        
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
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"enable_invites_failed", @"message": error.localizedDescription ?: @"Enable invites failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchServerStats {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.admin.getServerStats" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
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
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
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
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
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
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"report_resolve_failed", @"message": error.localizedDescription ?: @"Report resolution failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)describeRepo:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.describeRepo"
                              queryItems:@{@"repo": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"describe_repo_failed", @"message": error.localizedDescription ?: @"Describe repo failed"};
    }
    return response;
}

- (NSDictionary *)listRecordsForDID:(NSString *)did collection:(NSString *)collection limit:(NSUInteger)limit cursor:(NSString *)cursor {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"repo"] = did;
    if (collection.length > 0) params[@"collection"] = collection;
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.listRecords" queryItems:params baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"list_records_failed", @"message": error.localizedDescription ?: @"List records failed"};
    }
    return response;
}

- (NSDictionary *)getRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey {
    if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID, collection, and rkey required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.getRecord"
                              queryItems:@{@"repo": did, @"collection": collection, @"rkey": rkey}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"get_record_failed", @"message": error.localizedDescription ?: @"Get record failed"};
    }
    return response;
}

- (NSDictionary *)fetchChatConvosWithLimit:(NSUInteger)limit cursor:(NSString *)cursor {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"limit"] = [@(limit ?: 25) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/chat.bsky.convo.listConvos" queryItems:params baseURL:self.configuration.chatBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.chatAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"chat_convos_failed", @"message": error.localizedDescription ?: @"Chat convos fetch failed"};
    }
    return response;
}

- (NSDictionary *)fetchChatMessagesForConvoID:(NSString *)convoID limit:(NSUInteger)limit cursor:(NSString *)cursor {
    if (!convoID.length) return @{@"error": @"convo_id_required"};
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"convoId"] = convoID;
    params[@"limit"] = [@(limit ?: 50) stringValue];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    NSURL *url = [self URLByAppendingPath:@"/xrpc/chat.bsky.convo.getMessages" queryItems:params baseURL:self.configuration.chatBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.chatAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"chat_messages_failed", @"message": error.localizedDescription ?: @"Chat messages fetch failed"};
    }
    return response;
}

- (NSDictionary *)lockChatConvo:(NSString *)convoID {
    if (!convoID.length) return @{@"error": @"convo_id_required"};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/chat.bsky.convo.muteConvo" queryItems:@{} baseURL:self.configuration.chatBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *body = @{@"convoId": convoID};
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.chatAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"lock_convo_failed", @"message": error.localizedDescription ?: @"Lock conversation failed"};
    }
    return response;
}

- (NSDictionary *)fetchBlobListWithLimit:(NSUInteger)limit cursor:(NSString *)cursor {
    // Currently no global blob list endpoint in ATProto admin lexicons.
    // Returning stub for UI consistency.
    return @{@"blobs": @[], @"total": @0, @"storage_bytes": @0};
}

- (NSDictionary *)fetchBlobForDID:(NSString *)did cid:(NSString *)cid {
    if (did.length == 0 || cid.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and CID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.sync.getBlob"
                              queryItems:@{@"did": did, @"cid": cid}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        return @{@"error": @"blob_fetch_failed", @"message": error.localizedDescription ?: @"Blob fetch failed"};
    }
    return response;
}

- (NSDictionary *)createRecordForDID:(NSString *)did collection:(NSString *)collection record:(NSDictionary *)record rkey:(NSString *)rkey {
    if (did.length == 0 || collection.length == 0 || !record) {
        return @{@"error": @"invalid_params", @"message": @"DID, collection, and record required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.createRecord" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"repo"] = did;
    body[@"collection"] = collection;
    body[@"record"] = record;
    if (rkey.length > 0) body[@"rkey"] = rkey;
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"create_record_failed", @"message": error.localizedDescription ?: @"Create record failed"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteRecordForDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey {
    if (did.length == 0 || collection.length == 0 || rkey.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID, collection, and rkey required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.repo.deleteRecord" queryItems:nil baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"repo": did, @"collection": collection, @"rkey": rkey};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_record_failed", @"message": error.localizedDescription ?: @"Delete record failed"};
    }
    return response ?: @{};
}

#pragma mark - Ozone Moderation Operations

- (NSDictionary *)fetchOzoneStatusesWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.queryStatuses"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_statuses_failed", @"message": error.localizedDescription ?: @"Failed to fetch statuses"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchOzoneEventsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.queryEvents"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_events_failed", @"message": error.localizedDescription ?: @"Failed to fetch events"};
    }
    return response ?: @{};
}

- (NSDictionary *)emitModerationEvent:(NSDictionary *)event {
    if (!event) {
        return @{@"error": @"invalid_params", @"message": @"Event required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.emitEvent"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:event bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"emit_event_failed", @"message": error.localizedDescription ?: @"Failed to emit event"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchSubjectStatusForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.getSubjectStatus"
                              queryItems:@{@"did": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"subject_status_failed", @"message": error.localizedDescription ?: @"Failed to fetch subject status"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchModerationReportsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.queryStatuses"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"moderation_reports_failed", @"message": error.localizedDescription ?: @"Failed to fetch reports"};
    }
    return response ?: @{};
}

#pragma mark - Ozone Team Operations

- (NSDictionary *)fetchOzoneTeamMembers {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.team.listMembers"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"team_members_failed", @"message": error.localizedDescription ?: @"Failed to fetch team members"};
    }
    return response ?: @{};
}

- (NSDictionary *)addOzoneTeamMember:(NSDictionary *)member {
    if (!member) {
        return @{@"error": @"invalid_params", @"message": @"Member info required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.team.addMember"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:member bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"add_member_failed", @"message": error.localizedDescription ?: @"Failed to add team member"};
    }
    return response ?: @{};
}

- (NSDictionary *)removeOzoneTeamMember:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.team.deleteMember"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"remove_member_failed", @"message": error.localizedDescription ?: @"Failed to remove team member"};
    }
    return response ?: @{};
}

#pragma mark - Ozone Set Operations

- (NSDictionary *)fetchOzoneSetsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.set.querySets"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_sets_failed", @"message": error.localizedDescription ?: @"Failed to fetch sets"};
    }
    return response ?: @{};
}

- (NSDictionary *)upsertOzoneSet:(NSDictionary *)setSpec {
    if (!setSpec) {
        return @{@"error": @"invalid_params", @"message": @"Set specification required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.set.upsertSet"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:setSpec bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"upsert_set_failed", @"message": error.localizedDescription ?: @"Failed to upsert set"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteOzoneSet:(NSString *)name {
    if (name.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"Set name required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.set.deleteSet"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"name": name};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_set_failed", @"message": error.localizedDescription ?: @"Failed to delete set"};
    }
    return response ?: @{};
}

#pragma mark - Ozone Template Operations

- (NSDictionary *)fetchOzoneTemplates {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.communication.listTemplates"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_templates_failed", @"message": error.localizedDescription ?: @"Failed to fetch templates"};
    }
    return response ?: @{};
}

- (NSDictionary *)createOzoneTemplate:(NSDictionary *)template {
    if (!template) {
        return @{@"error": @"invalid_params", @"message": @"Template required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.communication.createTemplate"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:template bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"create_template_failed", @"message": error.localizedDescription ?: @"Failed to create template"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteOzoneTemplate:(NSString *)name {
    if (name.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"Template name required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.communication.deleteTemplate"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"name": name};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_template_failed", @"message": error.localizedDescription ?: @"Failed to delete template"};
    }
    return response ?: @{};
}

#pragma mark - Ozone Configuration

- (NSDictionary *)fetchOzoneConfig {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.server.getConfig"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_config_failed", @"message": error.localizedDescription ?: @"Failed to fetch ozone config"};
    }
    return response ?: @{};
}

- (NSDictionary *)updateOzoneConfig:(NSDictionary *)config {
    if (!config) {
        return @{@"error": @"invalid_params", @"message": @"Config required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.server.updateConfig"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:config bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"update_config_failed", @"message": error.localizedDescription ?: @"Failed to update config"};
    }
    return response ?: @{};
}

#pragma mark - Security Operations

- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.server.listSessions"
                              queryItems:@{@"did": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"sessions_failed", @"message": error.localizedDescription ?: @"Failed to fetch sessions"};
    }
    return response ?: @{};
}

- (NSDictionary *)revokeSessionForDID:(NSString *)did sessionID:(NSString *)sessionID {
    if (did.length == 0 || sessionID.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and session ID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.server.revokeSession"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did, @"id": sessionID};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"revoke_session_failed", @"message": error.localizedDescription ?: @"Failed to revoke session"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.server.listAppPasswords"
                              queryItems:@{@"did": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"app_passwords_failed", @"message": error.localizedDescription ?: @"Failed to fetch app passwords"};
    }
    return response ?: @{};
}

- (NSDictionary *)createAppPasswordForDID:(NSString *)did name:(NSString *)passwordName {
    if (did.length == 0 || passwordName.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and name required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.server.createAppPassword"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did, @"name": passwordName};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"create_app_password_failed", @"message": error.localizedDescription ?: @"Failed to create app password"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteAppPasswordForDID:(NSString *)did passwordName:(NSString *)passwordName {
    if (did.length == 0 || passwordName.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID and name required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/com.atproto.server.revokeAppPassword"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did, @"name": passwordName};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"POST" body:body bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_app_password_failed", @"message": error.localizedDescription ?: @"Failed to delete app password"};
    }
    return response ?: @{};
}

#pragma mark - MST Viewer Operations

- (NSDictionary *)fetchMSTAccounts {
    NSURL *url = [self URLByAppendingPath:@"/api/mst/accounts"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"mst_accounts_failed", @"message": error.localizedDescription ?: @"Failed to fetch MST accounts"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchMSTTreeForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/api/mst/tree/%@", did]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"mst_tree_failed", @"message": error.localizedDescription ?: @"Failed to fetch MST tree"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchMSTStatsForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/api/mst/stats/%@", did]
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.pdsAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"mst_stats_failed", @"message": error.localizedDescription ?: @"Failed to fetch MST stats"};
    }
    return response ?: @{};
}

- (NSData *)fetchMSTExportForDID:(NSString *)did format:(NSString *)format {
    if (did.length == 0) {
        return nil;
    }
    NSString *formatParam = [format isEqualToString:@"dot"] ? @"dot" : [format isEqualToString:@"svg"] ? @"svg" : @"json";
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/api/mst/export/%@", did]
                              queryItems:@{@"format": formatParam}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSData *data = [self performRequestWithURL:url
                                        method:@"GET"
                                          body:nil
                                   contentType:nil
                                    bearerToken:self.configuration.pdsAdminToken
                                     statusCode:&status
                                          error:&error];
    if (status < 200 || status >= 300) {
        return nil;
    }
    return data;
}

#pragma mark - Private Helper Methods

- (NSData *)performStringRequestWithURL:(NSURL *)url method:(NSString *)method bearerToken:(nullable NSString *)token statusCode:(NSInteger *)statusCode error:(NSError **)error {
    return [self performRequestWithURL:url method:method body:nil contentType:nil bearerToken:token statusCode:statusCode error:error];
}

@end

