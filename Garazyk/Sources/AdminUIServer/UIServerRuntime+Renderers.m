// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"

#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Auth/CryptoUtils.h"
#import "Debug/GZLogger.h"
#import "AdminUIServer/UIServerRuntime+Private.h"

@implementation UIServerRuntime (Renderers)

#pragma mark - Ozone Render Methods

- (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *statuses = [result[@"subjectStatuses"] isKindOfClass:[NSArray class]] ? result[@"subjectStatuses"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>DID</th><th>Status</th><th>Updated</th></tr></thead><tbody>"];
    for (NSDictionary *s in statuses) {
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td></tr>",
            UIEscaped(s[@"did"] ?: @""), UIEscaped(s[@"reviewState"] ?: @""), UIEscaped(s[@"updatedAt"] ?: @"")];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-statuses?cursor=%@\" hx-target=\"#ozone-statuses\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderOzoneEventsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *events = [result[@"events"] isKindOfClass:[NSArray class]] ? result[@"events"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Type</th><th>Subject</th><th>Created By</th><th>At</th></tr></thead><tbody>"];
    for (NSDictionary *e in events) {
        NSDictionary *subject = e[@"subject"];
        NSString *subjectStr = subject[@"did"] ?: subject[@"uri"] ?: @"";
        [html appendFormat:@"<tr><td>%@</td><td class=\"text-mono text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td><td class=\"text-sm\">%@</td></tr>",
            UIEscaped(e[@"event"] ?: @""), UIEscaped(subjectStr), UIEscaped(e[@"createdBy"] ?: @""), UIEscaped(e[@"createdAt"] ?: @"")];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-events?cursor=%@\" hx-target=\"#ozone-events\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">DID</span><span class=\"text-mono text-sm\">%@</span></div>", UIEscaped(result[@"did"] ?: @"")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Review State</span><span>%@</span></div>", UIEscaped(result[@"reviewState"] ?: @"")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Updated</span><span>%@</span></div>", UIEscaped(result[@"updatedAt"] ?: @"")];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderOzoneTeamPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *members = [result[@"members"] isKindOfClass:[NSArray class]] ? result[@"members"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form mb-lg\" data-ui-form=\"add-ozone-team-member\"><div class=\"form-group\"><label for=\"add-member-did\">DID:</label><input type=\"text\" id=\"add-member-did\" class=\"form-input\" placeholder=\"Enter DID\"></div><div class=\"form-group\"><label for=\"add-member-role\">Role:</label><select id=\"add-member-role\" class=\"form-input\"><option value=\"moderator\">Moderator</option><option value=\"admin\">Admin</option></select></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Add Member</button></form><table class=\"table\"><thead><tr><th>DID</th><th>Role</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *m in members) {
        NSString *did = m[@"did"] ?: @"";
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"remove-team-member\" data-ui-did=\"%@\">Remove</button></td></tr>",
            UIEscaped(did), UIEscaped(m[@"role"] ?: @""), UIEscaped(did)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneSetsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *sets = [result[@"sets"] isKindOfClass:[NSArray class]] ? result[@"sets"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form mb-lg\" data-ui-form=\"upsert-ozone-set\"><div class=\"form-group\"><label for=\"create-set-name\">Set Name:</label><input type=\"text\" id=\"create-set-name\" class=\"form-input\" placeholder=\"Enter set name\"></div><div class=\"form-group\"><label for=\"create-set-desc\">Description:</label><input type=\"text\" id=\"create-set-desc\" class=\"form-input\" placeholder=\"Enter description\"></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Create Set</button></form><table class=\"table\"><thead><tr><th>Name</th><th>Description</th><th>Size</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *s in sets) {
        NSString *name = s[@"name"] ?: @"";
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td>%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"delete-ozone-set\" data-ui-name=\"%@\">Delete</button></td></tr>",
            UIEscaped(name), UIEscaped(s[@"description"] ?: @""), UIEscaped(s[@"size"] ?: @""), UIEscaped(name)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *templates = [result[@"templates"] isKindOfClass:[NSArray class]] ? result[@"templates"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form mb-lg\" data-ui-form=\"create-ozone-template\"><div class=\"form-group\"><label for=\"create-template-name\">Template Name:</label><input type=\"text\" id=\"create-template-name\" class=\"form-input\" placeholder=\"Enter template name\"></div><div class=\"form-group\"><label for=\"create-template-subject\">Subject:</label><input type=\"text\" id=\"create-template-subject\" class=\"form-input\" placeholder=\"Enter subject\"></div><div class=\"form-group\"><label for=\"create-template-content\">Content (Markdown):</label><textarea id=\"create-template-content\" class=\"form-input\" placeholder=\"Enter template content\"></textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Create Template</button></form><table class=\"table\"><thead><tr><th>Name</th><th>Subject</th><th>Content</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *t in templates) {
        NSString *name = t[@"name"] ?: @"";
        NSString *content = t[@"contentMarkdown"] ?: @"";
        if (content.length > 80) content = [[content substringToIndex:80] stringByAppendingString:@"..."];
        [html appendFormat:@"<tr><td>%@</td><td>%@</td><td class=\"text-sm\">%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"delete-ozone-template\" data-ui-name=\"%@\">Delete</button></td></tr>",
            UIEscaped(name), UIEscaped(t[@"subject"] ?: @""), UIEscaped(content), UIEscaped(name)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneConfigPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&jsonError];
    NSString *jsonStr = jsonError ? @"" : [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"ozone-config-result\" aria-live=\"polite\"></div><form class=\"form mb-lg\" data-ui-form=\"update-ozone-config\"><div class=\"form-group\"><label for=\"config-json\">Config (JSON):</label><textarea id=\"config-json\" class=\"form-input\" placeholder=\"Enter config as JSON\">"];
    [html appendString:UIEscaped(jsonStr)];
    [html appendString:@"</textarea></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Update Config</button></form><div class=\"detail-card\">"];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">%@</span><span class=\"text-sm\">%@</span></div>",
            UIEscaped(key), UIEscaped([value description])];
    }];
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Security Render Methods

- (NSString *)renderSessionsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *sessions = [result[@"sessions"] isKindOfClass:[NSArray class]] ? result[@"sessions"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>ID</th><th>Device</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *s in sessions) {
        NSString *sessionID = s[@"id"] ?: @"";
        NSString *did = s[@"did"] ?: @"";
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"revoke-session\" data-ui-did=\"%@\" data-ui-session-id=\"%@\">Revoke</button></td></tr>",
            UIEscaped(sessionID), UIEscaped(s[@"deviceInfo"] ?: @""), UIEscaped(s[@"createdAt"] ?: @""), UIEscaped(did), UIEscaped(sessionID)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderAppPasswordsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *passwords = [result[@"passwords"] isKindOfClass:[NSArray class]] ? result[@"passwords"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"app-passwords-result\" aria-live=\"polite\"></div><form class=\"form mb-lg\" data-ui-form=\"create-app-password\"><div class=\"form-group\"><label for=\"create-pwd-did\">DID:</label><input type=\"text\" id=\"create-pwd-did\" class=\"form-input\" placeholder=\"Enter DID\"></div><div class=\"form-group\"><label for=\"create-pwd-name\">Password Name:</label><input type=\"text\" id=\"create-pwd-name\" class=\"form-input\" placeholder=\"Enter password name\"></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Create</button></form><table class=\"table\"><thead><tr><th>Name</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *p in passwords) {
        NSString *name = p[@"name"] ?: @"";
        NSString *did = p[@"did"] ?: @"";
        [html appendFormat:@"<tr><td>%@</td><td class=\"text-sm\">%@</td>"
            "<td><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"delete-app-password\" data-ui-did=\"%@\" data-ui-name=\"%@\">Delete</button></td></tr>",
            UIEscaped(name), UIEscaped(p[@"createdAt"] ?: @""), UIEscaped(did), UIEscaped(name)];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

#pragma mark - Chat Render Methods

- (NSString *)renderChatConvosPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *convos = [result[@"convos"] isKindOfClass:[NSArray class]] ? result[@"convos"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Conversation ID</th><th>Mode</th><th>Members</th><th>Last Message</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *convo in convos) {
        NSString *convoID = UISafe(convo[@"id"], @"");

        // Mode column: show lock icon for E2EE
        NSString *mode = UISafe(convo[@"mode"], @"plaintext");
        NSString *modeDisplay = [mode isEqualToString:@"e2ee"]
            ? @"<span title=\"End-to-end encrypted\">&#128274; E2EE</span>"
            : @"<span class=\"text-secondary\">plaintext</span>";

        // Count members from the members array if memberCount is absent
        NSString *memberCount;
        if (convo[@"memberCount"] && [convo[@"memberCount"] respondsToSelector:@selector(stringValue)]) {
            memberCount = [convo[@"memberCount"] stringValue];
        } else {
            NSArray *members = [convo[@"members"] isKindOfClass:[NSArray class]] ? convo[@"members"] : nil;
            memberCount = members ? [NSString stringWithFormat:@"%lu", (unsigned long)members.count] : @"0";
        }
        id lastMsgObj = convo[@"lastMessage"];
        NSString *lastMsg = @"(none)";
        if ([lastMsgObj isKindOfClass:[NSDictionary class]]) {
            // Check if last message is encrypted
            if ([((NSDictionary *)lastMsgObj)[@"mode"] isEqualToString:@"e2ee"] ||
                ((NSDictionary *)lastMsgObj)[@"ciphertext"] != nil) {
                lastMsg = @"<em class=\"text-secondary\">&#128274; encrypted</em>";
            } else {
                lastMsg = UISafe(((NSDictionary *)lastMsgObj)[@"text"], @"(none)");
                if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
            }
        } else if ([lastMsgObj isKindOfClass:[NSString class]]) {
            lastMsg = lastMsgObj;
            if (lastMsg.length > 50) lastMsg = [[lastMsg substringToIndex:50] stringByAppendingString:@"..."];
        }
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td>%@</td><td class=\"text-sm\">%@</td><td><button class=\"btn btn-secondary btn-sm\" data-ui-action=\"lock-chat-convo\" data-ui-convo-id=\"%@\">Lock</button></td></tr>",
            UIEscaped(convoID), modeDisplay, UIEscaped(memberCount), lastMsg, UIEscaped(convoID)];
    }
    if (convos.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No conversations found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/chat-convos?cursor=%@\" hx-target=\"#chat-convos\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderChatMessagesPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *messages = [result[@"messages"] isKindOfClass:[NSArray class]] ? result[@"messages"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"chat-messages\">"];
    for (NSDictionary *msg in messages) {
        // sender may be a dict with "did" key, or a bare string "senderDid"
        NSString *sender;
        id senderObj = msg[@"sender"];
        if ([senderObj isKindOfClass:[NSDictionary class]]) {
            sender = UISafe(((NSDictionary *)senderObj)[@"did"], @"unknown");
        } else if ([senderObj isKindOfClass:[NSString class]]) {
            sender = senderObj;
        } else {
            sender = UISafe(msg[@"senderDid"], @"unknown");
        }
        // Shorten DID display: show last segment after colon
        if ([sender hasPrefix:@"did:plc:"] && sender.length > 20) {
            sender = [NSString stringWithFormat:@"did:plc:…%@", [sender substringFromIndex:sender.length - 8]];
        }

        // Check if this is an E2EE message (mode=e2ee or ciphertext present)
        NSString *mode = msg[@"mode"] ?: @"plaintext";
        BOOL isEncrypted = [mode isEqualToString:@"e2ee"] || msg[@"ciphertext"] != nil;

        NSString *text;
        NSString *lockIcon = @"";
        if (isEncrypted) {
            // E2EE message: show lock icon and placeholder
            lockIcon = @"<span class=\"text-secondary\" title=\"End-to-end encrypted\">&#128274;</span> ";
            text = @"<em class=\"text-secondary\">End-to-end encrypted message</em>";
        } else {
            text = UIEscaped(UISafe(msg[@"text"], @""));
        }

        NSString *createdAt = UISafe(msg[@"createdAt"] ?: msg[@"sentAt"], @"");
        [html appendFormat:@"<div class=\"message\"><div class=\"message-header\"><span class=\"message-sender\">%@</span><span class=\"message-time text-xs text-secondary\">%@</span></div><div class=\"message-body\">%@%@</div></div>",
            UIEscaped(sender), UIEscaped(createdAt), lockIcon, text];
    }
    if (messages.count == 0) {
        [html appendString:@"<div class=\"text-center text-secondary p-lg\">No messages found.</div>"];
    }
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Render Methods

- (NSString *)renderConnectionsPartial {
    NSMutableString *html = [NSMutableString stringWithString:@"<form class=\"form\" data-ui-form=\"save-connections\">"];
    
    NSDictionary *fields = @{
        @"pdsURL": UISafe([self.configuration.pdsBaseURL absoluteString], @""),
        @"pdsToken": UISafe(self.configuration.pdsAdminToken, @""),
        @"appViewURL": UISafe([self.configuration.appViewBaseURL absoluteString], @""),
        @"appViewToken": UISafe(self.configuration.appViewAdminToken, @""),
        @"relayURL": UISafe([self.configuration.relayBaseURL absoluteString], @""),
        @"relayToken": UISafe(self.configuration.relayAdminToken, @""),
        @"plcURL": UISafe([self.configuration.plcBaseURL absoluteString], @""),
        @"plcToken": UISafe(self.configuration.plcAdminToken, @""),
        @"chatURL": UISafe([self.configuration.chatBaseURL absoluteString], @""),
        @"chatToken": UISafe(self.configuration.chatAdminToken, @""),
        @"videoURL": UISafe([self.configuration.videoBaseURL absoluteString], @""),
        @"videoToken": UISafe(self.configuration.videoAdminToken, @"")
    };
    
    [html appendString:@"<div class=\"grid-2\">"];
    
    NSArray<NSDictionary *> *order = @[
        @{@"id": @"pds", @"key": @"pds", @"label": @"PDS"},
        @{@"id": @"appview", @"key": @"appView", @"label": @"APPVIEW"},
        @{@"id": @"relay", @"key": @"relay", @"label": @"RELAY"},
        @{@"id": @"plc", @"key": @"plc", @"label": @"PLC"},
        @{@"id": @"chat", @"key": @"chat", @"label": @"CHAT"},
        @{@"id": @"video", @"key": @"video", @"label": @"VIDEO"}
    ];
    for (NSDictionary *entry in order) {
        NSString *inputID = entry[@"id"];
        NSString *key = entry[@"key"];
        NSString *urlKey = [key stringByAppendingString:@"URL"];
        NSString *tokenKey = [key stringByAppendingString:@"Token"];
        
        [html appendFormat:@"<div class=\"card\">"];
        [html appendFormat:@"<div class=\"card-title mb-md\">%@ Service</div>", entry[@"label"]];
        
        [html appendFormat:@"<div class=\"form-group\">"];
        [html appendFormat:@"<label class=\"form-label\" for=\"conn-%@-url\">Base URL</label>", inputID];
        [html appendFormat:@"<input id=\"conn-%@-url\" type=\"text\" name=\"%@\" value=\"%@\" class=\"form-input\"/>", inputID, urlKey, UIEscaped(fields[urlKey])];
        [html appendString:@"</div>"];

        [html appendFormat:@"<div class=\"form-group\">"];
        [html appendFormat:@"<label class=\"form-label\" for=\"conn-%@-token\">Admin Token</label>", inputID];
        [html appendFormat:@"<input id=\"conn-%@-token\" type=\"password\" name=\"%@\" value=\"\" data-original-token=\"%@\" class=\"form-input\" placeholder=\"Current token set, type to change\"/>", inputID, tokenKey, UIEscaped(fields[tokenKey])];
        [html appendString:@"</div>"];

        [html appendFormat:@"<div class=\"d-flex align-center gap-sm\"><button type=\"button\" class=\"btn btn-secondary btn-sm\" data-ui-action=\"test-connection\" data-ui-service=\"%@\">Test</button><span id=\"conn-%@-test-result\" class=\"text-sm text-secondary\" aria-live=\"polite\"></span></div>", inputID, inputID];
        
        [html appendString:@"</div>"];
    }
    
    [html appendString:@"</div>"];
    [html appendString:@"<div id=\"connections-save-result\" class=\"mt-md\" aria-live=\"polite\"></div>"];
    [html appendString:@"<div class=\"mt-lg d-flex justify-end\">"];
    [html appendString:@"<button type=\"submit\" class=\"btn btn-primary\">Save Cluster Configuration</button>"];
    [html appendString:@"</div></form>"];
    
    return html;
}

- (NSString *)renderOverviewPartial:(NSDictionary *)result {
    NSArray *services = [result[@"services"] isKindOfClass:[NSArray class]] ? result[@"services"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"cluster-grid\">"];
    
    for (NSDictionary *svc in services) {
        NSString *name = UISafe(svc[@"name"], @"unknown");
        NSString *status = UISafe(svc[@"status"], @"unknown");
        NSString *url = UISafe(svc[@"url"], @"-");
        
        NSString *statusClass = @"status-unknown";
        if ([status isEqualToString:@"online"]) statusClass = @"status-online";
        else if ([status isEqualToString:@"offline"]) statusClass = @"status-offline";
        else if ([status isEqualToString:@"error"]) statusClass = @"status-error";
        
        [html appendFormat:@"<div class=\"service-card %@\">", statusClass];
        [html appendFormat:@"<div class=\"service-header\">"];
        [html appendFormat:@"<span class=\"service-name\">%@</span>", [name uppercaseString]];
        [html appendFormat:@"<span class=\"status-dot\"></span>"];
        [html appendString:@"</div>"];
        
        [html appendFormat:@"<div class=\"service-url\">%@</div>", UIEscaped(url)];
        
        if (svc[@"version"]) {
            [html appendFormat:@"<div class=\"service-meta\">Version: %@</div>", UIEscaped(svc[@"version"])];
        }
        
        if (svc[@"latency_ms"]) {
            [html appendFormat:@"<div class=\"service-meta\">Latency: %@ms</div>", svc[@"latency_ms"]];
        }
        
        if (svc[@"error"]) {
            [html appendFormat:@"<div class=\"text-xs text-destructive mt-xs\">%@</div>", UIEscaped(svc[@"error"])];
        }
        
        [html appendString:@"</div>"];
    }
    
    [html appendString:@"</div>"];
    
    if (result[@"generatedAt"]) {
        [html appendFormat:@"<div class=\"text-xs text-secondary mt-lg\">Last updated: %@</div>", UIEscaped(result[@"generatedAt"])];
    }
    
    return html;
}

- (NSString *)renderMSTAccountsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *accounts = [result[@"accounts"] isKindOfClass:[NSArray class]] ? result[@"accounts"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>DID</th><th>Handle</th></tr></thead><tbody>"];
    for (NSDictionary *a in accounts) {
        [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td></tr>",
            UIEscaped(a[@"did"] ?: @""), UIEscaped(a[@"handle"] ?: @"")];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderMSTTreePartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray *nodes = [result[@"nodes"] isKindOfClass:[NSArray class]] ? result[@"nodes"] : @[];
    NSString *rootCID = result[@"rootCID"] ?: @"";
    NSNumber *nodeCount = result[@"nodeCount"] ?: @(0);
    NSNumber *entryCount = result[@"entryCount"] ?: @(0);
    NSNumber *maxDepth = result[@"maxDepth"] ?: @(0);

    if (nodes.count == 0 && rootCID.length == 0) {
        return @"<div class=\"alert alert-info\">No tree data available.</div>";
    }

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Root CID</span><span class=\"text-mono text-sm\">%@</span></div>", UIEscaped(rootCID)];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Nodes</span><span>%@</span></div>", nodeCount];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Entries</span><span>%@</span></div>", entryCount];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Max Depth</span><span>%@</span></div>", maxDepth];
    [html appendString:@"</div>"];

    // Render node table
    if (nodes.count > 0) {
        [html appendString:@"<table class=\"table mt-sm\"><thead><tr><th>CID</th><th>Level</th><th>Kind</th><th>Entries</th></tr></thead><tbody>"];
        for (NSDictionary *node in nodes) {
            NSString *cid = node[@"cid"] ?: @"";
            NSNumber *level = node[@"level"] ?: @(0);
            NSString *kind = node[@"kind"] ?: @"";
            NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
            [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td>%@</td><td>%@</td><td>%lu</td></tr>",
                UIEscaped(cid), level, UIEscaped(kind), (unsigned long)entries.count];
        }
        [html appendString:@"</tbody></table>"];

        // Render entries for each node
        for (NSDictionary *node in nodes) {
            NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
            if (entries.count > 0) {
                NSString *cid = node[@"cid"] ?: @"";
                [html appendFormat:@"<h3 class=\"mt-md\">Node %@</h3>", UIEscaped([cid substringToIndex:MIN(16, cid.length)])];
                [html appendString:@"<table class=\"table\"><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>"];
                for (NSDictionary *e in entries) {
                    [html appendFormat:@"<tr><td class=\"text-mono text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td></tr>",
                        UIEscaped(e[@"fullKey"] ?: @""), UIEscaped(e[@"value"] ?: @"")];
                }
                [html appendString:@"</tbody></table>"];
            }
        }
    }
    return html;
}

- (NSString *)renderMSTStatsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">%@</span><span>%@</span></div>",
            UIEscaped(key), UIEscaped([value description])];
    }];
    [html appendString:@"</div>"];
    return html;
}

