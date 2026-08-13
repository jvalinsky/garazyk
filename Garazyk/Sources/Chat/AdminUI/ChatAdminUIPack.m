// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Chat/AdminUI/ChatAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZAdminUIDTOProjection.h"
#import "AdminUIServer/GZHTML.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@interface GZChatAdminUIBackendConfig : NSObject
@property (nonatomic, strong) NSURL *serviceBaseURL;
@property (nonatomic, copy) NSString *adminSecret;
@end

@implementation GZChatAdminUIBackendConfig
@end

@implementation GZChatAdminUIPack

+ (NSMapTable<GZAdminUIHost *, GZChatAdminUIBackendConfig *> *)backends {
    static NSMapTable<GZAdminUIHost *, GZChatAdminUIBackendConfig *> *backends;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        backends = [NSMapTable weakToStrongObjectsMapTable];
    });
    return backends;
}

+ (void)configureHost:(GZAdminUIHost *)host
       serviceBaseURL:(NSURL *)serviceBaseURL
          adminSecret:(NSString *)adminSecret {
    if (!host || serviceBaseURL.absoluteString.length == 0 || adminSecret.length == 0) {
        return;
    }
    GZChatAdminUIBackendConfig *cfg = [[GZChatAdminUIBackendConfig alloc] init];
    cfg.serviceBaseURL = serviceBaseURL;
    cfg.adminSecret = adminSecret;
    @synchronized(self) {
        [[self backends] setObject:cfg forKey:host];
    }
}

+ (nullable GZChatAdminUIBackendConfig *)backendForHost:(GZAdminUIHost *)host {
    if (!host) {
        return nil;
    }
    @synchronized(self) {
        return [[self backends] objectForKey:host];
    }
}

+ (NSString *)packIdentifier { return @"chat"; }
+ (NSString *)displayName { return @"Chat"; }

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"chat", @"displayName": @"Chat"}];
}

+ (NSString *)errorUnavailableHTML {
    return [GZHTML alertWithType:@"warning"
                         message:@"Chat dashboard unavailable — configure the embedded listener with CHAT_ADMIN_PASSWORD."];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    __weak GZAdminUIHost *weakHost = host;

    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:[self chatOverviewHTML]];
    }];

    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-stats" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *stats = [self fetchLiveStatsForHost:weakHost];
        if (stats[@"error"]) {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:stats[@"message"] ?: @"Stats unavailable."]];
        } else {
            [res setBodyString:[self statsHTML:stats]];
        }
    }];

    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-convos" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *convos = [self fetchLiveConvosForHost:weakHost
                                                     cursor:[req queryParamForKey:@"cursor"]];
        if (convos[@"error"]) {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:convos[@"message"] ?: @"Conversation data unavailable."]];
        } else if (convos) {
            [res setBodyString:[self convosHTML:convos]];
        } else {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:@"Conversation data unavailable — Chat service may not be running."]];
        }
    }];

    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-messages" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *convoID = [req queryParamForKey:@"convoID"];
        if (convoID.length == 0) {
            [res setBodyString:[GZHTML alertWithType:@"warning" message:@"Enter a conversation ID to view message metadata."]];
            return;
        }
        NSDictionary *msgs = [self fetchLiveMessagesForHost:weakHost
                                                    convoID:convoID
                                                     cursor:[req queryParamForKey:@"cursor"]];
        if (msgs[@"error"]) {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:msgs[@"message"] ?: @"Message metadata unavailable."]];
        } else if (msgs) {
            [res setBodyString:[self messagesHTML:msgs convoID:convoID]];
        } else {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:@"Message metadata unavailable — Chat service may not be running."]];
        }
    }];

    [host.httpServer addRoute:@"POST" path:@"/admin/actions/chat-lock" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *convoID = [req.jsonBody[@"convoId"] isKindOfClass:[NSString class]] ? req.jsonBody[@"convoId"] : [req queryParamForKey:@"convoId"];
        NSDictionary *result = [self postAdminActionForHost:weakHost path:@"/_admin/lock" convoID:convoID ?: @""];
        res.statusCode = result[@"error"] ? 400 : 200;
        [res setBodyString:[self actionResultHTML:result success:@"Conversation locked."]];
    }];

    [host.httpServer addRoute:@"POST" path:@"/admin/actions/chat-unlock" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *convoID = [req.jsonBody[@"convoId"] isKindOfClass:[NSString class]] ? req.jsonBody[@"convoId"] : [req queryParamForKey:@"convoId"];
        NSDictionary *result = [self postAdminActionForHost:weakHost path:@"/_admin/unlock" convoID:convoID ?: @""];
        res.statusCode = result[@"error"] ? 400 : 200;
        [res setBodyString:[self actionResultHTML:result success:@"Conversation unlocked."]];
    }];
}

