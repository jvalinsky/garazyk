#import <Foundation/Foundation.h>
#import "AdminUIHandler.h"
#import "Metrics/PDSMetrics.h"
#import "Admin/AdminPartialHandler.h"
#import "Admin/PDSAdminHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdminUIHandler ()
@property (nonatomic, strong) NSBundle *bundle;
@end

@implementation AdminUIHandler

+ (instancetype)sharedHandler {
    static AdminUIHandler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AdminUIHandler alloc] init];
    });
    return shared;
}

- (NSString *)assetsDirectoryPath {
    // For command-line tools, look for AdminUI relative to executable location
    NSString *executablePath = [[NSBundle mainBundle] executablePath];
    NSString *baseDir = [executablePath stringByDeletingLastPathComponent];

    // Try in the build directory structure first (for development)
    // From build/bin: go up 2 levels to reach garazyk root, then find Garazyk/Sources/Admin/AdminUI/Assets
    NSString *buildAssetsPath = [baseDir stringByAppendingPathComponent:@"../../Garazyk/Sources/Admin/AdminUI/Assets"];
    NSString *resolvedPath = [buildAssetsPath stringByResolvingSymlinksInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
        return resolvedPath;
    }

    // Fallback to bundle path (for deployed app)
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    return [bundlePath stringByAppendingPathComponent:@"AdminUI/Assets"];
}

- (NSString *)templatesDirectoryPath {
    // For command-line tools, look for AdminUI relative to executable location
    NSString *executablePath = [[NSBundle mainBundle] executablePath];
    NSString *baseDir = [executablePath stringByDeletingLastPathComponent];

    // Try in the build directory structure first (for development)
    // From build/bin: go up 2 levels to reach garazyk root, then find Garazyk/Sources/Admin/AdminUI/Templates
    NSString *buildTemplatesPath = [baseDir stringByAppendingPathComponent:@"../../Garazyk/Sources/Admin/AdminUI/Templates"];
    NSString *resolvedPath = [buildTemplatesPath stringByResolvingSymlinksInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
        return resolvedPath;
    }

    // Fallback to bundle path (for deployed app)
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    return [bundlePath stringByAppendingPathComponent:@"AdminUI/Templates"];
}

- (nullable NSString *)handleRequestWithMethod:(AdminUIHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {

    // Route static assets
    if ([path hasPrefix:@"/admin/assets/"]) {
        return [self handleStaticAssetPath:path statusCode:statusCode contentType:contentType];
    }

    // Route partial templates
    if ([path hasPrefix:@"/admin/partials/"]) {
        return [self handlePartialPath:path statusCode:statusCode contentType:contentType];
    }

    // Root admin UI entry point and all sub-paths return the shell
    if ([path isEqualToString:@"/admin"] || [path hasPrefix:@"/admin/"] ) {
        // Exclude specific prefixes that are handled elsewhere
        if (![path hasPrefix:@"/admin/assets/"] &&
            ![path hasPrefix:@"/admin/partials/"] &&
            ![path hasPrefix:@"/admin/css/"] &&
            ![path hasPrefix:@"/admin/js/"]) {
            return [self handleRootPath:statusCode contentType:contentType];
        }
    }

    // Static asset fallback (without /assets prefix for compatibility)
    if ([path hasPrefix:@"/admin/css/"] || [path hasPrefix:@"/admin/js/"]) {
        NSString *remainingPath = [path substringWithRange:NSMakeRange(6, path.length - 6)];
        NSString *adjustedPath = [@"/admin/assets" stringByAppendingString:remainingPath];
        return [self handleStaticAssetPath:adjustedPath statusCode:statusCode contentType:contentType];
    }

    return nil;
}

#pragma mark - Static Asset Handling

- (nullable NSString *)handleStaticAssetPath:(NSString *)path
                                  statusCode:(nullable NSInteger *)statusCode
                                 contentType:(NSString * _Nullable * _Nullable)contentType {
    NSString *assetPath = [path stringByReplacingOccurrencesOfString:@"/admin/assets/"
                                                           withString:@""];

    NSString *fullPath = [[self assetsDirectoryPath] stringByAppendingPathComponent:assetPath];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:fullPath]) {
        if (statusCode) *statusCode = 404;
        if (contentType) *contentType = @"text/plain";
        return @"Not Found";
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:fullPath options:0 error:&error];
    if (!data) {
        if (statusCode) *statusCode = 500;
        if (contentType) *contentType = @"text/plain";
        return @"Internal Server Error";
    }

    // Determine content type
    NSString *fileExtension = [fullPath pathExtension];
    NSString *type = [self contentTypeForExtension:fileExtension];
    if (contentType) *contentType = type;
    if (statusCode) *statusCode = 200;

    // Convert data to string if appropriate
    if ([type hasPrefix:@"text/"] || [type isEqualToString:@"application/json"]
        || [type isEqualToString:@"application/javascript"]) {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }

    // For binary files, encode as base64 data URL
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"data:%@;base64,%@", type, base64];
}

#pragma mark - Partial Template Handling

