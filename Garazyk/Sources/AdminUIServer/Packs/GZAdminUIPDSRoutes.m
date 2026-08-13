// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUIPDSPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (PDSRoutes)

- (void)registerPDSRoutes {
    __weak typeof(self) weakSelf = self;

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/accounts" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *query = [request queryParamForKey:@"q"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient searchAccountsWithQuery:query];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderAccountsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/invites" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchInviteCodes];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderInvitesPartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/disable-invites" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *account = [request.jsonBody[@"account"] isKindOfClass:[NSString class]] ? request.jsonBody[@"account"] : [request queryParamForKey:@"account"];
        NSDictionary *result = [weakSelf.backendClient disableInvitesForAccount:account ?: @""];
        if (result[@"error"]) {
            response.statusCode = 400;
        } else {
            response.statusCode = 200;
        }
        response.contentType = @"text/html; charset=utf-8";
        NSString *message = result[@"error"]
            ? [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", GZAdminUIEscaped(result[@"message"] ?: result[@"error"])]
            : @"<div class=\"alert alert-success\">Invites disabled for account.</div>";
        [response setBodyString:message];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-takedown" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = [request.jsonBody[@"dids"] isKindOfClass:[NSArray class]] ? request.jsonBody[@"dids"] : @[];
        NSDictionary *result = [weakSelf.backendClient bulkTakedownAccounts:dids];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-delete" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = [request.jsonBody[@"dids"] isKindOfClass:[NSArray class]] ? request.jsonBody[@"dids"] : @[];
        NSDictionary *result = [weakSelf.backendClient bulkDeleteAccounts:dids];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    // PDS: Account detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/account-detail" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchAccountInfoForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderAccountDetailPartial:result]];
    }];

    // PDS: Server stats (prefer local snapshot when embedded; else XRPC getServerStats)
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-stats" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = nil;
        id<GZAdminUIPDSOverviewSnapshot> local = [GZAdminUIPDSPack snapshotForHost:weakSelf];
        if (local) {
            result = [local snapshot];
        }
        if (!result) {
            result = [weakSelf.backendClient fetchServerStats];
        }
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderServerStatsPartial:result ?: @{}]];
    }];

    // PDS: Audit log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/audit-log" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchAuditLogWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderAuditLogPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/blobs" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = did && did.length > 0 ? [weakSelf.backendClient fetchBlobsForDID:did limit:25 cursor:cursor] : @{@"blobs": @[]};
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderBlobsPartial:result did:did]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/enable-invites" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *account = [request.jsonBody[@"account"] isKindOfClass:[NSString class]] ? request.jsonBody[@"account"] : [request queryParamForKey:@"account"];
        NSDictionary *result = [weakSelf.backendClient enableInvitesForAccount:account ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Invites enabled for account.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];

    // PDS: Update handle action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-handle" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *handle = [request.jsonBody[@"handle"] isKindOfClass:[NSString class]] ? request.jsonBody[@"handle"] : @"";
        NSDictionary *result = [weakSelf.backendClient updateAccountHandle:handle forDID:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Handle updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];

    // PDS: Delete account
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-account" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSDictionary *result = [weakSelf.backendClient deleteAccount:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Account deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];

    // PDS: Fetch reports
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-reports" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchReportsWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUIPDSPack renderPDSReportsPartial:result]];
    }];

    // PDS: Resolve report
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/resolve-pds-report" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *reportID = [request.jsonBody[@"reportID"] isKindOfClass:[NSString class]] ? request.jsonBody[@"reportID"] : @"";
        NSString *action = [request.jsonBody[@"action"] isKindOfClass:[NSString class]] ? request.jsonBody[@"action"] : @"";
        NSDictionary *result = [weakSelf.backendClient resolveReport:reportID action:action];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Report resolved.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];
}

@end
