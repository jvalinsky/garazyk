// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIPLCPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIPLCPack

+ (NSString *)packIdentifier {
    return @"plc";
}

+ (NSString *)displayName {
    return @"PLC";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"plc", @"displayName": @"PLC"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerPLCRoutes];
}

+ (NSString *)renderPLCDIDPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"did", @"handle", @"service", @"rotationKeys", @"alsoKnownAs", @"createdAt"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSArray class]]) {
            NSString *joined = [((NSArray *)val) componentsJoinedByString:@", "];
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value text-mono text-xs\">%@</span></div>", key, GZAdminUIEscaped(joined)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? GZAdminUIEscaped(val) : GZAdminUIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value text-mono text-xs\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)renderPLCLogPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *entries = [result[@"log"] isKindOfClass:[NSArray class]] ? result[@"log"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Seq</th><th>Type</th><th>Time</th><th>Detail</th></tr></thead><tbody>"];
    for (NSDictionary *entry in entries) {
        NSString *seq = GZAdminUIEscaped([entry[@"seq"] stringValue] ?: @"");
        NSString *type = GZAdminUIEscaped(entry[@"type"] ?: @"");
        NSString *time = GZAdminUIEscaped(entry[@"createdAt"] ?: @"");
        NSString *detail = GZAdminUIEscaped(entry[@"detail"] ?: @"");
        [html appendFormat:@"<tr><td>%@</td><td><span class=\"badge badge-secondary\">%@</span></td><td class=\"text-xs text-mono\">%@</td><td class=\"text-xs\">%@</td></tr>", seq, type, time, detail];
    }
    if (entries.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No log entries.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)renderPLCHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"status"] = status;
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    return [GZAdminUITemplateEngine renderTemplate:@"plc-health" context:ctx];
}

+ (NSString *)renderPLCMetricsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (!ctx[@"text"]) ctx[@"text"] = @"";
    return [GZAdminUITemplateEngine renderTemplate:@"plc-metrics" context:ctx];
}

+ (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (cursor) ctx[@"cursor"] = cursor;
    if (result[@"dids"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSString *did in result[@"dids"]) {
            [mapped addObject:@{@"did": did}];
        }
        ctx[@"mappedDids"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"plc-list" context:ctx];
}

@end