- (nullable NSString *)handlePartialPath:(NSString *)path
                              statusCode:(nullable NSInteger *)statusCode
                             contentType:(NSString * _Nullable * _Nullable)contentType {
    NSString *partialPath = [path stringByReplacingOccurrencesOfString:@"/admin/partials/"
                                                         withString:@""];
    
    // Split partial name and query string
    NSString *partial = partialPath;
    NSRange queryRange = [partialPath rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        partial = [partialPath substringToIndex:queryRange.location];
    }

    // Parse query parameters from path
    NSDictionary *params = [self parseQueryString:path];

    if ([partial isEqualToString:@"overview"]) {
        return [self renderOverviewPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"users"]) {
        return [self renderUsersPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"users/search"]) {
        NSString *query = params[@"q"] ?: @"";
        return [self renderUsersSearchWithQuery:query statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"users/detail"]) {
        NSString *did = params[@"did"];
        return [self renderUsersDetailWithDid:did statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"invites"]) {
        return [self renderInvitesPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"identity"]) {
        return [self renderIdentityPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"health"]) {
        return [self renderHealthPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"health/status"]) {
        return [self renderHealthStatusWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"plc/lookup"]) {
        return [self renderPLCLookupPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"plc/export"]) {
        return [self renderPLCExportPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"plc/metrics"]) {
        return [self renderPLCMetricsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"relay/upstreams"]) {
        return [self renderRelayUpstreamsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"relay/events"]) {
        return [self renderRelayEventsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"relay/crawl"]) {
        return [self renderRelayCrawlPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"appview/backfill"]) {
        return [self renderAppViewBackfillPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"appview/index"]) {
        return [self renderAppViewIndexPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"appview/metrics"]) {
        return [self renderAppViewMetricsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/convos"]) {
        return [self renderChatConvosPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/convos/search"]) {
        NSString *query = params[@"q"] ?: @"";
        return [self renderChatConvosSearchWithQuery:query statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/groups"]) {
        return [self renderChatGroupsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/groups/search"]) {
        NSString *query = params[@"q"] ?: @"";
        return [self renderChatGroupsSearchWithQuery:query statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/groups/detail"]) {
        NSString *groupUri = params[@"groupUri"];
        return [self renderChatGroupDetailPartialWithGroupUri:groupUri statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/invite-links"]) {
        return [self renderChatInviteLinksPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/invite-links/search"]) {
        NSString *query = params[@"q"] ?: @"";
        return [self renderChatInviteLinksSearchWithQuery:query statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/messages"]) {
        return [self renderChatMessagesPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/reports"]) {
        return [self renderChatReportsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"chat/reports/list"]) {
        return [self renderChatReportsListWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/events"]) {
        return [self renderOzoneEventsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/statuses"]) {
        return [self renderOzoneStatusesPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/team"]) {
        return [self renderOzoneTeamPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/templates"]) {
        return [self renderOzoneTemplatesPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"security/sessions"]) {
        return [self renderSecuritySessionsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"security/app-passwords"]) {
        return [self renderSecurityAppPasswordsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/sets"]) {
        return [self renderOzoneSetsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/correlations"]) {
        return [self renderOzoneCorrelationsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"ozone/verification"]) {
        return [self renderOzoneVerificationPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"diagnostics/overview"]) {
        return [self renderDiagnosticsOverviewPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"diagnostics/sequencer"]) {
        return [self renderDiagnosticsSequencerPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"diagnostics/blobs"]) {
        return [self renderDiagnosticsBlobsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"diagnostics/ratelimits"]) {
        return [self renderDiagnosticsRateLimitsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"reports"]) {
        return [self renderReportsPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"reports/list"]) {
        return [self renderReportsListWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"audit-log"]) {
        return [self renderAuditLogPartialWithStatusCode:statusCode contentType:contentType];
    }

    if (statusCode) *statusCode = 404;
    if (contentType) *contentType = @"text/html";
    return @"<p>Partial not found</p>";
}

- (NSDictionary *)parseQueryString:(NSString *)url {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSRange queryStart = [url rangeOfString:@"?"];

    if (queryStart.location != NSNotFound) {
        NSString *queryString = [url substringWithRange:NSMakeRange(queryStart.location + 1, url.length - queryStart.location - 1)];
        NSArray *pairs = [queryString componentsSeparatedByString:@"&"];

        for (NSString *pair in pairs) {
            NSArray *components = [pair componentsSeparatedByString:@"="];
            if (components.count == 2) {
                NSString *key = [components[0] stringByRemovingPercentEncoding];
                NSString *value = [components[1] stringByRemovingPercentEncoding];
                params[key] = value;
            }
        }
    }

    return [params copy];
}

#pragma mark - Root Path Handling

- (nullable NSString *)handleRootPath:(nullable NSInteger *)statusCode
                          contentType:(NSString * _Nullable * _Nullable)contentType {
    NSString *indexPath = [[self assetsDirectoryPath] stringByAppendingPathComponent:@"index.html"];

    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:indexPath
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
    if (!html) {
        if (statusCode) *statusCode = 404;
        if (contentType) *contentType = @"text/html";
        return @"<h1>Not Found</h1>";
    }

    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html; charset=utf-8";
    return html;
}

#pragma mark - Partial Template Rendering

- (NSString *)renderOverviewPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    return @"<div class=\"content-header\">"
           @"<h1>Welcome to AT Protocol Admin</h1>"
           @"<p class=\"text-secondary mt-sm\">Select a service from the sidebar to get started.</p>"
           @"</div>"
           @"<div class=\"grid-3\">"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">Personal Data Server</h3></div>"
           @"<div class=\"card-body\"><p>Manage users, invites, blobs, identity, and server health.</p></div>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">PLC Directory</h3></div>"
           @"<div class=\"card-body\"><p>Lookup DIDs, manage exports, and view metrics.</p></div>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">Relay (BGS)</h3></div>"
           @"<div class=\"card-body\"><p>Monitor upstreams, event streams, and crawl queue.</p></div>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">AppView</h3></div>"
           @"<div class=\"card-body\"><p>Track backfill progress, index status, and metrics.</p></div>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">Chat Service</h3></div>"
           @"<div class=\"card-body\"><p>Monitor active conversations and audit message history.</p></div>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">Ozone</h3></div>"
           @"<div class=\"card-body\"><p>Enterprise moderation tools, team management, and event auditing.</p></div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderUsersPartialWithStatusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    return @"<div class=\"content-header\">"
           @"<h2>Users</h2>"
           @"<p class=\"text-secondary\">Manage user accounts and status.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\">"
           @"<h3 class=\"card-title\">Search Users</h3>"
           @"</div>"
           @"<div class=\"card-body\">"
           @"<form class=\"form\" hx-get=\"/admin/partials/users/search\" hx-target=\"#users-table\">"
           @"<div class=\"form-group\">"
           @"<label class=\"form-label\">DID or Handle</label>"
           @"<input type=\"text\" name=\"q\" class=\"form-input\" placeholder=\"Search users...\" "
           @"hx-trigger=\"input changed debounce:300ms\" hx-target=\"#users-table\" />"
           @"</div>"
           @"</form>"
           @"</div>"
           @"</div>"
           @"<div class=\"table-wrapper mt-lg\">"
           @"<table class=\"table\">"
           @"<thead>"
           @"<tr>"
           @"<th>DID</th>"
           @"<th>Handle</th>"
           @"<th>Status</th>"
           @"<th>Created</th>"
           @"<th>Actions</th>"
           @"</tr>"
           @"</thead>"
           @"<tbody id=\"users-table\">"
           @"<tr><td colspan=\"5\" class=\"text-secondary text-center p-lg\">No users loaded. Use search to load users.</td></tr>"
           @"</tbody>"
           @"</table>"
           @"</div>";
}

- (NSString *)renderInvitesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                   contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    return @"<div class=\"content-header\">"
           @"<h2>Invite Codes</h2>"
           @"<p class=\"text-secondary\">Create and manage invite codes.</p>"
           @"</div>"
           @"<div class=\"card mb-lg\">"
           @"<div class=\"card-header\">"
           @"<h3 class=\"card-title\">Create Invite</h3>"
           @"</div>"
           @"<div class=\"card-body\">"
           @"<form class=\"form\" hx-post=\"/admin/invites\" hx-swap=\"beforeend:#invites-list\">"
           @"<div class=\"form-row\">"
           @"<div class=\"form-group\">"
           @"<label class=\"form-label\">Uses</label>"
           @"<input type=\"number\" name=\"uses\" class=\"form-input\" value=\"1\" min=\"1\" required />"
           @"</div>"
           @"</div>"
           @"<div class=\"card-footer\">"
           @"<button type=\"submit\" class=\"btn btn-primary\">Create Invite</button>"
           @"</div>"
           @"</form>"
           @"</div>"
           @"</div>"
           @"<div class=\"table-wrapper\">"
           @"<table class=\"table\">"
           @"<thead>"
           @"<tr>"
           @"<th>Code</th>"
           @"<th>Uses</th>"
           @"<th>Disabled</th>"
           @"<th>Created</th>"
           @"<th>Actions</th>"
           @"</tr>"
           @"</thead>"
           @"<tbody id=\"invites-list\">"
           @"<tr><td colspan=\"5\" class=\"text-secondary text-center p-lg\">No invites created yet.</td></tr>"
           @"</tbody>"
           @"</table>"
           @"</div>";
}

- (NSString *)renderIdentityPartialWithStatusCode:(nullable NSInteger *)statusCode
                                    contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    return @"<div class=\"content-header\">"
           @"<h2>Identity Management</h2>"
           @"<p class=\"text-secondary\">Resolve DIDs, lookup handles, and manage identity operations.</p>"
           @"</div>"
           @"<div class=\"grid-2\">"
           @"<div class=\"card\">"
           @"<div class=\"card-header\">"
           @"<h3 class=\"card-title\">Resolve DID</h3>"
           @"</div>"
           @"<div class=\"card-body\">"
           @"<form class=\"form\" hx-get=\"/xrpc/com.atproto.identity.resolveDid\" hx-target=\"#did-result\">"
           @"<div class=\"form-group\">"
           @"<label class=\"form-label\">DID</label>"
           @"<input type=\"text\" name=\"did\" class=\"form-input\" placeholder=\"did:plc:...\" required />"
           @"</div>"
           @"<button type=\"submit\" class=\"btn btn-primary\">Resolve</button>"
           @"</form>"
           @"<div id=\"did-result\" class=\"mt-md\"></div>"
           @"</div>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\">"
           @"<h3 class=\"card-title\">Handle Lookup</h3>"
           @"</div>"
           @"<div class=\"card-body\">"
           @"<form class=\"form\" hx-get=\"/xrpc/com.atproto.identity.resolveHandle\" hx-target=\"#handle-result\">"
           @"<div class=\"form-group\">"
           @"<label class=\"form-label\">Handle</label>"
           @"<input type=\"text\" name=\"handle\" class=\"form-input\" placeholder=\"user.bsky.social\" required />"
           @"</div>"
           @"<button type=\"submit\" class=\"btn btn-primary\">Lookup</button>"
           @"</form>"
           @"<div id=\"handle-result\" class=\"mt-md\"></div>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderHealthPartialWithStatusCode:(nullable NSInteger *)statusCode
                                 contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    return @"<div class=\"content-header\">"
           @"<h2>Server Health</h2>"
           @"<p class=\"text-secondary\">Monitor server status and performance metrics.</p>"
           @"</div>"
           @"<div class=\"grid-3\" hx-get=\"/admin/health\" hx-trigger=\"load, every 30s\" hx-swap=\"outerHTML\">"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Status</div>"
           @"<div class=\"stat-value\">Loading...</div>"
           @"</div>"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Uptime</div>"
           @"<div class=\"stat-value\">--</div>"
           @"</div>"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Database</div>"
           @"<div class=\"stat-value\">--</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderUsersSearchWithQuery:(NSString *)query
                              statusCode:(nullable NSInteger *)statusCode
                             contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    // Mock data - in production, query the database
    NSArray *mockUsers = @[
        @{
            @"did": @"did:plc:example123",
            @"handle": @"user.bsky.social",
            @"email": @"user@example.com",
            @"active": @YES,
            @"createdAt": @"2024-01-15"
        },
        @{
            @"did": @"did:plc:example456",
            @"handle": @"another.bsky.social",
            @"email": @"another@example.com",
            @"active": @YES,
            @"createdAt": @"2024-02-10"
        }
    ];

    NSString *templatePath = [[self templatesDirectoryPath] stringByAppendingPathComponent:@"partials/users-search-response.html"];
    NSError *error = nil;
    NSString *template = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:&error];

    if (!template) {
        return [self renderEmptyStateWithMessage:@"No users found" suggestion:@"Try a different search query."];
    }

    return [self renderTemplate:template withContext:@{@"users": mockUsers}];
}

- (NSString *)renderHealthStatusWithStatusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    PDSMetrics *metrics = [PDSMetrics sharedMetrics];
    NSTimeInterval uptime = [[NSDate date] timeIntervalSince1970] - metrics.serverStartTime;
    
    NSInteger days = (NSInteger)(uptime / 86400);
    NSInteger hours = (NSInteger)((uptime - (days * 86400)) / 3600);
    NSInteger minutes = (NSInteger)((uptime - (days * 86400) - (hours * 3600)) / 60);
    
    NSString *uptimeStr = [NSString stringWithFormat:@"%ldd %ldh %ldm", (long)days, (long)hours, (long)minutes];

    return [NSString stringWithFormat:
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Server Status</div>"
           @"<div class=\"stat-value\">"
           @"<span class=\"status-indicator connected\" style=\"display: inline-block; margin-right: 8px;\"></span>"
           @"Online"
           @"</div>"
           @"</div>"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Uptime</div>"
           @"<div class=\"stat-value\">%@</div>"
           @"</div>"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Database</div>"
           @"<div class=\"stat-value\">"
           @"<span class=\"status-indicator connected\" style=\"display: inline-block; margin-right: 8px;\"></span>"
           @"%@.0 KB"
           @"</div>"
           @"</div>", uptimeStr, @(metrics.databaseSizeBytes / 1024)];
}

- (NSString *)renderEmptyStateWithMessage:(NSString *)message suggestion:(NSString *)suggestion {
    return [NSString stringWithFormat:
            @"<tr>"
            @"<td colspan=\"6\" class=\"text-secondary text-center p-lg\">"
            @"<p style=\"margin: 0;\">%@</p>"
            @"<small class=\"text-secondary\" style=\"display: block; margin-top: 8px;\">%@</small>"
            @"</td>"
            @"</tr>", message, suggestion];
}

- (NSString *)renderTemplate:(NSString *)template withContext:(NSDictionary *)context {
    // Use basic template rendering for now
    NSMutableString *result = [NSMutableString stringWithString:template];

    // Process {{#each array}}...{{/each}}
    NSRegularExpression *eachRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{#each\\s+(\\w+)\\}\\}(.+?)\\{\\{/each\\}\\}"
                                                                                options:NSRegularExpressionDotMatchesLineSeparators
                                                                                  error:NULL];

    for (NSTextCheckingResult *match in [[eachRegex matchesInString:result options:0 range:NSMakeRange(0, result.length)] reverseObjectEnumerator]) {
        NSString *key = [result substringWithRange:[match rangeAtIndex:1]];
        NSString *itemTemplate = [result substringWithRange:[match rangeAtIndex:2]];
        NSString *replacement = @"";

        NSArray *items = context[key];
        if ([items isKindOfClass:[NSArray class]]) {
            NSMutableString *accumulated = [NSMutableString string];
            for (NSDictionary *item in items) {
                NSMutableString *itemResult = [NSMutableString stringWithString:itemTemplate];
                for (NSString *itemKey in item) {
                    NSString *placeholder = [NSString stringWithFormat:@"{{%@}}", itemKey];
                    NSString *value = [item[itemKey] description] ?: @"";
                    [itemResult replaceOccurrencesOfString:placeholder withString:value options:NSLiteralSearch range:NSMakeRange(0, itemResult.length)];
                }
                [accumulated appendString:itemResult];
            }
            replacement = accumulated;
        }

        [result replaceCharactersInRange:match.range withString:replacement];
    }

    // Process {{#if key}}...{{/if}}
    NSRegularExpression *ifRegex = [NSRegularExpression regularExpressionWithPattern:@"\\{\\{#if\\s+(\\w+)\\}\\}(.+?)\\{\\{/if\\}\\}"
                                                                             options:NSRegularExpressionDotMatchesLineSeparators
                                                                               error:NULL];

    for (NSTextCheckingResult *match in [[ifRegex matchesInString:result options:0 range:NSMakeRange(0, result.length)] reverseObjectEnumerator]) {
        NSString *key = [result substringWithRange:[match rangeAtIndex:1]];
        NSString *content = [result substringWithRange:[match rangeAtIndex:2]];
        NSString *replacement = @"";

        if (context[key] && [self isTruthy:context[key]]) {
            replacement = content;
        }

        [result replaceCharactersInRange:match.range withString:replacement];
    }

    // Process remaining {{key}} substitutions
    for (NSString *key in context) {
        NSString *placeholder = [NSString stringWithFormat:@"{{%@}}", key];
        NSString *value = [context[key] description] ?: @"";
        [result replaceOccurrencesOfString:placeholder withString:value options:NSLiteralSearch range:NSMakeRange(0, result.length)];
    }

    return [result copy];
}

- (BOOL)isTruthy:(NSObject *)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)value;
        return str.length > 0;
    }
    return value != nil && value != [NSNull null];
}

#pragma mark - Content Type Mapping

- (NSString *)renderPLCLookupPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>PLC DID Lookup</h2>"
           @"<p class=\"text-secondary\">Query the PLC directory for DID documents and history.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<form class=\"form\" hx-get=\"/api/pds/did\" hx-target=\"#plc-result\">"
           @"<div class=\"form-group\">"
           @"<label class=\"form-label\">DID</label>"
           @"<input type=\"text\" name=\"did\" class=\"form-input\" placeholder=\"did:plc:...\" required />"
           @"</div>"
           @"<button type=\"submit\" class=\"btn btn-primary\">Lookup</button>"
           @"</form>"
           @"<div id=\"plc-result\" class=\"mt-md\"></div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderPLCExportPartialWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>PLC Directory Export</h2>"
           @"<p class=\"text-secondary\">Download full or partial snapshots of the PLC directory.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<p>Exports are generated daily and available for download below.</p>"
           @"<div class=\"table-wrapper mt-md\">"
           @"<table class=\"table\">"
           @"<thead><tr><th>Date</th><th>Size</th><th>Action</th></tr></thead>"
           @"<tbody><tr><td colspan=\"3\" class=\"text-secondary text-center\">No exports available.</td></tr></tbody>"
           @"</table>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderPLCMetricsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>PLC Metrics</h2>"
           @"<p class=\"text-secondary\">Internal performance and health metrics for the PLC service.</p>"
           @"</div>"
           @"<div class=\"grid-3\">"
           @"<div class=\"stat-card\"><div class=\"stat-label\">Operations/sec</div><div class=\"stat-value\">0.0</div></div>"
           @"<div class=\"stat-card\"><div class=\"stat-label\">Total DIDs</div><div class=\"stat-value\">0</div></div>"
           @"<div class=\"stat-card\"><div class=\"stat-label\">Cache Hit Rate</div><div class=\"stat-value\">0%</div></div>"
           @"</div>";
}

- (NSString *)renderRelayUpstreamsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                          contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Relay Upstreams</h2>"
           @"<p class=\"text-secondary\">Manage PDS instances being crawled by this relay.</p>"
           @"</div>"
           @"<div class=\"table-wrapper\">"
           @"<table class=\"table\">"
           @"<thead><tr><th>Hostname</th><th>Status</th><th>Last Event</th><th>Actions</th></tr></thead>"
           @"<tbody><tr><td colspan=\"4\" class=\"text-secondary text-center\">No upstreams configured.</td></tr></tbody>"
           @"</table>"
           @"</div>";
}

- (NSString *)renderRelayEventsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Relay Event Stream</h2>"
           @"<p class=\"text-secondary\">Real-time view of events being processed by the relay.</p>"
           @"</div>"
           @"<div class=\"terminal-window\"><div class=\"terminal-content\" id=\"relay-log\">Connecting to stream...</div></div>";
}

- (NSString *)renderRelayCrawlPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Crawl Queue</h2>"
           @"<p class=\"text-secondary\">Monitor and manage the background crawling queue.</p>"
           @"</div>"
           @"<div class=\"stat-card mb-md\"><div class=\"stat-label\">Queue Depth</div><div class=\"stat-value\">0</div></div>";
}

- (NSString *)renderAppViewBackfillPartialWithStatusCode:(nullable NSInteger *)statusCode
                                           contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>AppView Backfill</h2>"
           @"<p class=\"text-secondary\">Track progress of historical data indexing.</p>"
           @"</div>"
           @"<div class=\"progress-bar\"><div class=\"progress-fill\" style=\"width: 0%\"></div></div>";
}

- (NSString *)renderAppViewIndexPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Index Status</h2>"
           @"<p class=\"text-secondary\">Status of the main AppView search and feed indexes.</p>"
           @"</div>"
           @"<ul class=\"list-group\">"
           @"<li class=\"list-item\"><span>Posts Index</span><span class=\"status-tag success\">Synced</span></li>"
           @"<li class=\"list-item\"><span>Profiles Index</span><span class=\"status-tag success\">Synced</span></li>"
           @"</ul>";
}

- (NSString *)renderAppViewMetricsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                          contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>AppView Metrics</h2>"
           @"<p class=\"text-secondary\">Query latency and indexing throughput metrics.</p>"
           @"</div>"
           @"<div class=\"grid-2\">"
           @"<div class=\"card\"><h4>Query Latency (p99)</h4><div class=\"stat-value\">12ms</div></div>"
           @"<div class=\"card\"><h4>Index Throughput</h4><div class=\"stat-value\">450 ev/s</div></div>"
           @"</div>";
}