#pragma mark - Phase 1 Render Methods

- (NSString *)renderRelayHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *status = result[@"status"] ?: @"unknown";
    NSString *statusBadge = [status isEqualToString:@"ok"] ? @"badge badge-success" :
                            [status isEqualToString:@"error"] ? @"badge badge-destructive" : @"badge badge-secondary";
    NSString *checkedAt = UISafe(result[@"checkedAt"], UISafe(result[@"lastChecked"], @""));
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Status</span><span class=\"%@\">%@</span></div>", statusBadge, UIEscaped(status)];
    if (checkedAt.length > 0) {
        [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Last Checked</span><span>%@</span></div>", UIEscaped(checkedAt)];
    }
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Subject</th><th>Reason</th><th>Reported By</th><th>Resolved At</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *reports = [result[@"reports"] isKindOfClass:[NSArray class]] ? result[@"reports"] : @[];
    for (NSDictionary *report in reports) {
        NSString *subject = UIEscaped(report[@"subject"] ?: @"");
        NSString *reason = UIEscaped(report[@"reason"] ?: @"");
        NSString *reportedBy = UIEscaped(report[@"reportedBy"] ?: @"");
        NSString *resolvedAt = UIEscaped(report[@"resolvedAt"] ?: @"pending");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td><td>%@</td></tr>", subject, reason, reportedBy, resolvedAt];
    }
    if (reports.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No moderation reports found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-reports?cursor=%@\" hx-target=\"#ozone-reports\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

#pragma mark - Phase 2 Render Methods

- (NSString *)renderPLCHealthPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *status = result[@"status"] ?: @"unknown";
    NSString *statusBadge = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Status</span><span class=\"%@\">%@</span></div>", statusBadge, UIEscaped(status)];
    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderPLCMetricsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *metricsText = result[@"text"] ?: @"";
    return [NSString stringWithFormat:@"<pre class=\"code-block\">%@</pre>", UIEscaped(metricsText)];
}

