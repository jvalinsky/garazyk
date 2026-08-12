// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"

#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "AdminUIServer/UITemplateEngine.h"

@implementation GZAdminUIPDSPack

+ (NSString *)packIdentifier {
    return @"pds";
}

+ (NSString *)displayName {
    return @"PDS";
}

+ (NSArray<NSDictionary<NSString *, id> *> *)sidebarSections {
    return @[
        @{@"tabIdentifier": @"pds", @"displayName": @"PDS"},
    ];
}

+ (void)registerRoutesWithHost:(GZAdminUIHost *)host {
    [host registerPDSRoutes];
}

+ (NSString *)renderAccountsPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *accounts = [result[@"accounts"] isKindOfClass:[NSArray class]] ? result[@"accounts"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@""];

    if (accounts.count > 0) {
        [html appendString:@"<div class=\"bulk-actions mb-sm d-flex gap-sm\">"
         "<button class=\"btn btn-secondary btn-sm\" data-ui-action=\"bulk-action\" data-ui-action-kind=\"takedown\">Bulk Takedown</button>"
         "<button class=\"btn btn-destructive btn-sm\" data-ui-action=\"bulk-action\" data-ui-action-kind=\"delete\">Bulk Delete</button>"
         "</div>"];
    }

    [html appendString:@"<table class=\"table\"><thead><tr><th><input type=\"checkbox\" id=\"select-all-accounts\" data-ui-action=\"toggle-select-all\"></th><th>DID</th><th>Handle</th><th>Email</th></tr></thead><tbody>"];
    if (result[@"error"]) {
        NSString *message = GZAdminUIEscaped(result[@"message"] ?: result[@"error"]);
        [html appendFormat:@"<tr><td colspan=\"4\" class=\"text-destructive\">%@</td></tr>", message];
    } else {
        for (NSDictionary *account in accounts) {
            NSString *did = GZAdminUIEscaped(account[@"did"] ?: @"");
            NSString *handle = GZAdminUIEscaped(account[@"handle"] ?: @"");
            NSString *email = GZAdminUIEscaped(account[@"email"] ?: @"");
            [html appendFormat:@"<tr><td><input type=\"checkbox\" class=\"account-checkbox\" value=\"%@\"></td><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", did, did, handle, email];
        }
        if (accounts.count == 0) {
            [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No accounts found.</td></tr>"];
        }
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)renderInvitesPartial:(NSDictionary *)result {
    NSArray<NSDictionary *> *codes = [result[@"codes"] isKindOfClass:[NSArray class]] ? result[@"codes"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Code</th><th>Available</th><th>Uses</th></tr></thead><tbody>"];
    if (result[@"error"]) {
        NSString *message = GZAdminUIEscaped(result[@"message"] ?: result[@"error"]);
        [html appendFormat:@"<tr><td colspan=\"3\" class=\"text-destructive\">%@</td></tr>", message];
    } else {
        for (NSDictionary *entry in codes) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSString *code = GZAdminUIEscaped(entry[@"code"] ?: @"");
            // Lexicon: available is integer; uses is inviteCodeUse[].
            id availableValue = entry[@"available"];
            NSString *availableText = @"0";
            if ([availableValue isKindOfClass:[NSNumber class]] ||
                [availableValue isKindOfClass:[NSString class]]) {
                availableText = [availableValue description];
            }
            id usesValue = entry[@"uses"];
            NSString *usesText = @"0";
            if ([usesValue isKindOfClass:[NSArray class]]) {
                usesText = [NSString stringWithFormat:@"%lu", (unsigned long)[(NSArray *)usesValue count]];
            } else if ([usesValue isKindOfClass:[NSNumber class]] ||
                       [usesValue isKindOfClass:[NSString class]]) {
                usesText = [usesValue description];
            }
            NSString *available = GZAdminUIEscaped(availableText);
            NSString *uses = GZAdminUIEscaped(usesText);
            [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", code, available, uses];
        }
        if (codes.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No invite codes found.</td></tr>"];
        }
    }
    [html appendString:@"</tbody></table>"];
    return html;
}

+ (NSString *)renderAccountDetailPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSString *did = result[@"did"] ?: @"";
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"account-detail-result\" aria-live=\"polite\"></div><div class=\"detail-grid\">"];
    NSArray *fields = @[@"did", @"handle", @"email", @"emailConfirmed", @"invitesDisabled", @"deactivatedAt"];
    for (NSString *key in fields) {
        id val = result[key];
        if (!val) continue;
        NSString *display = [val isKindOfClass:[NSString class]] ? GZAdminUIEscaped(val) : GZAdminUIEscaped([val description]);
        [html appendFormat:@"<div class=\"detail-field\"><span class=\"detail-label\">%@</span><span class=\"detail-value\">%@</span></div>", key, display];
    }
    [html appendFormat:@"</div><div class=\"mt-lg\"><button class=\"btn btn-destructive btn-sm\" data-ui-action=\"delete-account\" data-ui-did=\"%@\">Delete Account</button></div>", GZAdminUIEscaped(did)];
    return html;
}

