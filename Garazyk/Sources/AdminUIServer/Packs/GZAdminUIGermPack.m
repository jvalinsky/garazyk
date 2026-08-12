// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIGermPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIGermPack

+ (NSString *)packIdentifier {
    return @"germ";
}

+ (NSString *)displayName {
    return @"Germ";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"germ", @"displayName": @"Mailbox"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerGermRoutes];
}

+ (NSString *)renderGermOverviewHTML {
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Operator posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Privacy", @"value": @"Aggregate counters only — no ciphertext, addresses, or agents"},
        @{@"label": @"Encryption", @"value": @"End-to-end encrypted — server cannot decrypt"},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Health"]];
    [html appendString:@"<div id=\"germ-health\" hx-get=\"/admin/partials/germ-health\" hx-trigger=\"revealed, every 30s\"></div></section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Mailbox flow"]];
    [html appendString:@"<div id=\"germ-flow\" hx-get=\"/admin/partials/germ-flow\" hx-trigger=\"revealed, every 30s\"></div></section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Storage"]];
    [html appendString:@"<div id=\"germ-storage\" hx-get=\"/admin/partials/germ-storage\" hx-trigger=\"revealed, every 30s\"></div></section>"];
    return html;
}

+ (NSString *)renderGermHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-warning";
    return [GZAdminUITemplateEngine renderTemplate:@"germ-health" context:ctx];
}

@end