#pragma mark - Live data fetchers

+ (nullable NSDictionary *)gz_getJSONFromHost:(GZAdminUIHost *)host
                                         path:(NSString *)path
                                        query:(nullable NSString *)query {
    return [self gz_requestJSONFromHost:host method:@"GET" path:path query:query body:nil];
}

+ (nullable NSDictionary *)gz_requestJSONFromHost:(GZAdminUIHost *)host
                                           method:(NSString *)method
                                             path:(NSString *)path
                                            query:(nullable NSString *)query
                                             body:(nullable NSDictionary *)body {
    GZChatAdminUIBackendConfig *cfg = [self backendForHost:host];
    if (!cfg) {
        return @{
            @"error": @"not_configured",
            @"message": @"Chat admin backend is not configured on this host."
        };
    }
    NSString *urlStr = [cfg.serviceBaseURL.absoluteString stringByAppendingString:path];
    if (query.length > 0) {
        urlStr = [urlStr stringByAppendingFormat:@"?%@", query];
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method.length > 0 ? method : @"GET";
    request.timeoutInterval = 15.0;
    if ([cfg.adminSecret rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location == NSNotFound) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", cfg.adminSecret]
       forHTTPHeaderField:@"Authorization"];
    }
    if (body) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        request.HTTPBody = json;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.allowHTTP = YES;
    options.allowPrivateHosts = YES;
    NSHTTPURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                        options:options
                                                                       response:&response
                                                                          error:&error];
    if (!data || response.statusCode < 200 || response.statusCode >= 300) {
        NSString *message = error.localizedDescription ?:
            [NSString stringWithFormat:@"Chat admin HTTP %ld", (long)response.statusCode];
        return @{@"error": @"fetch_failed", @"message": message};
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

+ (NSDictionary *)fetchLiveStatsForHost:(GZAdminUIHost *)host {
    return [self gz_getJSONFromHost:host path:@"/_admin/stats" query:nil] ?: @{};
}

+ (NSDictionary *)postAdminActionForHost:(GZAdminUIHost *)host
                                    path:(NSString *)path
                                 convoID:(NSString *)convoID {
    if (convoID.length == 0) {
        return @{@"error": @"convo_id_required", @"message": @"Conversation ID is required."};
    }
    return [self gz_requestJSONFromHost:host
                                 method:@"POST"
                                   path:path
                                  query:nil
                                   body:@{@"convoId": convoID}] ?: @{};
}

+ (NSDictionary *)fetchLiveConvosForHost:(GZAdminUIHost *)host cursor:(NSString *)cursor {
    NSMutableString *query = [NSMutableString stringWithString:@"limit=25"];
    if (cursor.length > 0) {
        NSString *enc = [cursor stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
        [query appendFormat:@"&cursor=%@", enc];
    }
    return [self gz_getJSONFromHost:host path:@"/_admin/convos" query:query] ?: @{};
}

+ (NSDictionary *)fetchLiveMessagesForHost:(GZAdminUIHost *)host
                                   convoID:(NSString *)convoID
                                    cursor:(NSString *)cursor {
    NSString *encID = [convoID stringByAddingPercentEncodingWithAllowedCharacters:
                       [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
    NSMutableString *query = [NSMutableString stringWithFormat:@"convoId=%@&limit=50", encID];
    if (cursor.length > 0) {
        NSString *enc = [cursor stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
        [query appendFormat:@"&cursor=%@", enc];
    }
    return [self gz_getJSONFromHost:host path:@"/_admin/messages" query:query] ?: @{};
}

#pragma mark - HTML renderers

+ (NSString *)chatOverviewHTML {
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Overview"]];
    [html appendString:@"<div id=\"chat-stats\" hx-get=\"/admin/partials/chat-stats\" hx-trigger=\"revealed, every 15s\"></div>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Operator posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Privacy", @"value": @"Metadata only — no message bodies"},
        @{@"label": @"Encryption", @"value": @"E2EE and plaintext conversations supported"},
        @{@"label": @"Admin API", @"value": @"Bearer-gated /_admin stats, convos, messages, lock"},
        @{@"label": @"Actions", @"value": @"Lock / unlock conversation (audited server-side)"},
    ]]];
    [html appendString:@"</section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Conversations"]];
    [html appendString:@"<div id=\"chat-action-result\" aria-live=\"polite\"></div>"];
    [html appendString:@"<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"revealed, every 10s\"></div></section>"];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Message metadata"]];
    [html appendString:@"<div class=\"search-row\">"
     @"<form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/chat-messages\" hx-target=\"#chat-messages\">"
     @"<label class=\"sr-only\" for=\"chat-convo-id\">Conversation ID</label>"
     @"<input id=\"chat-convo-id\" type=\"text\" name=\"convoID\" placeholder=\"Conversation ID\" class=\"form-input flex-1\"/>"
     @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Look up</button>"
     @"</form></div>"
     @"<div id=\"chat-messages\" class=\"mt-md\"></div></section>"];
    return html;
}

+ (NSString *)statsHTML:(NSDictionary *)stats {
    NSDictionary *projected = GZAdminUIProjectDictionary(stats, @[
        @"health", @"uptimeSeconds",
        @"conversationsTotal", @"conversationsLocked",
        @"conversationsE2EE", @"conversationsPlaintext",
        @"membersActive", @"messagesTotal", @"database"
    ]);
    NSDictionary *database = [stats[@"database"] isKindOfClass:[NSDictionary class]]
        ? GZAdminUIProjectDictionary(stats[@"database"], @[@"storageBytes"])
        : @{};
    NSMutableArray *fields = [NSMutableArray array];
    if (projected[@"health"]) {
        [fields addObject:@{@"label": @"Health", @"html": [GZHTML healthBadge:projected[@"health"]]}];
    }
    if (projected[@"uptimeSeconds"]) {
        [fields addObject:@{
            @"label": @"Uptime",
            @"html": [GZHTML monoValue:[GZHTML formatUptime:[projected[@"uptimeSeconds"] longLongValue]]]
        }];
    }
    [fields addObject:@{@"label": @"Conversations", @"html": [GZHTML monoValue:projected[@"conversationsTotal"] ?: @0]}];
    [fields addObject:@{@"label": @"Locked", @"html": [GZHTML monoValue:projected[@"conversationsLocked"] ?: @0]}];
    [fields addObject:@{@"label": @"E2EE / plaintext", @"html": [GZHTML monoValue:
        [NSString stringWithFormat:@"%@ / %@",
         projected[@"conversationsE2EE"] ?: @0,
         projected[@"conversationsPlaintext"] ?: @0]]}];
    [fields addObject:@{@"label": @"Active members", @"html": [GZHTML monoValue:projected[@"membersActive"] ?: @0]}];
    [fields addObject:@{@"label": @"Messages", @"html": [GZHTML monoValue:projected[@"messagesTotal"] ?: @0]}];
    if (database[@"storageBytes"]) {
        [fields addObject:@{
            @"label": @"Database",
            @"html": [GZHTML monoValue:[GZHTML formatMegabytes:[database[@"storageBytes"] longLongValue]]]
        }];
    }
    return [GZHTML detailCardWithFields:fields];
}

+ (NSString *)actionResultHTML:(NSDictionary *)result success:(NSString *)success {
    if (result[@"error"]) {
        return [GZHTML alertWithType:@"destructive"
                             message:result[@"message"] ?: result[@"error"]];
    }
    return [GZHTML alertWithType:@"success" message:success];
}

+ (NSString *)convosHTML:(NSDictionary *)data {
    NSArray *raw = data[@"convos"];
    NSArray<NSDictionary *> *convos = GZAdminUIProjectDictionaries(raw, @[
        @"id", @"mode", @"locked", @"memberCount", @"createdAt", @"updatedAt", @"lastMessage"
    ]);
    if (convos.count == 0) {
        return [GZHTML alertWithType:@"info" message:@"No conversations found."];
    }

    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:convos.count];
    for (NSDictionary *c in convos) {
        NSString *memberCount = [c[@"memberCount"] description] ?: @"0";
        NSString *sentAt = @"—";
        id lastMsg = c[@"lastMessage"];
        if ([lastMsg isKindOfClass:[NSDictionary class]]) {
            NSDictionary *safeLast = GZAdminUIProjectDictionary(lastMsg, @[@"createdAt", @"senderDid", @"id", @"mode"]);
            sentAt = [safeLast[@"createdAt"] description] ?: @"—";
        }
        BOOL locked = [c[@"locked"] boolValue];
        NSString *cid = c[@"id"] ?: @"";
        NSString *actionPath = locked ? @"/admin/actions/chat-unlock" : @"/admin/actions/chat-lock";
        NSString *actionLabel = locked ? @"Unlock" : @"Lock";
        NSString *btnClass = locked ? @"btn btn-secondary btn-sm" : @"btn btn-destructive btn-sm";
        NSString *actionHTML = [NSString stringWithFormat:
            @"<button type=\"button\" class=\"%@\" "
            @"hx-post=\"%@?convoId=%@\" "
            @"hx-target=\"#chat-action-result\" hx-swap=\"innerHTML\">%@</button>",
            btnClass, actionPath,
            [cid stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"",
            actionLabel];

        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:cid.length ? cid : @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:c[@"mode"] ?: @"—" className:nil],
            [GZHTML tableCellWithText:locked ? @"locked" : @"open" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:memberCount className:@"text-right text-mono"],
            [GZHTML tableCellWithText:sentAt className:@"text-mono text-sm"],
            [NSString stringWithFormat:@"<td>%@</td>", actionHTML],
        ]]];
    }

    NSMutableString *html = [NSMutableString stringWithString:
        [GZHTML tableWithHeaders:@[@"ID", @"Mode", @"State", @"Members", @"Last activity", @"Action"]
                        htmlRows:rows
                   emptyMessage:@"No conversations found."]];

    NSString *cursor = GZAdminUIStringFromDict(data, @"cursor");
    if (cursor.length > 0) {
        [html appendString:[GZHTML paginationButtonWithHref:
            [NSString stringWithFormat:@"/admin/partials/chat-convos?cursor=%@", cursor]
                                                     target:@"#chat-convos"
                                                      label:@"Load more"]];
    }
    return html;
}