- (NSString *)renderChatConvosPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Chat Conversations</h2>"
           @"<p class=\"text-secondary\">Monitor and manage active direct message conversations.</p>"
           @"</div>"
           @"<div class=\"table-wrapper\">"
           @"<table class=\"table\">"
           @"<thead><tr><th>ID</th><th>Members</th><th>Last Message</th><th>Actions</th></tr></thead>"
           @"<tbody><tr><td colspan=\"4\" class=\"text-secondary text-center\">No active conversations.</td></tr></tbody>"
           @"</table>"
           @"</div>";
}

- (NSString *)renderChatConvosSearchWithQuery:(NSString *)query
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    // This partial is meant to be called by HTMX for searching/filtering
    return [self renderChatConvosPartialWithStatusCode:statusCode contentType:contentType];
}

- (NSString *)renderChatGroupsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Chat Groups</h2>"
           @"<p class=\"text-secondary\">Monitor and manage group chat definitions.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/chat/groups/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary\">Loading groups...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderChatGroupsSearchWithQuery:(NSString *)query
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return [self renderChatGroupsPartialWithStatusCode:statusCode contentType:contentType];
}

- (NSString *)renderChatGroupDetailPartialWithGroupUri:(NSString *)groupUri
                                          statusCode:(nullable NSInteger *)statusCode
                                         contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    return [NSString stringWithFormat:
           @"<div class=\"mb-md\"><button class=\"btn\" hx-get=\"/admin/partials/chat/groups\" hx-target=\"#content-pane\">◀ Back to Groups</button></div>"
           @"<div class=\"card\"><div class=\"card-header\"><h3>Group Detail: %@</h3></div>"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/chat/groups/data?groupUri=%@\" hx-trigger=\"load\">Loading...</div>"
           @"</div></div>", groupUri, [groupUri stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
}

- (NSString *)renderChatInviteLinksPartialWithStatusCode:(nullable NSInteger *)statusCode
                                           contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Group Invite Links</h2>"
           @"<p class=\"text-secondary\">Audit and revoke active group join links.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/chat/invite-links/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary\">Loading invite links...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderChatInviteLinksSearchWithQuery:(NSString *)query
                                    statusCode:(nullable NSInteger *)statusCode
                                   contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return [self renderChatInviteLinksPartialWithStatusCode:statusCode contentType:contentType];
}

