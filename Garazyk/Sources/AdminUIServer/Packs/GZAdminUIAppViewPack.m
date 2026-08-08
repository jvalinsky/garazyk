// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIAppViewPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"

@implementation GZAdminUIAppViewPack

+ (NSString *)packIdentifier {
    return @"appview";
}

+ (NSString *)displayName {
    return @"AppView";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"appview", @"displayName": @"AppView"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerAppViewRoutes];
}

+ (NSString *)renderAppViewMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];
    NSDictionary *backfill = result[@"backfill"] ?: @{};
    NSDictionary *ingest = result[@"ingest"] ?: @{};
    NSDictionary *index = result[@"index"] ?: @{};

    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Queue Depth</span><span class=\"metric-value\">%@</span></div>", UIEscaped([backfill[@"queue_depth"] stringValue] ?: @"0")];
    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Active Workers</span><span class=\"metric-value\">%@</span></div>", UIEscaped([backfill[@"active_workers"] stringValue] ?: @"0")];
    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Relays</span><span class=\"metric-value\">%@</span></div>", UIEscaped([ingest[@"relays"] stringValue] ?: @"0")];
    [html appendFormat:@"<div class=\"metric\"><span class=\"metric-label\">Index Records</span><span class=\"metric-value\">%@</span></div>", UIEscaped([index[@"total_records"] stringValue] ?: @"0")];
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)renderIngestHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Relay</th><th>Lag</th><th>Throughput</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *relays = [result[@"relays"] isKindOfClass:[NSArray class]] ? result[@"relays"] : @[];
    for (NSDictionary *relay in relays) {
        NSString *url = UIEscaped(relay[@"url"] ?: @"");
        NSString *lag = UIEscaped([relay[@"lag"] stringValue] ?: @"0");
        NSString *tps = UIEscaped([relay[@"throughput"] stringValue] ?: @"0");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", url, lag, tps];
    }
    if (relays.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No relay ingest data.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)renderBackfillQueuePartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"appview-result\" aria-live=\"polite\"></div><div class=\"mb-lg\"><button class=\"btn btn-secondary btn-sm\" data-ui-action=\"rebuild-appview-scope\">Rebuild Relevance Set</button></div><form class=\"form mb-lg\" data-ui-form=\"enqueue-backfill\"><div class=\"form-group\"><label for=\"enqueue-dids-input\">Enqueue DIDs (one per line):</label><textarea id=\"enqueue-dids-input\" class=\"form-input\" placeholder=\"did:plc:...\"></textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Enqueue</button></form><table class=\"table\" id=\"queue-table\"><thead><tr><th>DID</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
    for (NSDictionary *entry in entries) {
        NSString *did = UIEscaped(entry[@"did"] ?: @"");
        NSString *status = UIEscaped(entry[@"status"] ?: @"");
        NSString *statusBadge = [status isEqualToString:@"running"] ? @"badge badge-success" :
                                [status isEqualToString:@"failed"] ? @"badge badge-destructive" : @"badge badge-secondary";
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td><span class=\"%@\">%@</span></td><td>", did, statusBadge, status];
        [html appendFormat:@"<button class=\"btn btn-sm btn-primary\" data-ui-action=\"appview-retry-repo\" data-ui-did=\"%@\">Retry</button> ", did];
        [html appendFormat:@"<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"appview-cancel-repo\" data-ui-did=\"%@\">Cancel</button>", did];
        [html appendString:@"</td></tr>"];
    }
    if (entries.count == 0) {
        [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">Queue is empty.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

@end
