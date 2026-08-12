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
    return @[@{@"tabIdentifier": @"explorer", @"displayName": @"Data Explorer"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerDataExplorerRoutes];
}

+ (NSString *)renderDescribeRepoPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *repoDID = GZAdminUIStringFromDict(result, @"did");
    NSMutableString *html = [NSMutableString stringWithString:GZAdminUIDetailCardOpen()];
    NSArray<NSDictionary<NSString *, NSString *> *> *fields = @[
        @{@"key": @"handle", @"label": @"Handle"},
        @{@"key": @"did", @"label": @"DID"},
        @{@"key": @"handleIsCorrect", @"label": @"Handle is correct"},
        @{@"key": @"collections", @"label": @"Collections"},
        @{@"key": @"didDoc", @"label": @"DID document"},
    ];
    for (NSDictionary<NSString *, NSString *> *field in fields) {
        NSString *key = field[@"key"];
        id val = result[key];
        if (!val || val == [NSNull null]) {
            continue;
        }
        if ([key isEqualToString:@"collections"] && [val isKindOfClass:[NSArray class]]) {
            NSMutableString *chips = [NSMutableString stringWithString:@"<div class=\"detail-chips\">"];
            for (id item in (NSArray *)val) {
                NSString *collection = [item isKindOfClass:[NSString class]] ? (NSString *)item : [item description];
                if (collection.length == 0) {
                    continue;
                }
                NSCharacterSet *queryAllowed = [NSCharacterSet characterSetWithCharactersInString:
                                                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:@"];
                NSString *escapedCollection = GZAdminUIEscaped(collection);
                if (repoDID.length > 0) {
                    NSString *didQ = [repoDID stringByAddingPercentEncodingWithAllowedCharacters:queryAllowed] ?: @"";
                    NSString *collectionQ = [collection stringByAddingPercentEncodingWithAllowedCharacters:queryAllowed] ?: @"";
                    [chips appendFormat:
                     @"<button type=\"button\" class=\"detail-chip\" "
                     @"hx-get=\"/admin/partials/list-records?did=%@&amp;collection=%@\" "
                     @"hx-target=\"#explorer-records\" hx-swap=\"innerHTML\">%@</button>",
                     GZAdminUIEscaped(didQ), GZAdminUIEscaped(collectionQ), escapedCollection];
                } else {
                    [chips appendFormat:@"<span class=\"detail-chip\">%@</span>", escapedCollection];
                }
            }
            if ([chips isEqualToString:@"<div class=\"detail-chips\">"]) {
                [chips appendString:@"<span class=\"text-secondary text-xs\">none</span>"];
            }
            [chips appendString:@"</div>"];
            [html appendString:GZAdminUIDetailRow(field[@"label"], chips)];
            continue;
        }
        if ([key isEqualToString:@"didDoc"] && [val isKindOfClass:[NSDictionary class]]) {
            [html appendFormat:
             @"<div class=\"detail-row detail-row-stack\">"
             @"<span class=\"detail-label\">%@</span>"
             @"%@"
             @"</div>",
             GZAdminUIEscaped(field[@"label"]),
             GZAdminUIJSONViewer(val)];
            continue;
        }
        NSString *valueHTML = nil;
        if ([val isKindOfClass:[NSArray class]]) {
            NSString *joined = [((NSArray *)val) componentsJoinedByString:@", "];
            valueHTML = [NSString stringWithFormat:@"<span class=\"detail-value text-mono text-xs\">%@</span>",
                         GZAdminUIEscaped(joined)];
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            valueHTML = GZAdminUIJSONViewer(val);
        } else if ([val isKindOfClass:[NSNumber class]]) {
            if ([key isEqualToString:@"handleIsCorrect"] ||
                val == (id)kCFBooleanTrue ||
                val == (id)kCFBooleanFalse) {
                valueHTML = GZAdminUIMonoValue([(NSNumber *)val boolValue] ? @"yes" : @"no");
            } else {
                valueHTML = GZAdminUIMonoValue(val);
            }
        } else {
            valueHTML = [NSString stringWithFormat:@"<span class=\"detail-value text-mono text-xs\">%@</span>",
                         GZAdminUIEscaped([val description])];
        }
        [html appendString:GZAdminUIDetailRow(field[@"label"], valueHTML)];
    }
    [html appendString:GZAdminUIDetailCardClose()];
    return html;
}

+ (NSString *)renderListRecordsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *records = [result[@"records"] isKindOfClass:[NSArray class]] ? result[@"records"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>URI</th><th>CID</th><th>Collection</th><th>Rkey</th></tr></thead><tbody>"];
    for (NSDictionary *record in records) {
        NSString *uriRaw = [record[@"uri"] isKindOfClass:[NSString class]] ? record[@"uri"] : @"";
        NSString *collectionRaw = [record[@"collection"] isKindOfClass:[NSString class]] ? record[@"collection"] : @"";
        NSString *rkeyRaw = [record[@"rkey"] isKindOfClass:[NSString class]] ? record[@"rkey"] : @"";
        // com.atproto.repo.listRecords returns uri+cid (+value); collection/rkey
        // are usually absent and must be parsed from at://did/collection/rkey.
        if ((collectionRaw.length == 0 || rkeyRaw.length == 0) && [uriRaw hasPrefix:@"at://"]) {
            NSString *path = [uriRaw substringFromIndex:5]; // strip at://
            NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
            if (parts.count >= 3) {
                if (collectionRaw.length == 0) {
                    collectionRaw = parts[1] ?: @"";
                }
                if (rkeyRaw.length == 0) {
                    rkeyRaw = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@"/"];
                }
            }
        }
        NSString *uri = GZAdminUIEscaped(uriRaw);
        NSString *cid = GZAdminUIEscaped(record[@"cid"] ?: @"");
        NSString *collection = GZAdminUIEscaped(collectionRaw);
        NSString *rkey = GZAdminUIEscaped(rkeyRaw);
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-mono text-xs\">%@</td><td class=\"text-mono text-xs\">%@</td><td class=\"text-mono text-xs\">%@</td></tr>", uri, cid, collection, rkey];
    }
    if (records.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No records found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = GZAdminUIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/list-records?cursor=%@\" hx-target=\"#records-list\">Load more</button></div>", GZAdminUIEscaped(cursor)];
    }
    return html;
}

+ (NSString *)renderGetRecordPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-grid\">"];
    NSArray *fields = @[@"uri", @"cid", @"value"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        if ([val isKindOfClass:[NSDictionary class]] || [val isKindOfClass:[NSArray class]]) {
            [html appendFormat:@"<div class=\"detail-field full-width\"><span class=\"detail-label\">%@</span>%@</div>",
             GZAdminUIEscaped(key), GZAdminUIJSONViewer(val)];
        } else {
            NSString *display = [val isKindOfClass:[NSString class]] ? GZAdminUIEscaped(val) : GZAdminUIEscaped([val description]);
            [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
        }
    }
    [html appendString:@"</div>"];
    return html;
}

@end
