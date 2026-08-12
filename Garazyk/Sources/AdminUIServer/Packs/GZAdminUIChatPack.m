// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIChatPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/GZHTML.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIChatPack

+ (NSString *)packIdentifier {
    return @"chat";
}

+ (NSString *)displayName {
    return @"Chat";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[@{@"tabIdentifier": @"chat", @"displayName": @"Chat"}];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerChatRoutes];
}

+ (NSString *)renderChatConvosPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"convos"]) {
        // Allowlisted metadata keys — no backend dictionary pass-through
        NSSet<NSString *> *allowlist = [NSSet setWithArray:@[
            @"id", @"mode", @"memberCount", @"locked", @"lastActivity",
            @"unreadCount", @"lastMessage"
        ]];
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *convo in result[@"convos"]) {
            NSMutableDictionary *mc = [NSMutableDictionary dictionary];
            for (NSString *key in allowlist) {
                id val = convo[key];
                if (val && ![val isKindOfClass:[NSNull class]]) {
                    mc[key] = val;
                }
            }
            NSString *mode = mc[@"mode"] ?: @"plaintext";
            mc[@"modeDisplay"] = [mode isEqualToString:@"e2ee"] ? @"<span title=\"End-to-end encrypted\">&#128274; E2EE</span>" : @"<span class=\"text-secondary\">plaintext</span>";
            NSNumber *memberCount = mc[@"memberCount"];
            mc[@"memberCountStr"] = memberCount ? [memberCount stringValue] : @"0";

            // Last message: render *escaped* preview text when provided.
            id lastMsgObj = mc[@"lastMessage"];
            NSString *lastMsg = @"<em class=\"text-secondary\">—</em>";
            if ([lastMsgObj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *lm = lastMsgObj;
                if ([lm[@"mode"] isEqualToString:@"e2ee"] || lm[@"ciphertext"] != nil) {
                    lastMsg = @"<em class=\"text-secondary\">&#128274; encrypted</em>";
                } else if (lm[@"sentAt"]) {
                    // Show timestamp but not body content
                    NSString *at = lm[@"sentAt"];
                    if (at.length > 19) at = [at substringToIndex:19];
                    lastMsg = [NSString stringWithFormat:@"<span class=\"text-secondary\">message at %@</span>", [GZHTML escapedString:at]];
                } else if ([lm[@"text"] isKindOfClass:[NSString class]]) {
                    NSString *text = lm[@"text"];
                    if (text.length > 0) {
                        lastMsg = [NSString stringWithFormat:@"<span class=\"text-secondary\">%@</span>",
                            [GZHTML escapedString:text]];
                    }
                }
            }
            mc[@"lastMsg"] = lastMsg;
            [mapped addObject:mc];
        }
        ctx[@"convos"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"chat-convos" context:ctx];
}

+ (NSString *)renderChatMessagesPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"messages"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *msg in result[@"messages"]) {
            NSMutableDictionary *mm = [msg mutableCopy];
            NSString *sender;
            id senderObj = msg[@"sender"];
            if ([senderObj isKindOfClass:[NSDictionary class]]) {
                sender = ((NSDictionary *)senderObj)[@"did"] ?: @"unknown";
            } else if ([senderObj isKindOfClass:[NSString class]]) {
                sender = senderObj;
            } else {
                sender = msg[@"senderDid"] ?: @"unknown";
            }
            if ([sender hasPrefix:@"did:plc:"] && sender.length > 20) {
                sender = [NSString stringWithFormat:@"did:plc:…%@", [sender substringFromIndex:sender.length - 8]];
            }
            mm[@"senderName"] = sender;
            NSString *mode = msg[@"mode"] ?: @"plaintext";
            BOOL isEncrypted = [mode isEqualToString:@"e2ee"] || msg[@"ciphertext"] != nil;
            if (isEncrypted) {
                mm[@"lockIcon"] = @"<span class=\"text-secondary\" title=\"End-to-end encrypted\">&#128274;</span> ";
                mm[@"text"] = @"<em class=\"text-secondary\">End-to-end encrypted message</em>";
            } else {
                mm[@"lockIcon"] = @"";
                // The template renders this field raw ({{{text}}}); msg[@"text"]
                // is user-controlled chat content, so it must be escaped here —
                // the other branch above is a literal, already-safe HTML fragment.
                mm[@"text"] = [GZHTML escapedString:msg[@"text"] ?: @""];
            }
            mm[@"time"] = msg[@"createdAt"] ?: msg[@"sentAt"] ?: @"";
            [mapped addObject:mm];
        }
        ctx[@"messages"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"chat-messages" context:ctx];
}

+ (NSString *)renderChatOverviewHTML {
    NSMutableString *html = [NSMutableString string];
    [html appendString:[GZHTML sectionTitle:@"Operator posture"]];
    [html appendString:[GZHTML detailCardWithFields:@[
        @{@"label": @"Privacy", @"value": @"Metadata only — no message bodies"},
        @{@"label": @"Encryption", @"value": @"E2EE and plaintext conversations supported"},
    ]]];

    [html appendString:@"<section class=\"mt-md\">"];
    [html appendString:[GZHTML sectionTitle:@"Conversations"]];
    [html appendString:@"<div id=\"chat-convos\" hx-get=\"/admin/partials/chat-convos\" hx-trigger=\"revealed\"></div></section>"];

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

@end