+ (NSString *)messagesHTML:(NSDictionary *)data convoID:(NSString *)convoID {
    NSArray *raw = data[@"messages"];
    NSArray<NSDictionary *> *msgs = GZAdminUIProjectDictionaries(raw, @[
        @"id", @"senderDid", @"createdAt", @"mode"
    ]);
    if (msgs.count == 0) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-info\">No message metadata for %@.</div>",
            [GZHTML monoValue:convoID]];
    }

    NSMutableString *html = [NSMutableString string];
    [html appendFormat:@"<p class=\"text-secondary text-sm mb-md\">Conversation %@ — %lu metadata rows</p>",
        [GZHTML monoValue:convoID], (unsigned long)msgs.count];

    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:msgs.count];
    for (NSDictionary *m in msgs) {
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:m[@"id"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:m[@"senderDid"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:m[@"createdAt"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:m[@"mode"] ?: @"—" className:nil],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"ID", @"Sender", @"Sent at", @"Mode"]
                                       htmlRows:rows
                                  emptyMessage:@"No messages."]];

    NSString *cursor = GZAdminUIStringFromDict(data, @"cursor");
    if (cursor.length > 0) {
        [html appendString:[GZHTML paginationButtonWithHref:
            [NSString stringWithFormat:@"/admin/partials/chat-messages?convoID=%@&cursor=%@", convoID, cursor]
                                                     target:@"#chat-messages"
                                                      label:@"Load more"]];
    }
    return html;
}

@end
