// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIBackendClient+Ozone.h"
#import "AdminUIServer/UIBackendClient_Internal.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/ATProtoSafeHTTPClient.h"

@implementation UIBackendClient (Ozone)

- (NSDictionary *)fetchOzoneStatusesWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.queryStatuses"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_statuses_failed", @"message": error.localizedDescription ?: @"Failed to fetch statuses"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchOzoneEventsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.queryEvents"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_events_failed", @"message": error.localizedDescription ?: @"Failed to fetch events"};
    }
    return response ?: @{};
}

- (NSDictionary *)emitModerationEvent:(NSDictionary *)event {
    if (!event) {
        return @{@"error": @"invalid_params", @"message": @"Event required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.emitEvent"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:event statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"emit_event_failed", @"message": error.localizedDescription ?: @"Failed to emit event"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchSubjectStatusForDID:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.getSubjectStatus"
                              queryItems:@{@"did": did}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"subject_status_failed", @"message": error.localizedDescription ?: @"Failed to fetch subject status"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchModerationReportsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    params[@"types"] = @"tools.ozone.moderation.defs#modEventReport";
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.queryEvents"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"moderation_reports_failed", @"message": error.localizedDescription ?: @"Failed to fetch reports"};
    }
    if (![response[@"reports"] isKindOfClass:[NSArray class]] && [response[@"events"] isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSDictionary *> *reports = [NSMutableArray array];
        for (NSDictionary *event in response[@"events"]) {
            if (![event isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            id subject = event[@"subject"];
            NSString *subjectString = [subject isKindOfClass:[NSString class]] ? subject : [subject description];
            [reports addObject:@{
                @"subject": subjectString ?: @"",
                @"reason": event[@"reportType"] ?: event[@"reason"] ?: event[@"comment"] ?: @"",
                @"reportedBy": event[@"createdBy"] ?: event[@"reportedBy"] ?: @"",
                @"resolvedAt": event[@"resolvedAt"] ?: @""
            }];
        }
        NSMutableDictionary *normalized = [response mutableCopy];
        normalized[@"reports"] = reports;
        return [normalized copy];
    }
    return response ?: @{};
}

- (NSDictionary *)fetchScheduledActionsWithStatuses:(nullable NSArray<NSString *> *)statuses cursor:(nullable NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if (statuses && statuses.count > 0) {
        body[@"statuses"] = statuses;
    }
    if (cursor && cursor.length > 0) {
        body[@"cursor"] = cursor;
    }
    if (limit > 0) {
        body[@"limit"] = @(limit);
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.listScheduledActions"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"scheduled_actions_failed", @"message": error.localizedDescription ?: @"Failed to fetch scheduled actions"};
    }
    return response ?: @{};
}

- (NSDictionary *)scheduleAction:(NSDictionary *)actionSpec {
    if (!actionSpec) {
        return @{@"error": @"invalid_params", @"message": @"Action specification required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.scheduleAction"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:actionSpec statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"schedule_action_failed", @"message": error.localizedDescription ?: @"Failed to schedule action"};
    }
    return response ?: @{};
}

- (NSDictionary *)cancelScheduledActionsForSubjects:(NSArray<NSString *> *)subjects {
    if (!subjects || subjects.count == 0) {
        return @{@"error": @"invalid_params", @"message": @"Subject DIDs required"};
    }
    NSDictionary *body = @{@"subjects": subjects};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.moderation.cancelScheduledActions"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"cancel_scheduled_actions_failed", @"message": error.localizedDescription ?: @"Failed to cancel scheduled actions"};
    }
    return response ?: @{};
}

- (NSDictionary *)listOzoneVerifications {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.verification.listVerifications"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"list_verifications_failed", @"message": error.localizedDescription ?: @"Failed to fetch verifications"};
    }
    return response ?: @{};
}

- (NSDictionary *)grantOzoneVerifications:(NSArray<NSDictionary *> *)verifications {
    if (!verifications || verifications.count == 0) {
        return @{@"error": @"invalid_params", @"message": @"Verification records required"};
    }
    NSDictionary *body = @{@"verifications": verifications};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.verification.grantVerifications"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"grant_verifications_failed", @"message": error.localizedDescription ?: @"Failed to grant verifications"};
    }
    return response ?: @{};
}

- (NSDictionary *)revokeOzoneVerifications:(NSArray<NSString *> *)dids {
    if (!dids || dids.count == 0) {
        return @{@"error": @"invalid_params", @"message": @"DIDs required"};
    }
    NSDictionary *body = @{@"dids": dids};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.verification.revokeVerifications"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"revoke_verifications_failed", @"message": error.localizedDescription ?: @"Failed to revoke verifications"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchSafelinkRules {
    NSDictionary *body = @{@"limit": @50};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.safelink.queryRules"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"fetch_safelinks_failed", @"message": error.localizedDescription ?: @"Failed to fetch safelink rules"};
    }
    return response ?: @{@"rules": @[]};
}

