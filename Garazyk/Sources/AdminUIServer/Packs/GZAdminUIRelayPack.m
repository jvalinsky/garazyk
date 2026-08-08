// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIRelayPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIRelayPack

+ (NSString *)packIdentifier {
    return @"relay";
}

+ (NSString *)displayName {
    return @"Relay";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"relay", @"displayName": @"Relay"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerRelayRoutes];
}

+ (NSString *)renderRelayMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];

    NSDictionary *metrics = result[@"metrics"] ?: result;
    for (NSString *key in metrics) {
        if (![metrics[key] isKindOfClass:[NSString class]] && ![metrics[key] isKindOfClass:[NSNumber class]]) continue;
        NSString *val = [metrics[key] description];
        [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">%@</span><span class=\"metric-value\">%@</span></div>", UIEscaped(key), UIEscaped(val)];
    }
    if (metrics.count == 0) {
        [html appendString:@"<div class=\"text-center text-secondary p-lg\">No metrics found.</div>"];
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)renderRelayUpstreamsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *upstreams = [result[@"upstreams"] isKindOfClass:[NSArray class]] ? result[@"upstreams"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Hostname</th><th>Status</th><th>Seq</th><th>Last Connected</th></tr></thead><tbody>"];
    for (NSDictionary *upstream in upstreams) {
        NSString *hostname = UIEscaped(upstream[@"hostname"] ?: @"");
        NSString *status = UIEscaped(upstream[@"status"] ?: @"");
        NSString *seq = UIEscaped([upstream[@"seq"] stringValue] ?: @"0");
        NSString *lastConnected = UIEscaped(upstream[@"lastConnected"] ?: @"");
        NSString *statusBadge = [status isEqualToString:@"connected"] ? @"badge badge-success" : @"badge badge-secondary";
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td><span class=\"%@\">%@</span></td><td>%@</td><td class=\"text-xs\">%@</td></tr>", hostname, statusBadge, status, seq, lastConnected];
    }
    if (upstreams.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No upstreams found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)renderRelayHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"status"] = status;
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : ([status isEqualToString:@"error"] ? @"badge badge-destructive" : @"badge badge-secondary");
    NSString *checkedAt = result[@"checkedAt"] ?: result[@"lastChecked"] ?: @"";
    if (checkedAt.length > 0) ctx[@"checkedAt"] = checkedAt;
    else [ctx removeObjectForKey:@"checkedAt"];
    return [UITemplateEngine renderTemplate:@"relay-health" context:ctx];
}

@end
