// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation UIServerRuntime (PDSRoutes)

- (void)registerPDSRoutes {
    __weak typeof(self) weakSelf = self;

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/overview" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *overview = [weakSelf.backendClient fetchServiceOverview];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOverviewPartial:overview]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/connections" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderConnectionsPartial]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/accounts" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *query = [request queryParamForKey:@"q"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient searchAccountsWithQuery:query];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAccountsPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/invites" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchInviteCodes];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderInvitesPartial:result]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/disable-invites" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *account = request.jsonBody[@"account"] ?: [request queryParamForKey:@"account"];
        NSDictionary *result = [weakSelf.backendClient disableInvitesForAccount:account ?: @""];
        if (result[@"error"]) {
            response.statusCode = 400;
        } else {
            response.statusCode = 200;
        }
        response.contentType = @"text/html; charset=utf-8";
        NSString *message = result[@"error"]
            ? [NSString stringWithFormat:@"<div class=\"alert alert-destructive\">%@</div>", UIEscaped(result[@"message"] ?: result[@"error"])]
            : @"<div class=\"alert alert-success\">Invites disabled for account.</div>";
        [response setBodyString:message];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-takedown" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient bulkTakedownAccounts:dids ?: @[]];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/bulk-delete" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"];
        NSDictionary *result = [weakSelf.backendClient bulkDeleteAccounts:dids ?: @[]];
        response.statusCode = 200;
        response.contentType = @"application/json";
        [response setJsonBody:result];
    }];

    // PDS: Account detail
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/account-detail" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient fetchAccountInfoForDID:did];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAccountDetailPartial:result]];
    }];

    // PDS: Server stats
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-stats" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchServerStats];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderServerStatsPartial:result]];
    }];

    // PDS: Audit log
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/audit-log" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchAuditLogWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderAuditLogPartial:result]];
    }];

    [self.httpServer addRoute:@"GET" path:@"/admin/partials/blobs" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = did && did.length > 0 ? [weakSelf.backendClient fetchBlobsForDID:did limit:25 cursor:cursor] : @{@"blobs": @[]};
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderBlobsPartial:result did:did]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/enable-invites" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *account = request.jsonBody[@"account"] ?: [request queryParamForKey:@"account"];
        NSDictionary *result = [weakSelf.backendClient enableInvitesForAccount:account ?: @""];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Invites enabled for account.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PDS: Update handle action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-handle" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSString *handle = request.jsonBody[@"handle"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient updateAccountHandle:handle forDID:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Handle updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PDS: Delete account
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-account" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteAccount:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Account deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // PDS: Fetch reports
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/pds-reports" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchReportsWithCursor:cursor limit:25];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderPDSReportsPartial:result]];
    }];

    // PDS: Resolve report
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/resolve-pds-report" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *reportID = request.jsonBody[@"reportID"] ?: @"";
        NSString *action = request.jsonBody[@"action"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient resolveReport:reportID action:action];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Report resolved.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Connections: Update service URLs and tokens
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-connections" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *body = request.jsonBody;
        if (![body isKindOfClass:[NSDictionary class]]) {
            response.statusCode = 400;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:@"<div class=\"alert alert-destructive\">Invalid request body.</div>"];
            return;
        }
        BOOL valid = [weakSelf.configuration updateWithDictionary:body];
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        if (valid) {
            [response setBodyString:@"<div class=\"alert alert-success\">Connections updated. Changes apply immediately but are not persisted across restarts.</div>"];
        } else {
            [response setBodyString:@"<div class=\"alert alert-destructive\">Some URLs were invalid and could not be applied. Other values were saved.</div>"];
        }
        // Re-render the form with updated values
        [response setBodyString:[response.bodyString stringByAppendingString:[weakSelf renderConnectionsPartial]]];
    }];
}

@end
