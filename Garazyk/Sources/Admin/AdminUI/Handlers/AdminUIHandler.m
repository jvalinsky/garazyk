#import <Foundation/Foundation.h>
#import "AdminUIHandler.h"

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
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    return [bundlePath stringByAppendingPathComponent:@"AdminUI/Assets"];
}

- (NSString *)templatesDirectoryPath {
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

    // Root admin UI entry point
    if ([path isEqualToString:@"/admin/ui"] || [path isEqualToString:@"/admin/ui/"]) {
        return [self handleRootPath:statusCode contentType:contentType];
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
    NSString *partial = [path stringByReplacingOccurrencesOfString:@"/admin/partials/"
                                                         withString:@""];

    // Parse query parameters from path
    NSDictionary *params = [self parseQueryString:path];

    if ([partial isEqualToString:@"users"]) {
        return [self renderUsersPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"users/search"]) {
        NSString *query = params[@"q"] ?: @"";
        return [self renderUsersSearchWithQuery:query statusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"invites"]) {
        return [self renderInvitesPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"identity"]) {
        return [self renderIdentityPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"health"]) {
        return [self renderHealthPartialWithStatusCode:statusCode contentType:contentType];
    } else if ([partial isEqualToString:@"health/status"]) {
        return [self renderHealthStatusWithStatusCode:statusCode contentType:contentType];
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

    return @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Server Status</div>"
           @"<div class=\"stat-value\">"
           @"<span class=\"status-indicator connected\" style=\"display: inline-block; margin-right: 8px;\"></span>"
           @"Online"
           @"</div>"
           @"</div>"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Uptime</div>"
           @"<div class=\"stat-value\">24d 5h 32m</div>"
           @"</div>"
           @"<div class=\"stat-card\">"
           @"<div class=\"stat-label\">Database</div>"
           @"<div class=\"stat-value\">"
           @"<span class=\"status-indicator connected\" style=\"display: inline-block; margin-right: 8px;\"></span>"
           @"Connected"
           @"</div>"
           @"</div>";
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

- (NSString *)contentTypeForExtension:(NSString *)extension {
    static NSDictionary *mimeTypes = nil;
    if (!mimeTypes) {
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
    }

    return mimeTypes[extension.lowercaseString] ?: @"application/octet-stream";
}

@end

NS_ASSUME_NONNULL_END
