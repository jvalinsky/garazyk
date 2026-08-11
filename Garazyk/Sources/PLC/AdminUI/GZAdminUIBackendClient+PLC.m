// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLC/AdminUI/GZAdminUIBackendClient+PLC.h"
#import "AdminUIServer/GZAdminUIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"

@implementation GZAdminUIBackendClient (PLC)

- (NSDictionary *)lookupDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/%@", did] queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0; NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    return (status >= 200 && status < 300 && response) ? response : @{@"error": @"plc_lookup_failed", @"message": error.localizedDescription ?: @"DID lookup failed"};
}

- (NSDictionary *)fetchPLCLogForDID:(NSString *)did {
    if (did.length == 0) return @{@"error": @"invalid_did", @"message": @"DID required"};
    NSURL *url = [self URLByAppendingPath:[NSString stringWithFormat:@"/%@/log", did] queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0; NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    return (status >= 200 && status < 300 && response) ? response : @{@"error": @"plc_log_failed", @"message": error.localizedDescription ?: @"PLC log fetch failed"};
}

- (NSDictionary *)fetchPLCHealth {
    NSURL *url = [self URLByAppendingPath:@"/_health" queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0; NSError *error = nil;
    NSDictionary *response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    return (status >= 200 && status < 300) ? (response ?: @{@"status": @"ok"}) : @{@"error": @"plc_health_failed", @"message": error.localizedDescription ?: @"PLC health check failed"};
}

- (NSDictionary *)fetchPLCMetrics {
    NSURL *url = [self URLByAppendingPath:@"/_metrics" queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0; NSError *error = nil;
    NSData *data = [self performStringRequestWithURL:url method:@"GET" bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !data) return @{@"error": @"plc_metrics_failed", @"message": error.localizedDescription ?: @"PLC metrics fetch failed", @"text": @""};
    return @{@"text": [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @""};
}

- (NSDictionary *)fetchPLCList {
    NSURL *url = [self URLByAppendingPath:@"/_list" queryItems:nil baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0; NSError *error = nil;
    id response = [self performJSONRequestWithURL:url method:@"GET" body:nil bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300) return @{@"error": @"plc_list_failed", @"message": error.localizedDescription ?: @"PLC list fetch failed"};
    if ([response isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = response;
        if ([dictionary[@"dids"] isKindOfClass:[NSArray class]]) return dictionary;
        if ([dictionary[@"items"] isKindOfClass:[NSArray class]]) return @{@"dids": dictionary[@"items"]};
        return dictionary;
    }
    return @{@"dids": @[]};
}

- (NSDictionary *)fetchPLCExportWithAfter:(NSString *)after count:(NSUInteger)count {
    NSMutableDictionary *queryItems = [NSMutableDictionary dictionary];
    if (after.length > 0) queryItems[@"after"] = after;
    if (count > 0) queryItems[@"count"] = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    NSURL *url = [self URLByAppendingPath:@"/export" queryItems:queryItems baseURL:self.configuration.plcBaseURL];
    NSInteger status = 0; NSError *error = nil;
    NSData *data = [self performStringRequestWithURL:url method:@"GET" bearerToken:self.configuration.plcAdminToken statusCode:&status error:&error];
    if (status < 200 || status >= 300 || !data) return @{@"error": @"plc_export_failed", @"message": error.localizedDescription ?: @"PLC export fetch failed", @"text": @""};
    return @{@"text": [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @""};
}

@end
