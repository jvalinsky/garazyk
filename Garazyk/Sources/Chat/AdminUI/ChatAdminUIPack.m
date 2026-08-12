// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Chat/AdminUI/ChatAdminUIPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
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
    return [GZHTML alertWithType:@"warning" message:@"Chat dashboard unavailable — embedded listener required."];
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
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:@"Conversation data unavailable — Chat service may not be running."]];
        }
    }];

    // Messages lookup (live fetch from Chat service admin endpoint)
    [host.httpServer addRoute:@"GET" path:@"/admin/partials/chat-messages" handler:^(ATProtoHttpRequest *req, ATProtoHttpResponse *res) {
        AUTH_GUARD(weakHost, req, res);
        res.contentType = @"text/html; charset=utf-8";
        NSString *convoID = [req queryParamForKey:@"convoID"];
        if (convoID.length == 0) {
            [res setBodyString:[GZHTML alertWithType:@"warning" message:@"Enter a conversation ID to view messages."]];
            return;
        }
        NSDictionary *msgs = [self fetchLiveMessagesForConvoID:convoID cursor:[req queryParamForKey:@"cursor"]];
        if (msgs) {
            [res setBodyString:[self messagesHTML:msgs convoID:convoID]];
        } else {
            [res setBodyString:[GZHTML alertWithType:@"warning"
                                             message:@"Message data unavailable — Chat service may not be running."]];
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
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Operator posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Privacy", @"value": @"Metadata only — no message bodies"},
        @{@"label": @"Encryption", @"value": @"E2EE and plaintext conversations supported"},
        @{@"label": @"Safe actions", @"value": @"Browse conversation metadata; lock/mute stay server-side"},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Conversations"]];
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

+ (NSString *)convosHTML:(NSDictionary *)data {
    NSArray *convos = data[@"convos"];
    if (![convos isKindOfClass:[NSArray class]] || convos.count == 0) {
        return [GZHTML alertWithType:@"info" message:@"No conversations found."];
    }

    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:convos.count];
    for (NSDictionary *c in convos) {
        NSArray *members = c[@"members"];
        NSString *memberCount = [@([members isKindOfClass:[NSArray class]] ? members.count : 0) stringValue];
        id lastMsg = c[@"lastMessage"];
        NSString *sentAt = @"—";
        if ([lastMsg isKindOfClass:[NSDictionary class]]) {
            sentAt = lastMsg[@"sentAt"] ?: @"—";
        }
        NSString *msgCount = [c[@"messageCount"] description] ?: @"—";

        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:c[@"id"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:memberCount className:@"text-right text-mono"],
            [GZHTML tableCellWithText:sentAt className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:msgCount className:@"text-right text-mono"],
        ]]];
    }

    NSMutableString *html = [NSMutableString stringWithString:
        [GZHTML tableWithHeaders:@[@"ID", @"Members", @"Last activity", @"Messages"]
                        htmlRows:rows
                   emptyMessage:@"No conversations found."]];

    NSString *cursor = data[@"cursor"];
    if ([cursor isKindOfClass:[NSString class]] && cursor.length > 0) {
        [html appendString:[GZHTML paginationButtonWithHref:
            [NSString stringWithFormat:@"/admin/partials/chat-convos?cursor=%@", cursor]
                                                     target:@"#chat-convos"
                                                      label:@"Load more"]];
    }

    return html;
}

+ (NSString *)messagesHTML:(NSDictionary *)data convoID:(NSString *)convoID {
    NSArray *msgs = data[@"messages"];
    if (![msgs isKindOfClass:[NSArray class]] || msgs.count == 0) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-info\">No messages for %@.</div>",
            [GZHTML monoValue:convoID]];
    }

    NSMutableString *html = [NSMutableString string];
    [html appendFormat:@"<p class=\"text-secondary text-sm mb-md\">Conversation %@ — %lu metadata rows</p>",
        [GZHTML monoValue:convoID], (unsigned long)msgs.count];

    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:msgs.count];
    for (NSDictionary *m in msgs) {
        [rows addObject:[GZHTML tableRowWithHtmlCells:@[
            [GZHTML tableCellWithText:m[@"id"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:m[@"sender"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:m[@"sentAt"] ?: @"—" className:@"text-mono text-sm"],
            [GZHTML tableCellWithText:m[@"type"] ?: @"—" className:nil],
        ]]];
    }
    [html appendString:[GZHTML tableWithHeaders:@[@"ID", @"Sender", @"Sent at", @"Type"]
                                       htmlRows:rows
                                  emptyMessage:@"No messages."]];

    NSString *cursor = data[@"cursor"];
    if ([cursor isKindOfClass:[NSString class]] && cursor.length > 0) {
        [html appendString:[GZHTML paginationButtonWithHref:
            [NSString stringWithFormat:@"/admin/partials/chat-messages?convoID=%@&cursor=%@", convoID, cursor]
                                                     target:@"#chat-messages"
                                                      label:@"Load more"]];
    }

    return html;
}

@end
