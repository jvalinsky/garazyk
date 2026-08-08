// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIDataExplorerPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"

@implementation GZAdminUIDataExplorerPack

+ (NSString *)packIdentifier {
    return @"explorer";
}

+ (NSString *)displayName {
    return @"Data Explorer";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    // Populated when the shell is made composable (WS11 M2 slice 4).
    return @[];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerDataExplorerRoutes];
}

+ (NSString *)renderDescribeRepoPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"handle", @"did", @"didDoc", @"collections", @"handleIsCorrect"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSArray class]]) {
            NSString *joined = [((NSArray *)val) componentsJoinedByString:@", "];
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value text-mono text-xs\">%@</span></div>", key, UIEscaped(joined)];
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:val options:0 error:nil];
            NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
            [html appendFormat:@"<div class=\"detail-field full-width\"><span class=\"detail-label\">%@</span><pre class=\"detail-value text-xs text-mono\">%@</pre></div>", key, UIEscaped(jsonStr)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)renderListRecordsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *records = [result[@"records"] isKindOfClass:[NSArray class]] ? result[@"records"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>URI</th><th>CID</th><th>Collection</th><th>Rkey</th></tr></thead><tbody>"];
    for (NSDictionary *record in records) {
        NSString *uri = UIEscaped(record[@"uri"] ?: @"");
        NSString *cid = UIEscaped(record[@"cid"] ?: @"");
        NSString *collection = UIEscaped(record[@"collection"] ?: @"");
        NSString *rkey = UIEscaped(record[@"rkey"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td></tr>", uri, cid, collection, rkey];
    }
    if (records.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No records found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/list-records?cursor=%@\" hx-target=\"#records-list\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

+ (NSString *)renderGetRecordPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"uri", @"cid", @"value"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSDictionary class]] || [val isKindOfClass:[NSArray class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:val options:NSJSONWritingPrettyPrinted error:nil];
            NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
            [html appendFormat:@"<div class=\"detail-field full-width\"><span class=\"detail-label\">%@</span><pre class=\"detail-value text-xs text-mono\">%@</pre></div>", key, UIEscaped(jsonStr)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? UIEscaped(val) : UIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

@end
