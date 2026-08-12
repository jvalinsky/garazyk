// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Mikrus/AdminUI/MikrusAdminUIPack.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "Mikrus/AdminUI/MikrusAdminSnapshot.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZMikrusAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZMikrusAdminSnapshot *> *)snapshots {
    static NSMapTable<GZAdminUIHost *, GZMikrusAdminSnapshot *> *snapshots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ snapshots = [NSMapTable weakToStrongObjectsMapTable]; });
    return snapshots;
}

+ (void)configureHost:(GZAdminUIHost *)host snapshot:(GZMikrusAdminSnapshot *)snapshot {
    @synchronized(self) { [[self snapshots] setObject:snapshot forKey:host]; }
}

+ (NSString *)packIdentifier { return @"mikrus"; }
+ (NSString *)displayName { return @"Mikrus"; }
+ (NSArray<NSDictionary<NSString *,id> *> *)sidebarSections {
    return @[
        @{ @"tabIdentifier": @"mikrus-metrics", @"displayName": @"Mikrus Metrics" },
        @{ @"tabIdentifier": @"mikrus-ingestion", @"displayName": @"Ingestion" },
        @{ @"tabIdentifier": @"mikrus-indexes", @"displayName": @"Indexes" },
    ];
}

#pragma mark - HTML renderers