- (NSDictionary *)fetchOzoneSettings {
    return [self listOzoneSettings];
}

- (NSDictionary *)addSafelinkRule:(NSDictionary *)rule {
    if (!rule) {
        return @{@"error": @"invalid_params", @"message": @"Rule specification required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.safelink.addRule"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:rule statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"add_safelink_failed", @"message": error.localizedDescription ?: @"Failed to add safelink rule"};
    }
    return response ?: @{};
}

- (NSDictionary *)removeSafelinkRule:(NSString *)url pattern:(NSString *)pattern {
    if (!url || url.length == 0 || !pattern || pattern.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"URL and pattern required"};
    }
    NSDictionary *body = @{@"url": url, @"pattern": pattern};
    NSURL *requestUrl = [self URLByAppendingPath:@"/xrpc/tools.ozone.safelink.removeRule"
                                     queryItems:nil
                                        baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:requestUrl method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"remove_safelink_failed", @"message": error.localizedDescription ?: @"Failed to remove safelink rule"};
    }
    return response ?: @{};
}

- (NSDictionary *)listOzoneSettings {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.setting.listOptions"
                              queryItems:@{@"limit": @"50", @"scope": @"instance"}
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"list_settings_failed", @"message": error.localizedDescription ?: @"Failed to fetch settings"};
    }
    return response ?: @{@"options": @[]};
}

- (NSDictionary *)upsertOzoneSetting:(NSDictionary *)option {
    if (!option) {
        return @{@"error": @"invalid_params", @"message": @"Option specification required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.setting.upsertOption"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:option statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"upsert_setting_failed", @"message": error.localizedDescription ?: @"Failed to upsert setting"};
    }
    return response ?: @{};
}

- (NSDictionary *)removeOzoneSettings:(NSArray<NSString *> *)keys {
    if (!keys || keys.count == 0) {
        return @{@"error": @"invalid_params", @"message": @"Setting keys required"};
    }
    NSDictionary *body = @{@"keys": keys};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.setting.removeOptions"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"remove_settings_failed", @"message": error.localizedDescription ?: @"Failed to remove settings"};
    }
    return response ?: @{};
}

- (NSDictionary *)findRelatedAccounts:(NSString *)did {
    if (!did || did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSDictionary *body = @{@"did": did};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.signature.findRelatedAccounts"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"find_related_failed", @"message": error.localizedDescription ?: @"Failed to find related accounts"};
    }
    return response ?: @{@"related": @[]};
}

- (NSDictionary *)findSignatureCorrelation:(NSArray<NSString *> *)dids {
    if (!dids || dids.count == 0) {
        return @{@"error": @"invalid_params", @"message": @"DIDs required"};
    }
    NSDictionary *body = @{@"dids": dids};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.signature.findCorrelation"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"find_correlation_failed", @"message": error.localizedDescription ?: @"Failed to find correlation"};
    }
    return response ?: @{@"correlations": @[]};
}

- (NSDictionary *)searchAccountsBySignature:(NSDictionary *)patterns {
    if (!patterns) {
        return @{@"error": @"invalid_params", @"message": @"Search patterns required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.signature.searchAccounts"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:patterns statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"search_accounts_failed", @"message": error.localizedDescription ?: @"Failed to search accounts"};
    }
    return response ?: @{@"accounts": @[]};
}

