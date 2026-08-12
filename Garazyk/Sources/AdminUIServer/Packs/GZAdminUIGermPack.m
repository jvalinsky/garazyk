// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIGermPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
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
    return @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Privacy</span>"
        @"<span class=\"metric-value\">Aggregate counters only — no ciphertext, addresses, or agent data</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Encryption</span>"
        @"<span class=\"metric-value\">End-to-end encrypted — server cannot decrypt</span></div>"
        @"</div>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Health</h3>"
        @"<div id=\"germ-health\" hx-get=\"/admin/partials/germ-health\" hx-trigger=\"revealed, every 30s\"></div></section>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Mailbox Flow</h3>"
        @"<div id=\"germ-flow\" hx-get=\"/admin/partials/germ-flow\" hx-trigger=\"revealed, every 30s\"></div></section>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Storage</h3>"
        @"<div id=\"germ-storage\" hx-get=\"/admin/partials/germ-storage\" hx-trigger=\"revealed, every 30s\"></div></section>";
}

+ (NSString *)renderGermHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-warning";
    return [GZAdminUITemplateEngine renderTemplate:@"germ-health" context:ctx];
}

@end