+ (NSString *)renderBlobsPartial:(NSDictionary *)result did:(nullable NSString *)did {
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"mb-lg\"><form class=\"d-flex gap-sm\" data-ui-form=\"load-blobs\"><input type=\"text\" id=\"blob-did-input\" class=\"form-input flex-1\" placeholder=\"did:plc:...\" value=\""];
    if (did && did.length > 0) {
        [html appendFormat:@"%@", GZAdminUIEscaped(did)];
    }
    [html appendString:@"\"/><button type=\"submit\" class=\"btn btn-primary btn-sm\">Load Blobs</button></form></div>"];

    if (result[@"error"]) {
        [html appendFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    } else {
        [html appendString:@"<table class=\"table\"><thead><tr><th>CID</th><th>Size</th><th>Type</th></tr></thead><tbody>"];
        NSArray<NSDictionary *> *blobs = [result[@"blobs"] isKindOfClass:[NSArray class]] ? result[@"blobs"] : @[];
        for (NSDictionary *blob in blobs) {
            NSString *cid = GZAdminUIEscaped(blob[@"cid"] ?: @"");
            id sizeValue = blob[@"size"];
            NSString *sizeText = @"0";
            if ([sizeValue isKindOfClass:[NSNumber class]] || [sizeValue isKindOfClass:[NSString class]]) {
                sizeText = [sizeValue description];
            }
            NSString *size = GZAdminUIEscaped(sizeText);
            NSString *type = GZAdminUIEscaped(blob[@"mimeType"] ?: @"");
            [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td>%@</td><td>%@</td></tr>", cid, size, type];
        }
        if (blobs.count == 0) {
            [html appendString:@"<tr><td colspan=\"3\" class=\"text-center text-secondary p-lg\">No blobs found.</td></tr>"];
        }
        [html appendString:@"</tbody></table>"];
        NSString *cursor = GZAdminUIStringFromDict(result, @"cursor");
        if (cursor && cursor.length > 0) {
            [html appendFormat:@"<div class=\"mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/blobs?did=%@&cursor=%@\" hx-target=\"#blobs-content\">Load More</button></div>", GZAdminUIEscaped(did ?: @""), GZAdminUIEscaped(cursor)];
        }
    }
    return html;
}

+ (NSString *)renderServerStatsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSMutableString *html = [NSMutableString stringWithString:@"<div class=\"detail-card\">"];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Repos:</span> <span class=\"detail-value text-mono\">%@</span></div>", GZAdminUIEscaped(result[@"repos"] ?: @"0")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Records:</span> <span class=\"detail-value text-mono\">%@</span></div>", GZAdminUIEscaped(result[@"records"] ?: @"0")];
    [html appendFormat:@"<div class=\"detail-row\"><span class=\"detail-label\">Blobs:</span> <span class=\"detail-value text-mono\">%@</span></div>", GZAdminUIEscaped(result[@"blobs"] ?: @"0")];
    [html appendString:@"</div>"];
    return html;
}

+ (NSString *)renderAuditLogPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *events = [result[@"events"] isKindOfClass:[NSArray class]] ? result[@"events"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<table class=\"table\"><thead><tr><th>Time</th><th>Action</th><th>Subject</th><th>Created By</th></tr></thead><tbody>"];
    for (NSDictionary *event in events) {
        NSString *time = GZAdminUIEscaped(event[@"createdAt"] ?: @"");
        NSString *action = GZAdminUIEscaped(event[@"action"] ?: @"");
        NSString *subject = GZAdminUIEscaped(event[@"subject"] ?: @"");
        NSString *createdBy = GZAdminUIEscaped(event[@"createdBy"] ?: @"");
        [html appendFormat:@"<tr><td class=\"text-xs text-mono\">%@</td><td>%@</td><td class=\"text-mono text-xs\">%@</td><td class=\"text-xs\">%@</td></tr>", time, action, subject, createdBy];
    }
    if (events.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No audit log entries.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    // Pagination
    id cursorObj = result[@"cursor"];
    NSString *cursor = [cursorObj isKindOfClass:[NSString class]] ? cursorObj : nil;
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/audit-log?cursor=%@\" hx-target=\"#audit-log-content\">Load more</button></div>", GZAdminUIEscaped(cursor)];
    }
    return html;
}

+ (NSString *)renderPDSReportsPartial:(NSDictionary *)result {
    if (result[@"error"]) {
        return [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])];
    }
    NSArray<NSDictionary *> *reports = [result[@"reports"] isKindOfClass:[NSArray class]] ? result[@"reports"] : @[];
    NSMutableString *html = [NSMutableString stringWithString:@"<div id=\"pds-reports-result\" aria-live=\"polite\"></div><table class=\"table\"><thead><tr><th>ID</th><th>Created At</th><th>Status</th><th>Actions</th></tr></thead><tbody>"];
    for (NSDictionary *report in reports) {
        NSString *reportID = GZAdminUIEscaped(report[@"id"] ?: @"");
        NSString *createdAt = GZAdminUIEscaped(report[@"createdAt"] ?: @"");
        NSString *status = GZAdminUIEscaped(report[@"status"] ?: @"unknown");
        [html appendFormat:@"<tr><td class=\"text-mono text-xs\">%@</td><td class=\"text-xs\">%@</td><td>%@</td><td><select class=\"form-input\" data-ui-action=\"resolve-pds-report\" data-ui-report-id=\"%@\"><option value=\"\">Resolve as...</option><option value=\"escalate\">Escalate</option><option value=\"mute\">Mute</option><option value=\"markResolved\">Mark Resolved</option></select></td></tr>", reportID, createdAt, status, reportID];
    }
    if (reports.count == 0) {
        [html appendString:@"<tr><td colspan=\"4\" class=\"text-center text-secondary p-lg\">No reports found.</td></tr>"];
    }
    [html appendString:@"</tbody></table>"];
    NSString *cursor = GZAdminUIStringFromDict(result, @"cursor");
    if (cursor.length > 0) {
        [html appendFormat:@"<div class=\"d-flex justify-between mt-sm\"><button class=\"btn btn-secondary btn-sm\" hx-get=\"/admin/partials/pds-reports?cursor=%@\" hx-target=\"#pds-reports-content\">Load more</button></div>", GZAdminUIEscaped(cursor)];
    }
    return html;
}

@end
