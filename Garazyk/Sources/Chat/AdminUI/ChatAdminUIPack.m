// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Chat/AdminUI/ChatAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

static NSString *const kChatServiceBase = @"http://127.0.0.1:2585";

@implementation ChatAdminUIPack

+ (NSString *)packIdentifier { return @"chat"; }
+ (NSString *)displayName { return @"Chat"; }

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"chat", @"displayName": @"Chat"}];
}

+ (NSString *)errorUnavailableHTML {
    return @"<div class=\"alert alert-warning\">Chat dashboard unavailable — embedded listener required.</div>";
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    __weak GZAdminUIHost *weakHost = host;

    // Overview
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:[self chatOverviewHTML]];
    }];

    // Conversations (live fetch from Chat service admin endpoint)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-convos" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSDictionary *convos = [self fetchLiveConvosWithCursor:[req queryParamForKey:@"cursor"]];
        if (convos) {
            [res setBodyString:[self convosHTML:convos]];
        } else {
            [res setBodyString:@"<div class=\"alert alert-warning\">Conversation data unavailable — Chat service may not be running.</div>"];
        }
    }];

    // Messages lookup (live fetch from Chat service admin endpoint)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-messages" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *convoID = [req queryParamForKey:@"convoID"];
        if (convoID.length == 0) {
            [res setBodyString:@"<div class=\"alert alert-warning\">Enter a conversation ID to view messages.</div>"];
            return;
        }
        NSDictionary *msgs = [self fetchLiveMessagesForConvoID:convoID cursor:[req queryParamForKey:@"cursor"]];
        if (msgs) {
            [res setBodyString:[self messagesHTML:msgs convoID:convoID]];
        } else {
            [res setBodyString:@"<div class=\"alert alert-warning\">Message data unavailable — Chat service may not be running.</div>"];
        }
    }];
}

#pragma mark - Live data fetchers

+ (NSDictionary *)fetchLiveConvosWithCursor:(NSString *)cursor {
    NSString *urlStr = [NSString stringWithFormat:@"%@/_admin/convos?limit=25", kChatServiceBase];
    if (cursor.length > 0) {
        urlStr = [urlStr stringByAppendingFormat:@"&cursor=%@",
            [cursor stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr] options:0 error:nil];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

+ (NSDictionary *)fetchLiveMessagesForConvoID:(NSString *)convoID cursor:(NSString *)cursor {
    NSString *urlStr = [NSString stringWithFormat:@"%@/_admin/messages?convoId=%@&limit=50", kChatServiceBase,
        [convoID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    if (cursor.length > 0) {
        urlStr = [urlStr stringByAppendingFormat:@"&cursor=%@",
            [cursor stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    }
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:urlStr] options:0 error:nil];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

#pragma mark - HTML renderers

+ (NSString *)chatOverviewHTML {
    return @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Privacy</span>"
        @"<span class=\"metric-value\">No message content displayed — metadata only</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Encryption</span>"
        @"<span class=\"metric-value\">E2EE + plaintext supported</span></div>"
        @"</div>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Conversations</h3>"
        @"<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"revealed, every 10s\"></div></section>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Messages</h3>"
        @"<div class=\"search-row\">"
        @"<form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/chat-messages\" hx-target=\"#chat-messages\">"
        @"<input type=\"text\" name=\"convoID\" placeholder=\"Conversation ID\" class=\"form-input flex-1\"/>"
        @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">View</button>"
        @"</form></div>"
        @"<div id=\"chat-messages\"></div></section>";
}

+ (NSString *)convosHTML:(NSDictionary *)data {
    NSArray *convos = data[@"convos"];
    if (![convos isKindOfClass:[NSArray class]] || convos.count == 0) {
        return @"<div class=\"alert alert-muted\">No conversations found.</div>";
    }

    NSMutableString *html = [NSMutableString string];
    [html appendString:@"<table class=\"data-table\"><thead><tr>"
        @"<th>ID</th><th>Members</th><th>Last Activity</th><th>Messages</th></tr></thead><tbody>"];

    for (NSDictionary *c in convos) {
        NSString *cid = GZAdminUIEscaped(c[@"id"] ?: @"—");
        NSArray *members = c[@"members"];
        NSString *memberCount = [@([members isKindOfClass:[NSArray class]] ? members.count : 0) stringValue];
        id lastMsg = c[@"lastMessage"];
        NSString *sentAt = @"—";
        if ([lastMsg isKindOfClass:[NSDictionary class]]) {
            sentAt = GZAdminUIEscaped(lastMsg[@"sentAt"] ?: @"—");
        }
        NSString *msgCount = GZAdminUIEscaped([c[@"messageCount"] description] ?: @"—");

        [html appendFormat:
            @"<tr><td><code>%@</code></td><td>%@</td><td>%@</td><td>%@</td></tr>",
            cid, memberCount, sentAt, msgCount];
    }

    [html appendString:@"</tbody></table>"];

    // Cursor for pagination
    NSString *cursor = data[@"cursor"];
    if ([cursor isKindOfClass:[NSString class]] && cursor.length > 0) {
        [html appendFormat:
            @"<div class=\"mt-sm\"><button class=\"btn btn-outline btn-sm\" "
            @"hx-get=\"/admin/partials/chat-convos?cursor=%@\" hx-target=\"#chat-convos\">"
            @"Load more</button></div>",
            GZAdminUIEscaped(cursor)];
    }

    return html;
}

+ (NSString *)messagesHTML:(NSDictionary *)data convoID:(NSString *)convoID {
    NSArray *msgs = data[@"messages"];
    if (![msgs isKindOfClass:[NSArray class]] || msgs.count == 0) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-muted\">No messages for <code>%@</code>.</div>",
            GZAdminUIEscaped(convoID)];
    }

    NSMutableString *html = [NSMutableString string];
    [html appendFormat:@"<p class=\"text-muted mb-sm\">Conversation <code>%@</code> — %lu messages (metadata only)</p>",
        GZAdminUIEscaped(convoID), (unsigned long)msgs.count];
    [html appendString:@"<table class=\"data-table\"><thead><tr>"
        @"<th>ID</th><th>Sender</th><th>Sent At</th><th>Type</th></tr></thead><tbody>"];

    for (NSDictionary *m in msgs) {
        NSString *mid = GZAdminUIEscaped(m[@"id"] ?: @"—");
        NSString *sender = GZAdminUIEscaped(m[@"sender"] ?: @"—");
        NSString *sentAt = GZAdminUIEscaped(m[@"sentAt"] ?: @"—");
        NSString *type = GZAdminUIEscaped(m[@"type"] ?: @"—");

        [html appendFormat:
            @"<tr><td><code>%@</code></td><td>%@</td><td>%@</td><td>%@</td></tr>",
            mid, sender, sentAt, type];
    }

    [html appendString:@"</tbody></table>"];

    // Cursor for pagination
    NSString *cursor = data[@"cursor"];
    if ([cursor isKindOfClass:[NSString class]] && cursor.length > 0) {
        [html appendFormat:
            @"<div class=\"mt-sm\"><button class=\"btn btn-outline btn-sm\" "
            @"hx-get=\"/admin/partials/chat-messages?convoID=%@&cursor=%@\" hx-target=\"#chat-messages\">"
            @"Load more</button></div>",
            GZAdminUIEscaped(convoID), GZAdminUIEscaped(cursor)];
    }

    return html;
}

@end