- (NSString *)renderChatMessagesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Chat Messages</h2>"
           @"<p class=\"text-secondary\">Audit recent messages across all conversations.</p>"
           @"</div>"
           @"<div class=\"terminal-window\"><div class=\"terminal-content\" id=\"message-log\">Awaiting message stream...</div></div>";
}

- (NSString *)renderChatReportsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Chat Reports</h2>"
           @"<p class=\"text-secondary\">Review and resolve user reports for chat content.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-header\"><h3 class=\"card-title\">Active Reports</h3></div>"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/chat/reports/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary\">Loading reports...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderChatReportsListWithStatusCode:(nullable NSInteger *)statusCode
                                     contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    // In a real app, this would fetch from ChatService
    return @"<div class=\"table-wrapper\">"
           @"<table class=\"table\">"
           @"<thead><tr><th>Report ID</th><th>Subject</th><th>Reporter</th><th>Reason</th><th>Status</th></tr></thead>"
           @"<tbody><tr><td colspan=\"5\" class=\"text-secondary text-center\">No active chat reports.</td></tr></tbody>"
           @"</table>"
           @"</div>";
}

- (NSString *)renderOzoneEventsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                         contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Moderation Events</h2>"
           @"<p class=\"text-secondary\">Audit log of all moderation actions taken via Ozone.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/ozone/events/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary text-center\">Loading events...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderOzoneStatusesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                           contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Subject Statuses</h2>"
           @"<p class=\"text-secondary\">Current moderation state of actors and records.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/ozone/statuses/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary text-center\">Loading statuses...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderOzoneTeamPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Ozone Team</h2>"
           @"<p class=\"text-secondary\">Manage members of the moderation team.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/ozone/team/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary text-center\">Loading team members...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderOzoneTemplatesPartialWithStatusCode:(nullable NSInteger *)statusCode
                                            contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Communication Templates</h2>"
           @"<p class=\"text-secondary\">Standardized responses for user outreach.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/ozone/templates/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary text-center\">Loading templates...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderSecuritySessionsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                              contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Active Sessions</h2>"
           @"<p class=\"text-secondary\">Monitor and revoke active user sessions and refresh tokens.</p>"
           @"</div>"
           @"<div class=\"card mb-lg\">"
           @"<div class=\"card-body\">"
           @"<form class=\"form flex gap-md\" hx-get=\"/admin/partials/security/sessions/list\" hx-target=\"#session-list-container\">"
           @"<div class=\"form-group flex-1\">"
           @"<input type=\"text\" name=\"did\" class=\"form-input\" placeholder=\"Enter DID (did:plc:...)\" required />"
           @"</div>"
           @"<button type=\"submit\" class=\"btn btn-primary\">List Sessions</button>"
           @"</form>"
           @"</div>"
           @"</div>"
           @"<div id=\"session-list-container\"></div>";
}

- (NSString *)renderSecurityAppPasswordsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                                 contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Application Passwords</h2>"
           @"<p class=\"text-secondary\">Audit and manage application passwords for user accounts.</p>"
           @"</div>"
           @"<div class=\"card mb-lg\">"
           @"<div class=\"card-body\">"
           @"<form class=\"form flex gap-md\" hx-get=\"/admin/partials/security/app-passwords/list\" hx-target=\"#app-password-list-container\">"
           @"<div class=\"form-group flex-1\">"
           @"<input type=\"text\" name=\"did\" class=\"form-input\" placeholder=\"Enter DID (did:plc:...)\" required />"
           @"</div>"
           @"<button type=\"submit\" class=\"btn btn-primary\">List Passwords</button>"
           @"</form>"
           @"</div>"
           @"</div>"
           @"<div id=\"app-password-list-container\"></div>";
}

- (NSString *)renderOzoneSetsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                       contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Moderation Sets</h2>"
           @"<p class=\"text-secondary\">Group subjects together for bulk moderation actions.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div hx-get=\"/admin/partials/ozone/sets/list\" hx-trigger=\"load\">"
           @"<p class=\"text-secondary text-center\">Loading sets...</p>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderOzoneCorrelationsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Account Correlations</h2>"
           @"<p class=\"text-secondary\">Detect sybil accounts using shared metadata signatures.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<form class=\"form\" hx-get=\"/admin/partials/ozone/correlations/search\" hx-target=\"#correlation-results\">"
           @"<div class=\"form-group\">"
           @"<label class=\"form-label\">Subject DID</label>"
           @"<input type=\"text\" name=\"did\" class=\"form-input\" placeholder=\"did:plc:...\" required />"
           @"</div>"
           @"<button type=\"submit\" class=\"btn btn-primary\">Find Related Accounts</button>"
           @"</form>"
           @"<div id=\"correlation-results\" class=\"mt-lg\"></div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderOzoneVerificationPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<div class=\"content-header\">"
           @"<h2>Verification Status</h2>"
           @"<p class=\"text-secondary\">Manage account verification badges and authenticity.</p>"
           @"</div>"
           @"<div class=\"card\">"
           @"<div class=\"card-body\">"
           @"<div class=\"table-wrapper\">"
           @"<table class=\"table\">"
           @"<thead><tr><th>Account</th><th>Verified Since</th><th>Actions</th></tr></thead>"
           @"<tbody><tr><td colspan=\"3\" class=\"text-secondary text-center\">No verified accounts found.</td></tr></tbody>"
           @"</table>"
           @"</div>"
           @"</div>"
           @"</div>";
}

