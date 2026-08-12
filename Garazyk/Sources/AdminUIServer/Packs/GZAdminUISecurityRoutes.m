// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/GZAdminUIHost+Private.h"
#import "AdminUIServer/Packs/GZAdminUISecurityPack.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/GZAdminUIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation GZAdminUIHost (SecurityRoutes)

- (void)registerSecurityRoutes {
    __weak typeof(self) weakSelf = self;

    // Landing pane for shell dynamic tab /admin/partials/security
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/security" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.statusCode = 200;
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:
         @"<section class=\"admin-section\">"
         @"<h3 class=\"section-title\">Lookup</h3>"
         @"<form class=\"d-flex gap-sm\" hx-get=\"/admin/partials/sessions\" hx-target=\"#security-sessions\">"
         @"<label class=\"sr-only\" for=\"security-did\">DID</label>"
         @"<input id=\"security-did\" class=\"form-input flex-1\" type=\"text\" name=\"did\" placeholder=\"did:plc:...\" required/>"
         @"<button type=\"submit\" class=\"btn btn-primary btn-sm\">Sessions</button>"
         @"</form>"
         @"<form class=\"d-flex gap-sm mt-sm\" hx-get=\"/admin/partials/app-passwords\" hx-target=\"#security-app-passwords\">"
         @"<label class=\"sr-only\" for=\"security-app-did\">DID</label>"
         @"<input id=\"security-app-did\" class=\"form-input flex-1\" type=\"text\" name=\"did\" placeholder=\"did:plc:...\" required/>"
         @"<button type=\"submit\" class=\"btn btn-secondary btn-sm\">App passwords</button>"
         @"</form>"
         @"</section>"
         @"<section class=\"admin-section mt-lg\"><h3 class=\"section-title\">Sessions</h3>"
         @"<div id=\"security-sessions\" class=\"text-secondary text-sm\">Enter a DID to list sessions.</div></section>"
         @"<section class=\"admin-section mt-lg\"><h3 class=\"section-title\">App Passwords</h3>"
         @"<div id=\"security-app-passwords\" class=\"text-secondary text-sm\">Enter a DID to list app passwords.</div></section>"];
    }];

    // Security: Active sessions
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/sessions" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchActiveSessionsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUISecurityPack renderSessionsPartial:result]];
    }];

    // Security: App passwords
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/app-passwords" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchAppPasswordsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUISecurityPack renderAppPasswordsPartial:result]];
    }];

    // Security: Revoke session
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/revoke-session" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *sessionID = [request.jsonBody[@"id"] isKindOfClass:[NSString class]] ? request.jsonBody[@"id"] : @"";
        NSDictionary *result = [weakSelf.backendClient revokeSessionForDID:did sessionID:sessionID];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Session revoked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];

    // Security: Delete app password
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-app-password" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *name = [request.jsonBody[@"name"] isKindOfClass:[NSString class]] ? request.jsonBody[@"name"] : @"";
        NSDictionary *result = [weakSelf.backendClient deleteAppPasswordForDID:did passwordName:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"App password deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];

    // Security: Create app password
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/create-app-password" handler:^(ATProtoHttpRequest *request, ATProtoHttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *name = [request.jsonBody[@"name"] isKindOfClass:[NSString class]] ? request.jsonBody[@"name"] : @"";
        NSDictionary *result = [weakSelf.backendClient createAppPasswordForDID:did name:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"App password created.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, GZAdminUIEscaped(msg)]];
    }];
}

@end
