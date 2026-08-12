// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Chat/AdminUI/ChatAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

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

    // Conversations (privacy-safe metadata only)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-convos" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        [res setBodyString:[self convosPlaceholderHTML]];
    }];

    // Messages lookup
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-messages" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *convoID = [req queryParamForKey:@"convoID"];
        if (convoID.length == 0) {
            [res setBodyString:@"<div class=\"alert alert-warning\">Enter a conversation ID to view messages.</div>"];
            return;
        }
        [res setBodyString:[self messagesPlaceholderHTML:convoID]];
    }];
}

#pragma mark - HTML renderers

+ (NSString *)chatOverviewHTML {
    return @"<div class=\"metric-row\">"
        @"<div class=\"metric\"><span class=\"metric-label\">Privacy</span>"
        @"<span class=\"metric-value\">No message content displayed by default</span></div>"
        @"<div class=\"metric\"><span class=\"metric-label\">Encryption</span>"
        @"<span class=\"metric-value\">E2EE + plaintext supported</span></div>"
        @"</div>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Conversations</h3>"
        @"<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"revealed\"></div></section>"

        @"<section class=\"mt-lg\"><h3 class=\"section-title\">Messages</h3>"
        @"<div class=\"search-row\">"
        @"<form class=\"d-flex gap-sm flex-1\" hx-get=\"/admin/partials/chat-messages\" hx-target=\"#chat-messages\">"
        @"<input type=\"text\" name=\"convoID\" placeholder=\"Conversation ID\" class=\"form-input flex-1\"/>"
        @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">View</button>"
        @"</form></div>"
        @"<div id=\"chat-messages\"></div></section>";
}

+ (NSString *)convosPlaceholderHTML {
    return @"<div class=\"alert alert-info\">"
        @"Conversation list will be available when the Chat service exposes an admin endpoint. "
        @"Metadata only — message bodies are never rendered by default."
        @"</div>";
}

+ (NSString *)messagesPlaceholderHTML:(NSString *)convoID {
    return [NSString stringWithFormat:
        @"<div class=\"alert alert-info\">"
        @"Message view for conversation <code>%@</code> will be available when the Chat service "
        @"exposes an admin endpoint. No message content is displayed by default."
        @"</div>",
        GZAdminUIEscaped(convoID)];
}

@end
