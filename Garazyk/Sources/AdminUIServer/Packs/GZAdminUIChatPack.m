// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIChatPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
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
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *convo in result[@"convos"]) {
            NSMutableDictionary *mc = [convo mutableCopy];
            NSString *mode = convo[@"mode"] ?: @"plaintext";
            mc[@"modeDisplay"] = [mode isEqualToString:@"e2ee"] ? @"<span title=\"End-to-end encrypted\">&#128274; E2EE</span>" : @"<span class=\"text-secondary\">plaintext</span>";
            if (convo[@"memberCount"]) {
                mc[@"memberCountStr"] = [convo[@"memberCount"] stringValue];
            } else {
                NSArray *members = convo[@"members"];
                mc[@"memberCountStr"] = members ? [NSString stringWithFormat:@"%lu", (unsigned long)members.count] : @"0";
            }
            id lastMsgObj = convo[@"lastMessage"];
            NSString *lastMsg = @"(none)";
            if ([lastMsgObj isKindOfClass:[NSDictionary class]]) {
                if ([((NSDictionary *)lastMsgObj)[@"mode"] isEqualToString:@"e2ee"] || ((NSDictionary *)lastMsgObj)[@"ciphertext"] != nil) {
                    lastMsg = @"<em class=\"text-secondary\">&#128274; encrypted</em>";
                } else {
                    lastMsg = ((NSDictionary *)lastMsgObj)[@"text"] ?: @"(none)";
                    if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
                    lastMsg = GZAdminUIEscaped(lastMsg);
                }
            } else if ([lastMsgObj isKindOfClass:[NSString class]]) {
                lastMsg = lastMsgObj;
                if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
                lastMsg = GZAdminUIEscaped(lastMsg);
            }
            // lastMsg is either one of the two literal HTML fragments above
            // (encrypted placeholder) or GZAdminUIEscaped user message text — the
            // template renders this field raw ({{{lastMsg}}}), so anything
            // reaching here must already be safe HTML.
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
                mm[@"text"] = GZAdminUIEscaped(msg[@"text"] ?: @"");
            }
            mm[@"time"] = msg[@"createdAt"] ?: msg[@"sentAt"] ?: @"";
            [mapped addObject:mm];
        }
        ctx[@"messages"] = mapped;
    }
    return [GZAdminUITemplateEngine renderTemplate:@"chat-messages" context:ctx];
}

@end