+ (NSString *)metricsHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *db = snapshot[@"database"] ?: @{};
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    
    NSString *health = snapshot[@"health"] ?: @"unknown";
    int64_t uptime = [snapshot[@"uptimeSeconds"] longLongValue];
    int64_t uptimeHours = uptime / 3600;
    int64_t uptimeMins = (uptime % 3600) / 60;
    
    // Health status badge
    NSString *healthBadge;
    if ([health isEqualToString:@"ok"]) {
        healthBadge = @"<span class=\"badge badge-success\">✓ Healthy</span>";
    } else if ([health isEqualToString:@"degraded"]) {
        healthBadge = @"<span class=\"badge badge-warning\">⚠ Degraded</span>";
    } else {
        healthBadge = @"<span class=\"badge badge-destructive\">✗ Error</span>";
    }
    
    // Ingest status
    BOOL ingestEnabled = [ingest[@"enabled"] boolValue];
    BOOL ingestRunning = [ingest[@"running"] boolValue];
    NSString *ingestStatus;
    if (!ingestEnabled) {
        ingestStatus = @"<span class=\"badge badge-secondary\">Disabled</span>";
    } else if (ingestRunning) {
        ingestStatus = @"<span class=\"badge badge-success\">● Running</span>";
    } else {
        ingestStatus = @"<span class=\"badge badge-warning\">○ Stopped</span>";
    }
    
    int64_t totalQueries = [queries[@"backlink"] longLongValue] + [queries[@"manyToMany"] longLongValue]
                         + [queries[@"identity"] longLongValue] + [queries[@"record"] longLongValue];
    int64_t events = [ingest[@"events"] longLongValue];
    int64_t errors = [ingest[@"errors"] longLongValue];
    double errorRate = events > 0 ? (100.0 * errors / events) : 0.0;
    
    NSMutableString *html = [NSMutableString string];
    
    // Service Health Section
    [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Service Health</h3>"];
    [html appendString:@"<div class=\"metric-grid\">"];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Status</div><div class=\"metric-value\">%@</div></div>", healthBadge];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Uptime</div><div class=\"metric-value\">%lldh %lldm</div></div>", (long long)uptimeHours, (long long)uptimeMins];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Ingest</div><div class=\"metric-value\">%@</div></div>", ingestStatus];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Storage</div><div class=\"metric-value\">%lld MB</div></div>", (long long)([db[@"storageBytes"] longLongValue] / (1024 * 1024))];
    [html appendString:@"</div></section>"];
    
    // Ingest Performance Section
    [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Ingest Performance</h3>"];
    [html appendString:@"<div class=\"metric-grid\">"];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Events Processed</div><div class=\"metric-value metric-large\">%@</div></div>", ingest[@"events"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Commits</div><div class=\"metric-value metric-large\">%@</div></div>", ingest[@"commits"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Records Indexed</div><div class=\"metric-value metric-success\">%@</div></div>", ingest[@"recordsIndexed"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Records Deleted</div><div class=\"metric-value\">%@</div></div>", ingest[@"recordsDeleted"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Errors</div><div class=\"metric-value metric-destructive\">%lld <span class=\"text-secondary\">(%.2f%%)</span></div></div>", (long long)errors, errorRate];
    [html appendString:@"</div></section>"];
    
    // Index Statistics Section
    [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Index Statistics</h3>"];
    [html appendString:@"<div class=\"metric-grid\">"];
    
    NSDictionary *backlinks = indexes[@"backlinks"];
    NSDictionary *records = indexes[@"records"];
    NSDictionary *identities = indexes[@"identities"];
    NSDictionary *manyToMany = indexes[@"manyToMany"];
    
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Backlink Edges</div><div class=\"metric-value\">%@</div><div class=\"metric-help\">%@</div></div>",
     backlinks[@"approxEdges"] ?: @0, GZAdminUIEscaped(backlinks[@"description"])];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Cached Records</div><div class=\"metric-value\">%@</div><div class=\"metric-help\">%@</div></div>",
     records[@"approxCount"] ?: @0, GZAdminUIEscaped(records[@"description"])];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Identity Mappings</div><div class=\"metric-value\">%@</div><div class=\"metric-help\">%@</div></div>",
     identities[@"approxCount"] ?: @0, GZAdminUIEscaped(identities[@"description"])];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Many-to-Many Edges</div><div class=\"metric-value\">%@</div><div class=\"metric-help\">%@</div></div>",
     manyToMany[@"approxEdges"] ?: @0, GZAdminUIEscaped(manyToMany[@"description"])];
    [html appendString:@"</div></section>"];
    
    // Query Performance Section
    [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Query Performance</h3>"];
    [html appendString:@"<div class=\"metric-grid\">"];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Total Queries</div><div class=\"metric-value metric-large\">%lld</div></div>", (long long)totalQueries];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Backlink Queries</div><div class=\"metric-value\">%@</div></div>", queries[@"backlink"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Many-to-Many Queries</div><div class=\"metric-value\">%@</div></div>", queries[@"manyToMany"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Identity Queries</div><div class=\"metric-value\">%@</div></div>", queries[@"identity"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Record Queries</div><div class=\"metric-value\">%@</div></div>", queries[@"record"] ?: @0];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-label\">Rate Limited</div><div class=\"metric-value metric-warning\">%@</div></div>", snapshot[@"rateLimitRejects"] ?: @0];
    [html appendString:@"</div></section>"];
    
    return html;
}

+ (NSString *)ingestionHTML:(NSDictionary *)snapshot {
    NSDictionary *ingest = snapshot[@"ingest"] ?: @{};
    NSArray *relayURLs = snapshot[@"config"][@"relayURLs"] ?: @[];
    NSDictionary *relayHealth = ingest[@"relayHealth"] ?: @{};
    NSDictionary *lag = ingest[@"lagByRelay"] ?: @{};
    NSDictionary *throughput = ingest[@"throughput"] ?: @{};
    NSArray *recentErrors = snapshot[@"recentErrors"] ?: @[];
    
    NSMutableString *html = [NSMutableString string];
    
    // Relay Connections Section
    [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Relay Connections</h3>"];
    
    if (relayURLs.count == 0) {
        [html appendString:@"<div class=\"alert alert-info\">No relays configured. Ingest is disabled.</div>"];
    } else {
        [html appendString:@"<div class=\"relay-grid\">"];
        
        for (NSString *url in relayURLs) {
            NSString *status = relayHealth[url] ?: @"unknown";
            NSNumber *lagValue = lag[url];
            NSNumber *throughputValue = throughput[url];
            
            NSString *statusBadge;
            NSString *statusIcon;
            if ([status isEqualToString:@"connected"]) {
                statusBadge = @"<span class=\"badge badge-success\">● Connected</span>";
                statusIcon = @"●";
            } else if ([status isEqualToString:@"disconnected"]) {
                statusBadge = @"<span class=\"badge badge-secondary\">○ Disconnected</span>";
                statusIcon = @"○";
            } else if ([status isEqualToString:@"error"]) {
                statusBadge = @"<span class=\"badge badge-destructive\">✗ Error</span>";
                statusIcon = @"✗";
            } else {
                statusBadge = @"<span class=\"badge badge-secondary\">? Unknown</span>";
                statusIcon = @"?";
            }
            
            int64_t lagVal = lagValue ? [lagValue longLongValue] : 0;
            NSString *lagDisplay;
            NSString *lagClass = @"";
            if (lagVal == 0) {
                lagDisplay = @"—";
            } else if (lagVal < 1000) {
                lagDisplay = [NSString stringWithFormat:@"%lld", (long long)lagVal];
                lagClass = @"metric-success";
            } else if (lagVal < 10000) {
                lagDisplay = [NSString stringWithFormat:@"%lld", (long long)lagVal];
                lagClass = @"metric-warning";
            } else {
                lagDisplay = [NSString stringWithFormat:@"%lld", (long long)lagVal];
                lagClass = @"metric-destructive";
            }
            
            double tput = throughputValue ? [throughputValue doubleValue] : 0.0;
            NSString *throughputDisplay = tput > 0 ? [NSString stringWithFormat:@"%.1f events/s", tput] : @"—";
            
            [html appendFormat:
             @"<div class=\"relay-card\">"
             @"<div class=\"relay-header\"><span class=\"text-mono\">%@</span>%@</div>"
             @"<div class=\"relay-metrics\">"
             @"<div class=\"relay-metric\"><span class=\"metric-label\">Lag</span><span class=\"metric-value %@\">%@</span></div>"
             @"<div class=\"relay-metric\"><span class=\"metric-label\">Throughput</span><span class=\"metric-value\">%@</span></div>"
             @"</div>"
             @"</div>",
             GZAdminUIEscaped(url), statusBadge, lagClass, lagDisplay, throughputDisplay];
        }
        
        [html appendString:@"</div>"];
    }
    [html appendString:@"</section>"];
    
    // Event Counters Section
    [html appendFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Event Counters</h3>"
        @"<table class=\"table\"><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>"
        @"<tr><td>Events</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Commits</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Deletes</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Operations</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Identities</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Records indexed</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Records deleted</td><td class=\"text-right\">%@</td></tr>"
        @"<tr><td>Errors</td><td class=\"text-right text-destructive\">%@</td></tr>"
        @"</tbody></table></section>",
        ingest[@"events"] ?: @0, ingest[@"commits"] ?: @0, ingest[@"deletes"] ?: @0,
        ingest[@"ops"] ?: @0, ingest[@"identities"] ?: @0,
        ingest[@"recordsIndexed"] ?: @0, ingest[@"recordsDeleted"] ?: @0, ingest[@"errors"] ?: @0
    ];
    
    // Recent Errors Section
    if (recentErrors.count > 0) {
        [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Recent Errors</h3>"];
        [html appendString:@"<table class=\"table table-compact\"><thead><tr><th>Time</th><th>Relay</th><th>DID</th><th>Seq</th><th>Error</th></tr></thead><tbody>"];
        
        for (NSDictionary *error in recentErrors) {
            NSString *timestamp = error[@"timestamp"] ?: @"—";
            NSString *relayURL = error[@"relay_url"] ?: @"—";
            NSString *did = error[@"did"] ?: @"—";
            NSString *seq = error[@"seq"] ? [error[@"seq"] stringValue] : @"—";
            NSString *message = error[@"error_message"] ?: @"Unknown error";
            
            [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td class=\"text-mono text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td><td class=\"text-right\">%@</td><td>%@</td></tr>",
             GZAdminUIEscaped(timestamp), GZAdminUIEscaped(relayURL), GZAdminUIEscaped(did), seq, GZAdminUIEscaped(message)];
        }
        
        [html appendString:@"</tbody></table></section>"];
    }
    
    return html;
}

+ (NSString *)indexesHTML:(NSDictionary *)snapshot {
    NSDictionary *indexes = snapshot[@"indexes"] ?: @{};
    NSDictionary *queries = snapshot[@"queries"] ?: @{};
    NSDictionary *topCollections = snapshot[@"topCollections"] ?: @{};
    
    NSMutableString *html = [NSMutableString string];
    
    // Index Families Section
    [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Index Families</h3>"];
    [html appendString:@"<div class=\"index-grid\">"];
    
    NSArray *families = @[@"backlinks", @"records", @"identities", @"manyToMany"];
    NSArray *icons = @[@"🔗", @"📄", @"👤", @"↔"];
    
    for (NSUInteger i = 0; i < families.count; i++) {
        NSString *family = families[i];
        NSString *icon = icons[i];
        NSDictionary *familyData = indexes[family];
        
        NSString *countKey = [family isEqualToString:@"backlinks"] || [family isEqualToString:@"manyToMany"] ? @"approxEdges" : @"approxCount";
        NSNumber *count = familyData[countKey] ?: @0;
        NSString *description = familyData[@"description"] ?: @"";
        
        [html appendFormat:
         @"<div class=\"index-card\">"
         @"<div class=\"index-icon\">%@</div>"
         @"<div class=\"index-title\">%@</div>"
         @"<div class=\"index-count\">%@</div>"
         @"<div class=\"index-description\">%@</div>"
         @"</div>",
         icon, [self humanReadableFamily:family], count, GZAdminUIEscaped(description)];
    }
    
    [html appendString:@"</div></section>"];
    
    // Top Collections Section
    if (topCollections.count > 0) {
        [html appendString:@"<section class=\"mt-md\"><h3 class=\"section-title\">Top Collections by Record Count</h3>"];
        [html appendString:@"<table class=\"table\"><thead><tr><th>Collection</th><th class=\"text-right\">Records</th></tr></thead><tbody>"];
        
        // Sort collections by count descending
        NSArray *sortedCollections = [topCollections keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *obj1, NSNumber *obj2) {
            return [obj2 compare:obj1];
        }];
        
        for (NSString *collection in sortedCollections) {
            NSNumber *count = topCollections[collection];
            [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td class=\"text-right metric-large\">%@</td></tr>",
             GZAdminUIEscaped(collection), count];
        }
        
        [html appendString:@"</tbody></table></section>"];
    }
    
    // Query Activity Section
    int64_t totalQueries = [queries[@"backlink"] longLongValue] + [queries[@"manyToMany"] longLongValue]
                         + [queries[@"identity"] longLongValue] + [queries[@"record"] longLongValue];
    
    [html appendFormat:
        @"<section class=\"mt-md\"><h3 class=\"section-title\">Query Activity</h3>"
        @"<div class=\"query-stats\">"
        @"<div class=\"query-total\">Total: <strong>%lld</strong> queries</div>"
        @"</div>"
        @"<table class=\"table\"><thead><tr><th>Query Family</th><th class=\"text-right\">Requests</th><th class=\"text-right\">Percentage</th></tr></thead><tbody>",
        (long long)totalQueries];
    
    NSArray *queryFamilies = @[@"backlink", @"manyToMany", @"identity", @"record"];
    NSArray *queryNames = @[@"Backlinks", @"Many-to-Many", @"Identity Lookups", @"Record Lookups"];
    
    for (NSUInteger i = 0; i < queryFamilies.count; i++) {
        NSString *family = queryFamilies[i];
        NSString *name = queryNames[i];
        int64_t count = [queries[family] longLongValue];
        double percentage = totalQueries > 0 ? (100.0 * count / totalQueries) : 0.0;
        
        NSString *barWidth = [NSString stringWithFormat:@"%.1f%%", percentage];
        NSString *barClass = percentage > 50 ? @"bar-primary" : (percentage > 25 ? @"bar-success" : @"bar-secondary");
        
        [html appendFormat:
         @"<tr>"
         @"<td>%@</td>"
         @"<td class=\"text-right\">%lld</td>"
         @"<td class=\"text-right\">%.1f%% <div class=\"progress-bar\"><div class=\"progress-fill %@\" style=\"width: %@\"></div></div></td>"
         @"</tr>",
         name, (long long)count, percentage, barClass, barWidth];
    }
    
    [html appendString:@"</tbody></table></section>"];
    
    return html;
}

+ (NSString *)humanReadableFamily:(NSString *)family {
    if ([family isEqualToString:@"backlinks"]) return @"Backlinks";
    if ([family isEqualToString:@"records"]) return @"Records";
    if ([family isEqualToString:@"identities"]) return @"Identities";
    if ([family isEqualToString:@"manyToMany"]) return @"Many-to-Many";
    return family;
}

+ (NSString *)errorUnavailableHTML {
    return @"<div class=\"alert alert-destructive\">Mikrus dashboard is unavailable — embedded listener required.</div>";
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    GZMikrusAdminSnapshot *snapshot = nil;
    @synchronized(self) { snapshot = [[self snapshots] objectForKey:host]; }
    __weak GZAdminUIHost *weakHost = host;
    
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-metrics" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self metricsHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-ingestion" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self ingestionHTML:value] : [self errorUnavailableHTML]];
    }];
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/mikrus-indexes" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *value = snapshot ? [snapshot snapshot] : nil;
        [res setBodyString:snapshot ? [self indexesHTML:value] : [self errorUnavailableHTML]];
    }];
}

@end