- (NSString *)renderSecuritySessionsListPartialWithParams:(NSDictionary *)params
                                              statusCode:(nullable NSInteger *)statusCode
                                             contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<p>Security sessions list data should be handled by template handler</p>";
}

- (NSString *)renderSecurityAppPasswordsListPartialWithParams:(NSDictionary *)params
                                                 statusCode:(nullable NSInteger *)statusCode
                                                contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    return @"<p>App passwords list data should be handled by template handler</p>";
}

- (NSString *)renderOzoneCorrelationsSearchWithDid:(NSString *)did
                                         statusCode:(nullable NSInteger *)statusCode
                                        contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    if (!did) return @"<p class=\"text-error\">Missing DID</p>";
    
    // In a real app, this would query tools.ozone.signature.findRelatedAccounts
    return [NSString stringWithFormat:
           @"<div class=\"alert alert-info\">No exact correlations found for <code>%@</code></div>"
           @"<div class=\"mt-md\"><h4>Heuristic Matches</h4>"
           @"<ul class=\"list-group\"><li class=\"list-item text-secondary\">No other accounts found sharing IP or metadata.</li></ul></div>", did];
}

- (NSString *)contentTypeForExtension:(NSString *)extension {
    static NSDictionary *mimeTypes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mimeTypes = @{
            @"html": @"text/html; charset=utf-8",
            @"css": @"text/css",
            @"js": @"application/javascript",
            @"json": @"application/json",
            @"svg": @"image/svg+xml",
            @"png": @"image/png",
            @"jpg": @"image/jpeg",
            @"jpeg": @"image/jpeg",
            @"gif": @"image/gif",
            @"webp": @"image/webp",
            @"woff": @"font/woff",
            @"woff2": @"font/woff2",
            @"ttf": @"font/ttf",
            @"txt": @"text/plain",
        };
    });

    return mimeTypes[extension.lowercaseString] ?: @"application/octet-stream";
}