- (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSString *> *dids = [result[@"dids"] isKindOfClass:[NSArray class]] ? result[@"dids"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>DID</th></tr></thead><tbody>"];
    for (NSString *did in dids) {
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td></tr>", UIEscaped(did)];
    }
    if (dids.count == 0) {
        [html appendString:@"<tr><td class=\"text-center text-secondary p-lg\">No DIDs found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    if (cursor && cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/plc-list?cursor=%@\" hx-target=\"#plc-list\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

#pragma mark - Phase 3 Render Methods

- (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"form\" data-ui-form=\"schedule-ozone-action\"><div class=\"form-group\"><label for=\"schedule-subject-did\">Subject DID(s):</label><input type=\"text\" id=\"schedule-subject-did\" class=\"form-input\" placeholder=\"did:plc:...\"/></div><div class=\"form-group\"><label for=\"schedule-action-type\">Action Type:</label><select id=\"schedule-action-type\" class=\"form-input\"><option value=\"takedown\">Takedown</option></select></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Schedule Action</button></form></div>"];

    [html appendString:@"<table class=\"table\"><thead><tr><th>Subject</th><th>Action</th><th>Status</th><th>Execute At</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *actions = [result[@"actions"] isKindOfClass:[NSArray class]] ? result[@"actions"] : @[];
    for (NSDictionary *action in actions) {
        NSString *subject = UIEscaped(action[@"subject"] ?: @"");
        NSString *actionType = UIEscaped(action[@"action"] ?: @"");
        NSString *status = UIEscaped(action[@"status"] ?: @"pending");
        NSString *executeAt = UIEscaped(action[@"executeAt"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td><span class=\"badge\">%@</span></td><td>%@</td><td>", subject, actionType, status, executeAt];
        [html appendFormat:@"<button class=\"btn btn-sm btn-destructive\" data-ui-action=\"cancel-scheduled-action\" data-ui-subject=\"%@\">Cancel</button>", subject];
        [html appendString:@"</td></tr>"];
    }
    if (actions.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No scheduled actions.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor && cursor.length > 0) {
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/ozone-scheduled?cursor=%@\" hx-target=\"#ozone-scheduled\">Load More</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"form\" data-ui-form=\"grant-ozone-verification\"><div class=\"form-group\"><label for=\"grant-verification-did\">DID:</label><input type=\"text\" id=\"grant-verification-did\" class=\"form-input\" placeholder=\"did:plc:...\"/></div><div class=\"form-group\"><label for=\"grant-verification-name\">Display Name:</label><input type=\"text\" id=\"grant-verification-name\" class=\"form-input\" placeholder=\"Account display name\"/></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Grant Verification</button></form></div>"];

    [html appendString:@"<table class=\"table\"><thead><tr><th>DID</th><th>Display Name</th><th>Issuer</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *verifications = [result[@"verifications"] isKindOfClass:[NSArray class]] ? result[@"verifications"] : @[];
    for (NSDictionary *verification in verifications) {
        NSString *did = UIEscaped(verification[@"did"] ?: @"");
        NSString *displayName = UIEscaped(verification[@"displayName"] ?: @"");
        NSString *issuer = UIEscaped(verification[@"issuer"] ?: @"");
        NSString *createdAt = UIEscaped(verification[@"createdAt"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-xs\">%@</td><td class=\"text-xs\">%@</td><td>", did, displayName, issuer, createdAt];
        [html appendFormat:@"<button class=\"btn btn-sm btn-destructive\" data-ui-action=\"revoke-ozone-verification\" data-ui-did=\"%@\">Revoke</button>", did];
        [html appendString:@"</td></tr>"];
    }
    if (verifications.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No verified accounts.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"form\" data-ui-form=\"add-safelink-rule\"><div class=\"form-group\"><label for=\"add-safelink-url\">URL:</label><input type=\"text\" id=\"add-safelink-url\" class=\"form-input\" placeholder=\"https://example.com\"/></div><div class=\"form-group\"><label for=\"add-safelink-pattern\">Pattern Type:</label><select id=\"add-safelink-pattern\" class=\"form-input\"><option value=\"domain\">Domain</option><option value=\"url\">URL</option></select></div><div class=\"form-group\"><label for=\"add-safelink-action\">Action:</label><select id=\"add-safelink-action\" class=\"form-input\"><option value=\"block\">Block</option><option value=\"warn\">Warn</option><option value=\"whitelist\">Whitelist</option></select></div><div class=\"form-group\"><label for=\"add-safelink-reason\">Reason:</label><select id=\"add-safelink-reason\" class=\"form-input\"><option value=\"csam\">CSAM</option><option value=\"spam\">Spam</option><option value=\"phishing\">Phishing</option><option value=\"none\">None</option></select></div><div class=\"form-group\"><label for=\"add-safelink-comment\">Comment (optional):</label><input type=\"text\" id=\"add-safelink-comment\" class=\"form-input\"/></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Add Rule</button></form></div>"];

    [html appendString:@"<table class=\"table\"><thead><tr><th>URL</th><th>Pattern</th><th>Action</th><th>Reason</th><th>Actions</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *rules = [result[@"rules"] isKindOfClass:[NSArray class]] ? result[@"rules"] : @[];
    for (NSDictionary *rule in rules) {
        NSString *url = UIEscaped(rule[@"url"] ?: @"");
        NSString *pattern = UIEscaped(rule[@"pattern"] ?: @"domain");
        NSString *action = UIEscaped(rule[@"action"] ?: @"block");
        NSString *reason = UIEscaped(rule[@"reason"] ?: @"none");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td><td>%@</td><td>", url, pattern, action, reason];
        [html appendFormat:@"<button class=\"btn btn-sm btn-destructive\" data-ui-action=\"remove-safelink-rule\" data-ui-url=\"%@\" data-ui-pattern=\"%@\">Remove</button>", url, pattern];
        [html appendString:@"</td></tr>"];
    }
    if (rules.count == 0) {
        [html appendString:@"<tr><td colspan=\"5\" class=\"text-center text-secondary p-lg\">No safelink rules.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

#pragma mark - Phase 6 Render Methods

- (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Key</th><th>Value</th></tr></thead><tbody>"];
    NSArray<NSDictionary *> *options = [result[@"options"] isKindOfClass:[NSArray class]] ? result[@"options"] : @[];
    for (NSDictionary *option in options) {
        NSString *key = UIEscaped(option[@"key"] ?: @"");
        NSString *value = UIEscaped(option[@"value"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-mono\">%@</td><td>%@</td></tr>", key, value];
    }
    if (options.count == 0) {
        [html appendString:@"<tr><td colspan=\"2\" class=\"text-center text-secondary p-lg\">No settings configured.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

- (NSString *)renderOzoneSignaturesPartial:(NSDictionary *)result {
    return @"<div class=\"mb-lg\"><form class=\"form\" data-ui-form=\"find-ozone-related\"><div class=\"form-group\"><label for=\"ozone-find-did\">DID:</label><input type=\"text\" id=\"ozone-find-did\" class=\"form-input\" placeholder=\"did:plc:...\"/></div><button type=\"submit\" class=\"btn btn-primary btn-sm\">Find Related Accounts</button></form></div><div id=\"ozone-signature-results\" aria-live=\"polite\"></div>";
}

- (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    NSArray *related = [result[@"related"] isKindOfClass:[NSArray class]] ? result[@"related"] : @[];
    [html appendString:@"<div class=\"detail-row\"><span class=\"detail-label\">Related Accounts</span></div><ul>"];
    for (NSString *did in related) {
        [html appendFormat:@"<li class=\"text-mono text-xs\">%@</li>", UIEscaped(did)];
    }
    [html appendString:@"</ul></div>"];
    return html;
}

- (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"d-flex gap-sm\" data-ui-form=\"load-hosting-history\"><input type=\"text\" id=\"hosting-did-input\" class=\"form-input flex-1\" placeholder=\"did:plc:...\" value=\""];
    if (did && did.length > 0) {
        [html appendFormat:@"%@", UIEscaped(did)];
    }
    [html appendString:@"\"/><button type=\"submit\" class=\"btn btn-primary btn-sm\">Load History</button></form></div>"];

    if (result[@"error"]) {
        [html appendFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    } else {
        [html appendString:@"<table class=\"table\"><thead><tr><th>PDS</th><th>Status</th><th>Created At</th></tr></thead><tbody>"];
        NSArray<NSDictionary *> *entries = [result[@"entries"] isKindOfClass:[NSArray class]] ? result[@"entries"] : @[];
        for (NSDictionary *entry in entries) {
            NSString *pds = UIEscaped(entry[@"pds"] ?: @"");
            NSString *status = UIEscaped(entry[@"status"] ?: @"");
            NSString *createdAt = UIEscaped(entry[@"createdAt"] ?: @"");
            [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td class=\"text-xs\">%@</td></tr>", pds, status, createdAt];
        }
        if (entries.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No hosting history.</td></tr>"];
        }
        [html appendString:@"</tbody></table>"];
    }
    return html;
}

#pragma mark - Lab (AT Protocol OAuth2 Self-Service)

- (NSString *)labShellHTML:(NSString *)nonce {
    NSString *pdsBaseURL = [self.configuration.pdsBaseURL absoluteString];
    NSString *clientId = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                         self.configuration.host, (unsigned long)self.configuration.port];
    NSString *redirectUri = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                            self.configuration.host, (unsigned long)self.configuration.port];

    return [NSString stringWithFormat:
    @"<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
    @"<title>Garazyk Lab - AT Protocol</title>"
    @"<link rel=\"stylesheet\" href=\"/css/system.css\">"
    @"<link rel=\"stylesheet\" href=\"/css/components.css\">"
    @"<meta name=\"lab-pds-url\" content=\"%@\">"
    @"<meta name=\"lab-client-id\" content=\"%@\">"
    @"<meta name=\"lab-redirect-uri\" content=\"%@\">"
    @"<style nonce=\"%@\">"
    @".lab-shell { max-width: 800px; margin: 0 auto; padding: var(--space-lg); }"
    @".lab-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: var(--space-xl); padding-bottom: var(--space-lg); border-bottom: 1px solid var(--separator-color); }"
    @".lab-header h1 { margin: 0; }"
    @".lab-header a { color: var(--color-text-primary); text-decoration: none; font-size: var(--font-size-sm); }"
    @".lab-section { display: none; }"
    @".lab-section.active { display: block; }"
    @".login-form { margin-top: var(--space-lg); }"
    @".login-form .form-group { margin-bottom: var(--space-md); }"
    @".account-card { background: var(--color-bg-secondary); border: 1px solid var(--separator-color); border-radius: var(--radius-md); padding: var(--space-lg); margin-bottom: var(--space-lg); }"
    @".account-row { display: flex; justify-content: space-between; padding: var(--space-sm) 0; border-bottom: 1px solid var(--separator-color-secondary); }"
    @".account-row:last-child { border-bottom: none; }"
    @".account-label { font-weight: 500; color: var(--color-text-secondary); }"
    @".account-value { font-family: monospace; font-size: var(--font-size-sm); }"
    @".handle-update-form { margin-top: var(--space-lg); padding-top: var(--space-lg); border-top: 1px solid var(--separator-color); }"
    @".handle-update-form .form-group { margin-bottom: var(--space-md); }"
    @"</style>"
    @"</head><body class=\"lab-shell\">"
    @"<header class=\"lab-header\">"
    @"<h1>Garazyk Lab</h1>"
    @"<a href=\"/admin\">← Back to Admin</a>"
    @"</header>"
    @"<main>"
    @"<section class=\"lab-section active\" id=\"lab-login-section\">"
    @"<h2>Sign in with AT Protocol</h2>"
    @"<p class=\"text-secondary\">Enter your handle or DID to sign in to your account.</p>"
    @"<form class=\"login-form\" data-lab-form=\"start-oauth\">"
    @"<div class=\"form-group\">"
    @"<label for=\"lab-handle-input\">Handle or DID</label>"
    @"<input type=\"text\" id=\"lab-handle-input\" class=\"form-input\" placeholder=\"alice.example.com\" />"
    @"</div>"
    @"<button type=\"submit\" class=\"btn btn-primary\">Sign In with AT Protocol</button>"
    @"</form>"
    @"</section>"
    @"<section class=\"lab-section\" id=\"lab-account-section\">"
    @"<div class=\"account-card\">"
    @"<h2>Your Account</h2>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">DID</span>"
    @"<span class=\"account-value\" id=\"lab-did-display\">—</span>"
    @"</div>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">Handle</span>"
    @"<span class=\"account-value\" id=\"lab-handle-display\">—</span>"
    @"</div>"
    @"<div class=\"account-row\">"
    @"<span class=\"account-label\">Email</span>"
    @"<span class=\"account-value\" id=\"lab-email-display\">—</span>"
    @"</div>"
    @"</div>"
    @"<form class=\"handle-update-form\" data-lab-form=\"update-handle\">"
    @"<h3>Update Handle</h3>"
    @"<p class=\"text-secondary text-sm\">Change your handle to a new one.</p>"
    @"<div class=\"form-group\">"
    @"<label for=\"lab-new-handle-input\">New Handle</label>"
    @"<input type=\"text\" id=\"lab-new-handle-input\" class=\"form-input\" placeholder=\"newhandle.com\" />"
    @"</div>"
    @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Update Handle</button>"
    @"<div id=\"lab-update-result\" aria-live=\"polite\"></div>"
    @"</form>"
    @"<div style=\"margin-top:var(--space-xl);padding-top:var(--space-lg);border-top:1px solid var(--separator-color);\">"
    @"<button data-lab-action=\"sign-out\" class=\"btn btn-secondary btn-sm\">Sign Out</button>"
    @"</div>"
    @"</section>"
    @"</main>"
    @"<script src=\"/js/lab.js\"></script>"
    @"</body></html>",
    UIEscaped(pdsBaseURL), UIEscaped(clientId), UIEscaped(redirectUri), nonce];
}

- (NSString *)labClientMetadataJSON {
    NSString *clientId = [NSString stringWithFormat:@"http://%@:%lu/lab/client-metadata.json",
                         self.configuration.host, (unsigned long)self.configuration.port];
    NSString *redirectUri = [NSString stringWithFormat:@"http://%@:%lu/lab/callback",
                            self.configuration.host, (unsigned long)self.configuration.port];

    NSDictionary *metadata = @{
        @"client_id": clientId,
        @"client_name": @"Garazyk Admin Lab",
        @"redirect_uris": @[redirectUri],
        @"scope": @"atproto transition:generic",
        @"grant_types": @[@"authorization_code", @"refresh_token"],
        @"response_types": @[@"code"],
        @"token_endpoint_auth_method": @"none",
        @"application_type": @"web",
        @"dpop_bound_access_tokens": @YES
    };

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata options:NSJSONWritingPrettyPrinted error:&error];
    if (error) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

#pragma mark - Video Render Methods

- (NSString *)renderVideoHealthPartial:(NSDictionary *)result {
    NSString *status = UISafe(result[@"status"], @"unknown");
    NSString *statusClass = @"status-unknown";
    if ([status isEqualToString:@"online"]) statusClass = @"status-online";
    else if ([status isEqualToString:@"offline"]) statusClass = @"status-offline";
    else if ([status isEqualToString:@"error"]) statusClass = @"status-error";

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"cluster-grid\">"];
    [html appendFormat:@"<div class=\"service-card %@\">", statusClass];
    [html appendString:@"<div class=\"service-header\">"];
    [html appendFormat:@"<span class=\"service-name\">VIDEO</span>"];
    [html appendString:@"<span class=\"status-dot\"></span>"];
    [html appendString:@"</div>"];
    [html appendFormat:@"<div class=\"service-url\">%@</div>", UIEscaped([self.configuration.videoBaseURL absoluteString] ?: @"")];
    if (result[@"latency_ms"]) {
        [html appendFormat:@"<div class=\"service-meta\">Latency: %@ms</div>", result[@"latency_ms"]];
    }
    if (result[@"error"]) {
        [html appendFormat:@"<div class=\"text-xs text-destructive mt-xs\">%@</div>", UIEscaped(result[@"error"])];
    }
    [html appendString:@"</div></div>"];
    return html;
}

- (NSString *)renderVideoJobsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *jobs = [result[@"jobs"] isKindOfClass:[NSArray class]] ? result[@"jobs"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Job ID</th><th>DID</th><th>State</th><th>Progress</th><th>MIME</th><th>Size</th><th>Retries</th><th>Created</th><th>Actions</th></tr></thead><tbody>"];

    for (NSDictionary *job in jobs) {
        NSString *jobId = UISafe(job[@"job_id"], @"");
        NSString *shortJobId = jobId.length > 8 ? [NSString stringWithFormat:@"%@...", [jobId substringToIndex:8]] : jobId;
        NSString *did = UISafe(job[@"did"], @"");
        NSString *shortDid = did;
        if ([did hasPrefix:@"did:plc:"] && did.length > 20) {
            shortDid = [NSString stringWithFormat:@"did:plc:...%@", [did substringFromIndex:did.length - 8]];
        }
        NSString *state = UISafe(job[@"state"], @"");
        NSString *stateBadge = @"badge-secondary";
        if ([state isEqualToString:@"PENDING"]) stateBadge = @"badge-warning";
        else if ([state isEqualToString:@"PROCESSING"] || [state isEqualToString:@"TRANSCODING"] || [state isEqualToString:@"GENERATING_THUMBNAIL"]) stateBadge = @"badge-info";
        else if ([state isEqualToString:@"COMPLETED"]) stateBadge = @"badge-success";
        else if ([state isEqualToString:@"FAILED"]) stateBadge = @"badge-destructive";

        NSNumber *progressNum = [job[@"progress"] isKindOfClass:[NSNumber class]] ? job[@"progress"] : @0;
        int progress = [progressNum intValue];
        NSString *progressBar = [NSString stringWithFormat:@"<div class=\"progress-bar\"><div class=\"progress-fill\" style=\"width:%d%%\"></div></div><span class=\"text-sm\">%d%%</span>", progress, progress];

        NSString *mimeType = UISafe(job[@"mime_type"], @"-");
        NSNumber *fileSizeNum = [job[@"file_size"] isKindOfClass:[NSNumber class]] ? job[@"file_size"] : nil;
        NSString *fileSize = @"-";
        if (fileSizeNum) {
            long long bytes = [fileSizeNum longLongValue];
            if (bytes >= 1048576) fileSize = [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
            else if (bytes >= 1024) fileSize = [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
            else fileSize = [NSString stringWithFormat:@"%lld B", bytes];
        }
        NSNumber *retryCount = [job[@"retry_count"] isKindOfClass:[NSNumber class]] ? job[@"retry_count"] : @0;
        NSString *createdAt = UISafe(job[@"created_at"], @"-");

        NSString *actions = @"";
        if ([state isEqualToString:@"FAILED"]) {
            actions = [NSString stringWithFormat:@"<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"retry-video-job\" data-ui-job-id=\"%@\">Retry</button>", UIEscaped(jobId)];
        }

        [html appendFormat:@"<tr><td class=\"text-mono text-sm\" title=\"%@\">%@</td><td class=\"text-mono text-sm\" title=\"%@\">%@</td><td><span class=\"badge %@\">%@</span></td><td>%@</td><td class=\"text-sm\">%@</td><td class=\"text-sm\">%@</td><td>%@</td><td class=\"text-sm\">%@</td><td>%@</td></tr>",
            UIEscaped(jobId), UIEscaped(shortJobId),
            UIEscaped(did), UIEscaped(shortDid),
            stateBadge, UIEscaped(state),
            progressBar,
            UIEscaped(mimeType),
            UIEscaped(fileSize),
            retryCount,
            UIEscaped(createdAt),
            actions];
    }

    if (jobs.count == 0) {
        [html appendString:@"<tr><td colspan=\"9\" class=\"text-center text-secondary p-lg\">No video jobs found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];

    NSString *cursor = UIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/video-jobs?cursor=%@\" hx-target=\"#video-jobs\">Load more</button></div>", UIEscaped(cursor)];
    }
    return html;
}

- (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSDictionary *jobStatus = [result[@"jobStatus"] isKindOfClass:[NSDictionary class]] ? result[@"jobStatus"] : result;
    if (!jobStatus || ![jobStatus isKindOfClass:[NSDictionary class]]) {
        return @"<div class=\"text-secondary text-sm\">No job data returned.</div>";
    }

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendString:@"<table class=\"table\"><thead><tr><th>Field</th><th>Value</th></tr></thead><tbody>"];

    NSArray *fields = @[
        @[@"Job ID", @"jobId"],
        @[@"DID", @"did"],
        @[@"State", @"state"],
        @[@"Progress", @"progress"],
        @[@"Error", @"error"],
        @[@"Message", @"message"],
    ];

    for (NSArray *field in fields) {
        NSString *label = field[0];
        NSString *key = field[1];
        id value = jobStatus[key];
        NSString *display = @"";
        if ([value isKindOfClass:[NSString class]]) {
            display = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            display = [value stringValue];
        }
        if (display.length == 0) display = @"-";
        [html appendFormat:@"<tr><td class=\"text-sm\">%@</td><td class=\"text-mono text-sm\">%@</td></tr>", label, UIEscaped(display)];
    }

    // Blob info
    id blob = jobStatus[@"blob"];
    if ([blob isKindOfClass:[NSDictionary class]]) {
        NSDictionary *blobDict = blob;
        [html appendFormat:@"<tr><td class=\"text-sm\">Blob CID</td><td class=\"text-mono text-sm\">%@</td></tr>", UIEscaped(UISafe(blobDict[@"ref"][@"$link"], UISafe(blobDict[@"cid"], @"-")))];
        NSNumber *blobSize = [blobDict[@"size"] isKindOfClass:[NSNumber class]] ? blobDict[@"size"] : nil;
        if (blobSize) {
            long long bytes = [blobSize longLongValue];
            NSString *sizeStr = bytes >= 1048576 ? [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0] : [NSString stringWithFormat:@"%lld B", bytes];
            [html appendFormat:@"<tr><td class=\"text-sm\">Blob Size</td><td class=\"text-sm\">%@</td></tr>", UIEscaped(sizeStr)];
        }
    }

    [html appendString:@"</tbody></table>"];

    NSString *state = UISafe(jobStatus[@"state"], @"");
    if ([state isEqualToString:@"FAILED"]) {
        NSString *jobId = UISafe(jobStatus[@"jobId"], @"");
        [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" data-ui-action=\"retry-video-job\" data-ui-job-id=\"%@\">Retry Job</button></div>", UIEscaped(jobId)];
    }

    [html appendString:@"</div>"];
    return html;
}

- (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])];
    }

    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"metric-row\">"];

    id canUpload = result[@"canUpload"];
    NSString *canUploadStr = @"-";
    if ([canUpload isKindOfClass:[NSNumber class]]) {
        canUploadStr = [canUpload boolValue] ? @"Yes" : @"No";
    } else if ([canUpload isKindOfClass:[NSString class]]) {
        canUploadStr = canUpload;
    }

    id remainingVideos = result[@"remainingDailyVideos"];
    NSString *remainingVideosStr = @"-";
    if ([remainingVideos isKindOfClass:[NSNumber class]]) {
        remainingVideosStr = [remainingVideos stringValue];
    }

    id remainingBytes = result[@"remainingDailyBytes"];
    NSString *remainingBytesStr = @"-";
    if ([remainingBytes isKindOfClass:[NSNumber class]]) {
        long long bytes = [remainingBytes longLongValue];
        if (bytes >= 1073741824) remainingBytesStr = [NSString stringWithFormat:@"%.1f GB", bytes / 1073741824.0];
        else if (bytes >= 1048576) remainingBytesStr = [NSString stringWithFormat:@"%.1f MB", bytes / 1048576.0];
        else remainingBytesStr = [NSString stringWithFormat:@"%lld B", bytes];
    }

    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-value\">%@</div><div class=\"metric-label\">Can Upload</div></div>", UIEscaped(canUploadStr)];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-value\">%@</div><div class=\"metric-label\">Remaining Daily Videos</div></div>", UIEscaped(remainingVideosStr)];
    [html appendFormat:@"<div class=\"metric-card\"><div class=\"metric-value\">%@</div><div class=\"metric-label\">Remaining Daily Bytes</div></div>", UIEscaped(remainingBytesStr)];

    [html appendString:@"</div>"];
    return html;
}


@end
