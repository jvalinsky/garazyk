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

    // Security: Active sessions
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/sessions" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchActiveSessionsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUISecurityPack renderSessionsPartial:result]];
    }];

    // Security: App passwords
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/app-passwords" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchAppPasswordsForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[GZAdminUISecurityPack renderAppPasswordsPartial:result]];
    }];

    // Security: Revoke session
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/revoke-session" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *sessionID = [request.jsonBody[@"id"] isKindOfClass:[NSString class]] ? request.jsonBody[@"id"] : @"";
        NSDictionary *result = [weakSelf.backendClient revokeSessionForDID:did sessionID:sessionID];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Session revoked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Security: Delete app password
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-app-password" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *name = [request.jsonBody[@"name"] isKindOfClass:[NSString class]] ? request.jsonBody[@"name"] : @"";
        NSDictionary *result = [weakSelf.backendClient deleteAppPasswordForDID:did passwordName:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"App password deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Security: Create app password
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/create-app-password" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request.jsonBody[@"did"] isKindOfClass:[NSString class]] ? request.jsonBody[@"did"] : @"";
        NSString *name = [request.jsonBody[@"name"] isKindOfClass:[NSString class]] ? request.jsonBody[@"name"] : @"";
        NSDictionary *result = [weakSelf.backendClient createAppPasswordForDID:did name:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"App password created.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];
}

@end