#pragma mark - Diagnostics Partials

- (NSString *)renderDiagnosticsOverviewPartialWithStatusCode:(nullable NSInteger *)statusCode
                                               contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    NSString *html = [NSString stringWithFormat:@"%@%@%@%@",
        @"<div class=\"content-header\">",
        @"<h1>System Diagnostics</h1>",
        @"<p class=\"text-secondary mt-sm\">Monitor sequencer health, blob storage, and rate limits.</p>",
        @"</div>"
    ];
    return html;
}

- (NSString *)renderDiagnosticsSequencerPartialWithStatusCode:(nullable NSInteger *)statusCode
                                                 contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    NSString *html = [NSString stringWithFormat:@"%@%@%@",
        @"<div class=\"content-header\"><h2>Sequencer Health</h2></div>",
        @"<div class=\"card\">",
        @"<p>Sequencer health dashboard - loading...</p></div>"
    ];
    return html;
}

- (NSString *)renderDiagnosticsBlobsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                             contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    NSString *html = [NSString stringWithFormat:@"%@%@%@",
        @"<div class=\"content-header\"><h2>Blob Audits</h2></div>",
        @"<div class=\"card\">",
        @"<p>Blob audit dashboard - loading...</p></div>"
    ];
    return html;
}

- (NSString *)renderDiagnosticsRateLimitsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";

    NSString *html = [NSString stringWithFormat:@"%@%@%@",
        @"<div class=\"content-header\"><h2>Rate Limit Management</h2></div>",
        @"<div class=\"card\">",
        @"<p>Rate limit management dashboard - loading...</p></div>"
    ];
    return html;
}

#pragma mark - User Detail View

- (NSString *)renderUsersDetailWithDid:(NSString *)did
                             statusCode:(nullable NSInteger *)statusCode
                          contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    if (!did || did.length == 0) {
        return @"<div class=\"card\"><p class=\"text-destructive\">No DID provided</p></div>";
    }
    
    // Get user data from AdminPartialHandler
    AdminPartialHandler *partialHandler = [AdminPartialHandler sharedHandler];
    NSDictionary *userData = [partialHandler getUserDetailForDid:did];
    if (!userData) {
        return [NSString stringWithFormat:@"<div class=\"card\"><p class=\"text-destructive\">User not found: %@</p></div>", did];
    }
    
    // Render using AdminPartialHandler's template system
    return [partialHandler renderPartialWithTemplate:@"users-detail" context:userData];
}

#pragma mark - Moderation Reports

- (NSString *)renderReportsPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    return @"<div class=\"content-header\">"
           @"<h2>Moderation Reports</h2>"
           @"<p class=\"text-secondary\">View and resolve user-submitted reports.</p>"
           @"</div>"
           @"<div id=\"reports-list\" hx-get=\"/admin/partials/reports/list\" hx-trigger=\"load\">"
           @"<p>Loading reports...</p>"
           @"</div>";
}