- (NSDictionary *)fetchHostingHistoryForDID:(NSString *)did {
    if (!did || did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSDictionary *body = @{@"did": did};
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.hosting.getAccountHistory"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"hosting_history_failed", @"message": error.localizedDescription ?: @"Failed to fetch hosting history"};
    }
    return response ?: @{@"entries": @[]};
}

- (NSDictionary *)fetchOzoneTeamMembers {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.team.listMembers"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"team_members_failed", @"message": error.localizedDescription ?: @"Failed to fetch team members"};
    }
    return response ?: @{};
}

- (NSDictionary *)addOzoneTeamMember:(NSDictionary *)member {
    if (!member) {
        return @{@"error": @"invalid_params", @"message": @"Member info required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.team.addMember"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:member statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"add_member_failed", @"message": error.localizedDescription ?: @"Failed to add team member"};
    }
    return response ?: @{};
}

- (NSDictionary *)removeOzoneTeamMember:(NSString *)did {
    if (did.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"DID required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.team.deleteMember"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"did": did};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"remove_member_failed", @"message": error.localizedDescription ?: @"Failed to remove team member"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchOzoneSetsWithCursor:(NSString *)cursor limit:(NSUInteger)limit {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (cursor.length > 0) params[@"cursor"] = cursor;
    if (limit > 0) params[@"limit"] = [NSString stringWithFormat:@"%lu", (unsigned long)limit];
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.set.querySets"
                              queryItems:params
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_sets_failed", @"message": error.localizedDescription ?: @"Failed to fetch sets"};
    }
    return response ?: @{};
}

- (NSDictionary *)upsertOzoneSet:(NSDictionary *)setSpec {
    if (!setSpec) {
        return @{@"error": @"invalid_params", @"message": @"Set specification required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.set.upsertSet"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:setSpec statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"upsert_set_failed", @"message": error.localizedDescription ?: @"Failed to upsert set"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteOzoneSet:(NSString *)name {
    if (name.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"Set name required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.set.deleteSet"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"name": name};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_set_failed", @"message": error.localizedDescription ?: @"Failed to delete set"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchOzoneTemplates {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.communication.listTemplates"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_templates_failed", @"message": error.localizedDescription ?: @"Failed to fetch templates"};
    }
    return response ?: @{};
}

- (NSDictionary *)createOzoneTemplate:(NSDictionary *)template {
    if (!template) {
        return @{@"error": @"invalid_params", @"message": @"Template required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.communication.createTemplate"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:template statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"create_template_failed", @"message": error.localizedDescription ?: @"Failed to create template"};
    }
    return response ?: @{};
}

- (NSDictionary *)deleteOzoneTemplate:(NSString *)name {
    if (name.length == 0) {
        return @{@"error": @"invalid_params", @"message": @"Template name required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.communication.deleteTemplate"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSDictionary *body = @{@"name": name};
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:body statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"delete_template_failed", @"message": error.localizedDescription ?: @"Failed to delete template"};
    }
    return response ?: @{};
}

- (NSDictionary *)fetchOzoneConfig {
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.server.getConfig"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"GET" body:nil statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"ozone_config_failed", @"message": error.localizedDescription ?: @"Failed to fetch ozone config"};
    }
    return response ?: @{};
}

- (NSDictionary *)updateOzoneConfig:(NSDictionary *)config {
    if (!config) {
        return @{@"error": @"invalid_params", @"message": @"Config required"};
    }
    NSURL *url = [self URLByAppendingPath:@"/xrpc/tools.ozone.server.updateConfig"
                              queryItems:nil
                                 baseURL:self.configuration.pdsBaseURL];
    NSInteger status = 0;
    NSError *error = nil;
    NSDictionary *response = [self performPDSRequestWithURL:url method:@"POST" body:config statusCode:&status error:&error];
    if (status < 200 || status >= 300) {
        return @{@"error": @"update_config_failed", @"message": error.localizedDescription ?: @"Failed to update config"};
    }
    return response ?: @{};
}

@end
