// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"
#import "AdminUIServer/UIServerRuntime+Private.h"
#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

@implementation UIServerRuntime (OzoneRoutes)

- (void)registerOzoneRoutes {
    __weak typeof(self) weakSelf = self;

    // Ozone: Moderation statuses
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-statuses" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneStatusesWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneStatusesPartial:result]];
    }];

    // Ozone: Moderation events
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-events" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneEventsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneEventsPartial:result]];
    }];

    // Ozone: Subject status
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-subject" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = [weakSelf.backendClient fetchSubjectStatusForDID:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSubjectPartial:result]];
    }];

    // Ozone: Moderation reports
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-reports" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchModerationReportsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneModerationReportsPartial:result]];
    }];

    // Ozone: Scheduled actions
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-scheduled" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchScheduledActionsWithStatuses:nil cursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneScheduledPartial:result]];
    }];

    // Ozone: Schedule action
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-schedule-action" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *actionSpec = request.jsonBody;
        NSDictionary *result = [weakSelf.backendClient scheduleAction:actionSpec ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Action scheduled.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Cancel scheduled actions
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-cancel-scheduled" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *subjects = request.jsonBody[@"subjects"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient cancelScheduledActionsForSubjects:subjects];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Scheduled actions cancelled.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Verification
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-verification" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient listOzoneVerifications];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneVerificationPartial:result]];
    }];

    // Ozone: Grant verification
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-grant-verification" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"];
        NSString *displayName = request.jsonBody[@"displayName"] ?: @"";
        if (!did || did.length == 0) {
            response.statusCode = 400;
            response.contentType = @"text/html; charset=utf-8";
            [response setBodyString:@"<div class=\"alert alert-destructive\">DID required</div>"];
            return;
        }
        NSDictionary *verification = @{@"did": did, @"displayName": displayName};
        NSDictionary *result = [weakSelf.backendClient grantOzoneVerifications:@[verification]];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Verification granted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Revoke verification
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-revoke-verification" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient revokeOzoneVerifications:dids];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Verification revoked.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Safelinks
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-safelinks" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchSafelinkRules];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSafelinksPartial:result]];
    }];

    // Ozone: Add safelink rule
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/add-safelink-rule" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *rule = request.jsonBody ?: @{};
        NSDictionary *result = [weakSelf.backendClient addSafelinkRule:rule];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Safelink rule added.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Remove safelink rule
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/remove-safelink-rule" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *url = request.jsonBody[@"url"] ?: @"";
        NSString *pattern = request.jsonBody[@"pattern"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient removeSafelinkRule:url pattern:pattern];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Safelink rule removed.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Settings
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-settings" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient listOzoneSettings];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSettingsPartial:result]];
    }];

    // Ozone: Upsert setting
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/upsert-ozone-setting" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *option = request.jsonBody ?: @{};
        NSDictionary *result = [weakSelf.backendClient upsertOzoneSetting:option];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Setting updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Signatures
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-signatures" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSignaturesPartial:nil]];
    }];

    // Ozone: Find related accounts
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-find-related" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient findRelatedAccounts:did];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSignatureResultsPartial:result]];
    }];

    // Ozone: Find correlation
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/ozone-find-correlation" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSArray *dids = request.jsonBody[@"dids"] ?: @[];
        NSDictionary *result = [weakSelf.backendClient findSignatureCorrelation:dids];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSignatureResultsPartial:result]];
    }];

    // Ozone: Hosting history
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-hosting" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = [request queryParamForKey:@"did"];
        NSDictionary *result = did && did.length > 0 ? [weakSelf.backendClient fetchHostingHistoryForDID:did] : @{@"entries": @[]};
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneHostingPartial:result did:did]];
    }];

    // Ozone: Team members
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-team" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchOzoneTeamMembers];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneTeamPartial:result]];
    }];

    // Ozone: Sets
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-sets" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSDictionary *result = [weakSelf.backendClient fetchOzoneSetsWithCursor:cursor limit:50];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneSetsPartial:result]];
    }];

    // Ozone: Templates
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-templates" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchOzoneTemplates];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneTemplatesPartial:result]];
    }];

    // Ozone: Config
    [self.httpServer addRoute:@"GET" path:@"/admin/partials/ozone-config" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *result = [weakSelf.backendClient fetchOzoneConfig];
        response.contentType = @"text/html; charset=utf-8";
        [response setBodyString:[weakSelf renderOzoneConfigPartial:result]];
    }];

    // Ozone: Emit moderation event
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/emit-moderation-event" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *event = request.jsonBody;
        NSDictionary *result = [weakSelf.backendClient emitModerationEvent:event];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Event emitted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Delete set
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-ozone-set" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *name = request.jsonBody[@"name"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteOzoneSet:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Set deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Delete template
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/delete-ozone-template" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *name = request.jsonBody[@"name"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient deleteOzoneTemplate:name];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Template deleted.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Remove team member
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/remove-team-member" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSString *did = request.jsonBody[@"did"] ?: @"";
        NSDictionary *result = [weakSelf.backendClient removeOzoneTeamMember:did];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Member removed.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    [self.httpServer addRoute:@"POST" path:@"/admin/actions/test-connection" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *body = request.jsonBody;
        NSString *service = [body[@"service"] isKindOfClass:[NSString class]] ? body[@"service"] : @"";
        NSString *urlString = [body[@"url"] isKindOfClass:[NSString class]] ? body[@"url"] : @"";
        NSString *token = [body[@"token"] isKindOfClass:[NSString class]] ? body[@"token"] : nil;
        NSURL *url = [NSURL URLWithString:urlString ?: @""];
        if (service.length == 0 || url.scheme.length == 0 || url.host.length == 0) {
            response.statusCode = 400;
            [response setJsonBody:@{@"name": service ?: @"", @"status": @"error", @"error": @"Valid service and URL are required"}];
            return;
        }
        NSDictionary *result = [weakSelf.backendClient testConnectionForService:service baseURL:url adminToken:token];
        response.statusCode = 200;
        [response setJsonBody:result ?: @{}];
    }];

    // Ozone: Add team member
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/add-ozone-team-member" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *member = request.jsonBody[@"member"];
        NSDictionary *result = [weakSelf.backendClient addOzoneTeamMember:member ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Team member added.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Create/update set
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/upsert-ozone-set" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *setSpec = request.jsonBody[@"setSpec"];
        NSDictionary *result = [weakSelf.backendClient upsertOzoneSet:setSpec ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Set created/updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Create template
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/create-ozone-template" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *template = request.jsonBody[@"template"];
        NSDictionary *result = [weakSelf.backendClient createOzoneTemplate:template ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Template created.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];

    // Ozone: Update config
    [self.httpServer addRoute:@"POST" path:@"/admin/actions/update-ozone-config" handler:^(HttpRequest *request, HttpResponse *response) {
        AUTH_GUARD(weakSelf, request, response);
        NSDictionary *config = request.jsonBody[@"config"];
        NSDictionary *result = [weakSelf.backendClient updateOzoneConfig:config ?: @{}];
        response.statusCode = result[@"error"] ? 400 : 200;
        response.contentType = @"text/html; charset=utf-8";
        NSString *msg = result[@"error"] ? (result[@"message"] ?: result[@"error"]) : @"Config updated.";
        NSString *alertClass = result[@"error"] ? @"alert-destructive" : @"alert-success";
        [response setBodyString:[NSString stringWithFormat:@"<div class=\"alert %@\">%@</div>", alertClass, UIEscaped(msg)]];
    }];
}

@end