- (NSString *)renderReportsListWithStatusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    // Get reports from AdminPartialHandler
    AdminPartialHandler *partialHandler = [AdminPartialHandler sharedHandler];
    NSArray *reports = [partialHandler getModerationReports];
    
    if (!reports || reports.count == 0) {
        return @"<div class=\"card\"><p class=\"text-secondary\">No reports found.</p></div>";
    }
    
    NSMutableString *html = [NSMutableString stringWithString:
        @"<div class=\"table-wrapper\">"
        @"<table class=\"table\">"
        @"<thead><tr>"
        @"<th>ID</th><th>Reason</th><th>Subject</th><th>Reporter</th><th>Status</th><th>Created</th><th>Actions</th>"
        @"</tr></thead><tbody>"];
    
    for (NSDictionary *report in reports) {
        [html appendFormat:
            @"<tr>"
            @"<td><code>%@</code></td>"
            @"<td>%@</td>"
            @"<td><code style=\"font-size: 11px;\">%@</code></td>"
            @"<td>%@</td>"
            @"<td><span class=\"badge %@\">%@</span></td>"
            @"<td><small>%@</small></td>"
            @"<td>"
            @"<button class=\"btn btn-sm btn-secondary\" hx-get=\"/admin/reports/%@\" hx-target=\"#detail-modal\" hx-on=\"htmx:afterSettle: document.getElementById('detail-modal').showModal()\">View</button>"
            @"</td>"
            @"</tr>",
            report[@"id"] ?: @"",
            report[@"reason"] ?: @"",
            report[@"subject"] ?: @"",
            report[@"reporter"] ?: @"",
            [report[@"resolved"] boolValue] ? @"badge-success" : @"badge-warning",
            [report[@"resolved"] boolValue] ? @"Resolved" : @"Open",
            report[@"createdAt"] ?: @"",
            report[@"id"] ?: @""];
    }
    
    [html appendString:@"</tbody></table></div>"];
    return html;
}

#pragma mark - Audit Log

- (NSString *)renderAuditLogPartialWithStatusCode:(nullable NSInteger *)statusCode
                                      contentType:(NSString * _Nullable * _Nullable)contentType {
    if (statusCode) *statusCode = 200;
    if (contentType) *contentType = @"text/html";
    
    // Get audit log data
    PDSAdminHandler *adminHandler = [PDSAdminHandler sharedHandler];
    NSDictionary *auditData = [adminHandler getAuditLogDataWithAdminDid:nil limit:100 cursor:nil];
    
    NSMutableString *html = [NSMutableString stringWithString:
        @"<div class=\"content-header\">"
        @"<h2>Audit Log</h2>"
        @"<p class=\"text-secondary\">View admin action history and account changes.</p>"
        @"</div>"];
    
    if (!auditData) {
        [html appendString:@"<div class=\"card\"><p class=\"text-secondary\">No audit log data available.</p></div>"];
        return html;
    }
    
    // Render filter form
    [html appendString:
        @"<div class=\"card mb-lg\">"
        @"<div class=\"card-body\">"
        @"<form class=\"form\" style=\"display: flex; gap: 16px; align-items: end;\">"
        @"<div class=\"form-group\">"
        @"<label class=\"form-label\">Admin DID</label>"
        @"<input type=\"text\" name=\"adminDid\" class=\"form-input\" placeholder=\"did:plc:...\" />"
        @"</div>"
        @"<div class=\"form-group\">"
        @"<label class=\"form-label\">Limit</label>"
        @"<select name=\"limit\" class=\"form-input\">"
        @"<option value=\"50\">50</option>"
        @"<option value=\"100\" selected>100</option>"
        @"<option value=\"200\">200</option>"
        @"</select>"
        @"</div>"
        @"<div class=\"form-group\">"
        @"<button type=\"submit\" class=\"btn btn-primary\">Filter</button>"
        @"</div>"
        @"</form>"
        @"</div>"
        @"</div>"];
    
    // Render table
    [html appendString:
        @"<div class=\"table-wrapper\">"
        @"<table class=\"table\">"
        @"<thead><tr>"
        @"<th>Timestamp</th><th>Admin</th><th>Action</th><th>Subject</th><th>Details</th>"
        @"</tr></thead><tbody>"];
    
    NSArray *logs = auditData[@"logs"] ?: auditData[@"audit_logs"] ?: @[];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterShortStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    
    for (NSDictionary *entry in logs) {
        NSString *timestamp = entry[@"createdAt"] ?: @"";
        NSString *admin = entry[@"createdBy"] ?: entry[@"admin_did"] ?: @"";
        NSString *action = entry[@"action"] ?: @"";
        NSString *subject = entry[@"subject"] ?: entry[@"subject_did"] ?: @"";
        
        // Format details as JSON
        NSDictionary *details = entry[@"details"] ?: @{};
        NSString *detailsStr = @"";
        if (details.count > 0) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:details options:0 error:nil];
            if (jsonData) {
                detailsStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }
        
        [html appendFormat:
            @"<tr>"
            @"<td><small>%@</small></td>"
            @"<td><code style=\"font-size: 11px;\">%@</code></td>"
            @"<td><span class=\"badge badge-secondary\">%@</span></td>"
            @"<td><code style=\"font-size: 11px;\">%@</code></td>"
            @"<td><small style=\"word-break: break-all;\">%@</small></td>"
            @"</tr>",
            timestamp, admin, action, subject, detailsStr];
    }
    
    if (logs.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-secondary text-center\">No audit entries found.</td></tr>"];
    }
    
    [html appendString:@"</tbody></table></div>"];
    
    // Add cursor for pagination if available
    NSString *cursor = auditData[@"cursor"];
    if (cursor && cursor.length > 0) {
        [html appendFormat:
            @"<div class=\"mt-md\">"
            @"<button class=\"btn btn-secondary\" hx-get=\"/admin/partials/audit-log?cursor=%@\" hx-target=\".table-wrapper tbody\">Load More</button>"
            @"</div>", cursor];
    }
    
    return html;
}

@end

NS_ASSUME_NONNULL_END
