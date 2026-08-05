// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"

#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Auth/Crypto/CryptoUtils.h"
#import "Debug/GZLogger.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UITemplateEngine.h"
@implementation GZAdminUIHost (Renderers)

#pragma mark - Ozone Render Methods

- (NSString *)renderOzoneStatusesPartial:(NSDictionary *)result {
    if (!result[@"error"] && !result[@"message"]) {
        NSMutableDictionary *ctx = [result mutableCopy];
        if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
        return [UITemplateEngine renderTemplate:@"ozone-statuses" context:ctx];
    }
    return [UITemplateEngine renderTemplate:@"ozone-statuses" context:result];
}

- (NSString *)renderOzoneEventsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (result[@"events"]) {
        NSMutableArray *mappedEvents = [NSMutableArray array];
        for (NSDictionary *e in result[@"events"]) {
            NSMutableDictionary *me = [e mutableCopy];
            NSDictionary *subject = e[@"subject"];
            me[@"subject_did"] = subject[@"did"] ?: subject[@"uri"] ?: @"";
            [mappedEvents addObject:me];
        }
        ctx[@"events"] = mappedEvents;
    }
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-events" context:ctx];
}

- (NSString *)renderOzoneSubjectPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-subject" context:ctx];
}

- (NSString *)renderOzoneTeamPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-team" context:ctx];
}

- (NSString *)renderOzoneSetsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-sets" context:ctx];
}

- (NSString *)renderOzoneTemplatesPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"templates"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *t in result[@"templates"]) {
            NSMutableDictionary *mt = [t mutableCopy];
            NSString *content = t[@"contentMarkdown"] ?: @"";
            if (content.length > 80) content = [[content substringToIndex:80] stringByAppendingString:@"..."];
            mt[@"contentMarkdownShort"] = content;
            [mapped addObject:mt];
        }
        ctx[@"templates"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"ozone-templates" context:ctx];
}

- (NSString *)renderOzoneConfigPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:&jsonError];
    NSString *jsonStr = jsonError ? @"" : [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    ctx[@"jsonStr"] = jsonStr;
    NSMutableArray *pairs = [NSMutableArray array];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [pairs addObject:@{@"key": key, @"value": [value description]}];
    }];
    ctx[@"configPairs"] = pairs;
    return [UITemplateEngine renderTemplate:@"ozone-config" context:ctx];
}

#pragma mark - Render Methods

- (NSString *)renderConnectionsPartial {
    NSDictionary *fields = @{
        @"pdsURL": [self.configuration.pdsBaseURL absoluteString] ?: @"",
        @"pdsToken": self.configuration.pdsAdminToken ?: @"",
        @"appViewURL": [self.configuration.appViewBaseURL absoluteString] ?: @"",
        @"appViewToken": self.configuration.appViewAdminToken ?: @"",
        @"relayURL": [self.configuration.relayBaseURL absoluteString] ?: @"",
        @"relayToken": self.configuration.relayAdminToken ?: @"",
        @"plcURL": [self.configuration.plcBaseURL absoluteString] ?: @"",
        @"plcToken": self.configuration.plcAdminToken ?: @"",
        @"chatURL": [self.configuration.chatBaseURL absoluteString] ?: @"",
        @"chatToken": self.configuration.chatAdminToken ?: @"",
        @"videoURL": [self.configuration.videoBaseURL absoluteString] ?: @"",
        @"videoToken": self.configuration.videoAdminToken ?: @""
    };
    NSArray *order = @[
        @{@"id": @"pds", @"key": @"pds", @"label": @"PDS"},
        @{@"id": @"appview", @"key": @"appView", @"label": @"APPVIEW"},
        @{@"id": @"relay", @"key": @"relay", @"label": @"RELAY"},
        @{@"id": @"plc", @"key": @"plc", @"label": @"PLC"},
        @{@"id": @"chat", @"key": @"chat", @"label": @"CHAT"},
        @{@"id": @"video", @"key": @"video", @"label": @"VIDEO"}
    ];
    NSMutableArray *services = [NSMutableArray array];
    for (NSDictionary *entry in order) {
        NSString *urlKey = [entry[@"key"] stringByAppendingString:@"URL"];
        NSString *tokenKey = [entry[@"key"] stringByAppendingString:@"Token"];
        [services addObject:@{
            @"id": entry[@"id"],
            @"label": entry[@"label"],
            @"urlKey": urlKey,
            @"urlVal": fields[urlKey],
            @"tokenKey": tokenKey,
            @"tokenVal": fields[tokenKey]
        }];
    }
    return [UITemplateEngine renderTemplate:@"connections" context:@{@"services": services}];
}

- (NSString *)renderOverviewPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (result[@"services"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *svc in result[@"services"]) {
            NSMutableDictionary *ms = [svc mutableCopy];
            NSString *name = svc[@"name"] ?: @"unknown";
            ms[@"nameUpper"] = [name uppercaseString];
            NSString *status = svc[@"status"] ?: @"unknown";
            if ([status isEqualToString:@"online"]) ms[@"statusClass"] = @"status-online";
            else if ([status isEqualToString:@"offline"]) ms[@"statusClass"] = @"status-offline";
            else if ([status isEqualToString:@"error"]) ms[@"statusClass"] = @"status-error";
            else ms[@"statusClass"] = @"status-unknown";
            ms[@"url"] = svc[@"url"] ?: @"-";
            [mapped addObject:ms];
        }
        ctx[@"services"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"overview" context:ctx];
}

- (NSString *)renderMSTAccountsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"mst-accounts" context:ctx];
}

