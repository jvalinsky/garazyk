// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+PLC.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (PLC)

- (NSDictionary *)lookupDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/%@", did] queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !response) {
        GZ_LOG_DEBUG(@"PLC Lookup failed for URL: %@, status: %ld, error: %@, response: %@", url, (long)status, error, response);
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
    id response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"plc_list_failed", @"message": error.localizedDescription ?: @"PLC list fetch failed"};
    }
    if ([response isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)response;
        if ([dict[@"dids"] isKindOfClass:[NSArray class]]) {
            return dict;
        }
        if ([dict[@"items"] isKindOfClass:[NSArray class]]) {
            return @{@"dids": dict[@"items"]};
        }
        return dict;
    }
    return @{@"dids": @[]};
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

@end