- (NSString *)renderMSTTreePartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSArray *nodes = [result[@"nodes"] isKindOfClass:[NSArray class]] ? result[@"nodes"] : @[];
    NSString *rootCID = result[@"rootCID"] ?: @"";
    ctx[@"emptyTree"] = @(nodes.count == 0 && rootCID.length == 0);
    ctx[@"hasNodes"] = @(nodes.count > 0);
    if (nodes.count > 0) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *node in nodes) {
            NSMutableDictionary *mn = [node mutableCopy];
            NSArray *entries = [node[@"entries"] isKindOfClass:[NSArray class]] ? node[@"entries"] : @[];
            mn[@"entriesCount"] = @(entries.count);
            mn[@"hasEntries"] = @(entries.count > 0);
            NSString *cid = node[@"cid"] ?: @"";
            mn[@"shortCid"] = [cid substringToIndex:MIN(16, cid.length)];
            [mapped addObject:mn];
        }
        ctx[@"nodes"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"mst-tree" context:ctx];
}

- (NSString *)renderMSTStatsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSMutableArray *pairs = [NSMutableArray array];
    [result enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [pairs addObject:@{@"key": key, @"value": [value description]}];
    }];
    ctx[@"statsPairs"] = pairs;
    return [UITemplateEngine renderTemplate:@"mst-stats" context:ctx];
}

#pragma mark - Phase 1 Render Methods

- (NSString *)renderOzoneModerationReportsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"reports"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *report in result[@"reports"]) {
            NSMutableDictionary *mr = [report mutableCopy];
            if (!mr[@"resolvedAt"]) mr[@"resolvedAt"] = @"pending";
            [mapped addObject:mr];
        }
        ctx[@"reports"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"ozone-reports" context:ctx];
}

#pragma mark - Phase 2 Render Methods

- (NSString *)renderPLCHealthPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"status"] = status;
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    return [UITemplateEngine renderTemplate:@"plc-health" context:ctx];
}

- (NSString *)renderPLCMetricsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (!ctx[@"text"]) ctx[@"text"] = @"";
    return [UITemplateEngine renderTemplate:@"plc-metrics" context:ctx];
}

- (NSString *)renderPLCListPartial:(NSDictionary *)result cursor:(nullable NSString *)cursor {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (cursor) ctx[@"cursor"] = cursor;
    if (result[@"dids"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSString *did in result[@"dids"]) {
            [mapped addObject:@{@"did": did}];
        }
        ctx[@"mappedDids"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"plc-list" context:ctx];
}

#pragma mark - Phase 3 Render Methods

- (NSString *)renderOzoneScheduledPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"actions"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *action in result[@"actions"]) {
            NSMutableDictionary *ma = [action mutableCopy];
            if (!ma[@"status"]) ma[@"status"] = @"pending";
            [mapped addObject:ma];
        }
        ctx[@"actions"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"ozone-scheduled" context:ctx];
}

- (NSString *)renderOzoneVerificationPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-verification" context:ctx];
}

- (NSString *)renderOzoneSafelinksPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"rules"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *rule in result[@"rules"]) {
            NSMutableDictionary *mr = [rule mutableCopy];
            if (!mr[@"pattern"]) mr[@"pattern"] = @"domain";
            if (!mr[@"action"]) mr[@"action"] = @"block";
            if (!mr[@"reason"]) mr[@"reason"] = @"none";
            [mapped addObject:mr];
        }
        ctx[@"rules"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"ozone-safelinks" context:ctx];
}

#pragma mark - Phase 6 Render Methods

- (NSString *)renderOzoneSettingsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-settings" context:ctx];
}

- (NSString *)renderOzoneSignaturesPartial:(NSDictionary *)result {
    return [UITemplateEngine renderTemplate:@"ozone-signatures" context:result ?: @{}];
}

- (NSString *)renderOzoneSignatureResultsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"related"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSString *did in result[@"related"]) {
            [mapped addObject:@{@"did": did}];
        }
        ctx[@"related"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"ozone-signature-results" context:ctx];
}

- (NSString *)renderOzoneHostingPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (did) ctx[@"did"] = did;
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"ozone-hosting" context:ctx];
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
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    NSString *status = result[@"status"] ?: @"unknown";
    ctx[@"status"] = status;
    ctx[@"statusBadge"] = [status isEqualToString:@"ok"] ? @"badge badge-success" : @"badge badge-destructive";
    return [UITemplateEngine renderTemplate:@"video-health" context:ctx];
}

- (NSString *)renderVideoJobsPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"jobs"]) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *job in result[@"jobs"]) {
            NSMutableDictionary *mj = [job mutableCopy];
            NSString *state = job[@"state"] ?: @"";
            NSString *badge = @"badge";
            if ([state isEqualToString:@"JOB_STATE_COMPLETED"]) badge = @"badge badge-success";
            else if ([state isEqualToString:@"JOB_STATE_FAILED"]) badge = @"badge badge-destructive";
            mj[@"badgeClass"] = badge;
            [mapped addObject:mj];
        }
        ctx[@"jobs"] = mapped;
    }
    return [UITemplateEngine renderTemplate:@"video-jobs" context:ctx];
}

- (NSString *)renderVideoJobDetailPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    if (result[@"job"]) {
        NSMutableArray *pairs = [NSMutableArray array];
        [(NSDictionary *)result[@"job"] enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [pairs addObject:@{@"key": key, @"value": [value description]}];
        }];
        ctx[@"detailPairs"] = pairs;
    }
    return [UITemplateEngine renderTemplate:@"video-job-detail" context:ctx];
}

- (NSString *)renderVideoQuotasPartial:(NSDictionary *)result {
    NSMutableDictionary *ctx = [result mutableCopy];
    if (!ctx[@"message"]) ctx[@"message"] = result[@"error"] ?: @"";
    return [UITemplateEngine renderTemplate:@"video-quotas" context:ctx];
}


@end
