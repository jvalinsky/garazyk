// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcToolsOzonePack.h"

#import "Debug/GZLogger.h"
#import "Admin/PDSAdminAuth.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Ozone/Services/ModerationService.h"
#import "Database/PDSDatabase.h"

@implementation XrpcToolsOzonePack

+ (NSString *)routePackIdentifier {
  return @"tools.ozone";
}

static NSString *ExtractAdminDid(HttpRequest *request,
                                 HttpResponse *response,
                                 id<XrpcRoutePackServices> services) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader services:services request:request response:response];
    if (!adminDid) return nil;

    if (![[PDSAdminAuth sharedAuth] isAdminDid:adminDid]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{
            @"error": @"Forbidden",
            @"message": @"Admin privileges required"
        }];
        return nil;
    }
    return adminDid;
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {

    ModerationService *moderationService = [[ModerationService alloc] initWithDatabase:services.appViewDatabase];

#pragma mark - Moderation Core Endpoints (15)

    // tools.ozone.moderation.emitEvent - Emit moderation event
    [dispatcher registerMethod:@"tools.ozone.moderation.emitEvent"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSDictionary *event = body[@"event"];
        if (!event) {
            [XrpcErrorHelper setValidationError:response message:@"event is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [moderationService emitModerationEvent:event createdBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"event": result ?: @{}}];
    }];

    // tools.ozone.moderation.queryStatuses - Query moderation statuses
    [dispatcher registerMethod:@"tools.ozone.moderation.queryStatuses"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSDictionary *result = [moderationService queryModerationStatuses:@{} limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:result ?: @{}];
    }];

    // tools.ozone.moderation.queryEvents - Query moderation events
    [dispatcher registerMethod:@"tools.ozone.moderation.queryEvents"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;

        NSError *error = nil;
        NSDictionary *result = [moderationService queryModerationEvents:@{} limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:result ?: @{}];
    }];

    // tools.ozone.moderation.getEvent - Get moderation event
    [dispatcher registerMethod:@"tools.ozone.moderation.getEvent"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *eventId = [request queryParamForKey:@"id"];
        if (!eventId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *event = [moderationService getModerationEvent:eventId error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"event": event ?: @{}}];
    }];

    // tools.ozone.moderation.getRecord - Get record
    [dispatcher registerMethod:@"tools.ozone.moderation.getRecord"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *uri = [request queryParamForKey:@"uri"];
        if (!uri) {
            [XrpcErrorHelper setValidationError:response message:@"uri is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *record = [moderationService getModerationRecord:uri error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"record": record ?: @{}}];
    }];

    // tools.ozone.moderation.getRecords - Get multiple records
    [dispatcher registerMethod:@"tools.ozone.moderation.getRecords"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSArray *uris = body[@"uris"];
        if (!uris || uris.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"uris is required"];
            return;
        }

        NSError *error = nil;
        NSArray *records = [moderationService getModerationRecords:uris error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"records": records ?: @[]}];
    }];

    // tools.ozone.moderation.getRepo - Get repository
    [dispatcher registerMethod:@"tools.ozone.moderation.getRepo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *repo = [moderationService getModerationRepo:did error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"repo": repo ?: @{}}];
    }];

    // tools.ozone.moderation.getRepos - Get multiple repositories
    [dispatcher registerMethod:@"tools.ozone.moderation.getRepos"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSArray *dids = body[@"dids"];
        if (!dids || dids.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"dids is required"];
            return;
        }

        NSError *error = nil;
        NSArray *repos = [moderationService getModerationRepos:dids error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"repos": repos ?: @[]}];
    }];

    // tools.ozone.moderation.searchRepos - Search repositories
    [dispatcher registerMethod:@"tools.ozone.moderation.searchRepos"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;

        NSError *error = nil;
        NSDictionary *result = [moderationService searchModerationRepos:@{} limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:result ?: @{}];
    }];

    // tools.ozone.moderation.getSubjectStatus - Get subject status
    [dispatcher registerMethod:@"tools.ozone.moderation.getSubjectStatus"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *subject = [request queryParamForKey:@"did"];
        if (!subject) {
            subject = [request queryParamForKey:@"uri"];
        }
        if (!subject) {
            [XrpcErrorHelper setValidationError:response message:@"did or uri is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *status = [moderationService getSubjectStatus:subject error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"status": status ?: @{}}];
    }];

    // tools.ozone.moderation.getReporterStats - Get reporter statistics
    [dispatcher registerMethod:@"tools.ozone.moderation.getReporterStats"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *stats = [moderationService getReporterStats:did error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"stats": stats ?: @{}}];
    }];

    // tools.ozone.moderation.getAccountTimeline - Get account event timeline
    [dispatcher registerMethod:@"tools.ozone.moderation.getAccountTimeline"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *did = [request queryParamForKey:@"did"];
        if (!did) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;

        NSError *error = nil;
        NSDictionary *timeline = [moderationService getAccountTimeline:did limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:timeline ?: @{}];
    }];

    // tools.ozone.moderation.scheduleAction - Schedule moderation action
    [dispatcher registerMethod:@"tools.ozone.moderation.scheduleAction"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSDictionary *action = body[@"action"];
        NSArray *subjects = body[@"subjects"];
        if (!action || !subjects) {
            [XrpcErrorHelper setValidationError:response message:@"action and subjects are required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *results = [moderationService scheduleAction:body createdBy:adminDid error:&error];
        if (error || !results) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:results];
    }];

    // tools.ozone.moderation.listScheduledActions - List scheduled actions
    [dispatcher registerMethod:@"tools.ozone.moderation.listScheduledActions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSError *error = nil;
        NSArray *actions = [moderationService listScheduledActions:@{} error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"actions": actions ?: @[]}];
    }];

    // tools.ozone.moderation.cancelScheduledAction - Cancel scheduled action
    [dispatcher registerMethod:@"tools.ozone.moderation.cancelScheduledAction"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *actionId = body[@"id"];
        if (!actionId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService cancelScheduledAction:actionId cancelledBy:adminDid error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to cancel action"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.moderation.cancelScheduledActions - Cancel all scheduled actions for subjects
    [dispatcher registerMethod:@"tools.ozone.moderation.cancelScheduledActions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSArray *subjects = body[@"subjects"];
        NSString *comment = body[@"comment"];
        if (!subjects || subjects.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"subjects is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *results = [moderationService cancelScheduledActions:subjects
                                                                  comment:comment
                                                              cancelledBy:adminDid
                                                                    error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:results ?: @{@"succeeded": @[], @"failed": @[]}];
    }];

    // tools.ozone.moderation.getSubjects - Get subject details
    [dispatcher registerMethod:@"tools.ozone.moderation.getSubjects"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *subjectsParam = [request queryParamForKey:@"subjects"];
        NSArray *subjects = nil;
        if (subjectsParam) {
            subjects = [subjectsParam componentsSeparatedByString:@","];
        }
        if (!subjects || subjects.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"subjects is required"];
            return;
        }

        NSError *error = nil;
        NSArray *subjectViews = [moderationService getSubjects:subjects error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"subjects": subjectViews ?: @[]}];
    }];

#pragma mark - Team Management (4)

    // tools.ozone.team.addMember
    [dispatcher registerMethod:@"tools.ozone.team.addMember"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        if (!body[@"email"]) {
            [XrpcErrorHelper setValidationError:response message:@"email is required"];
            return;
        }

        NSError *error = nil;
        NSString *memberId = [moderationService addTeamMember:body createdBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"id": memberId}];
    }];

    // tools.ozone.team.updateMember
    [dispatcher registerMethod:@"tools.ozone.team.updateMember"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        if (!body[@"email"] || !body[@"role"]) {
            [XrpcErrorHelper setValidationError:response message:@"email and role are required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService updateTeamMember:body[@"email"]
                                                   newRole:body[@"role"]
                                                 updatedBy:adminDid
                                                     error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.team.deleteMember
    [dispatcher registerMethod:@"tools.ozone.team.deleteMember"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *email = body[@"email"];
        if (!email) {
            [XrpcErrorHelper setValidationError:response message:@"email is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService removeTeamMember:email removedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.team.listMembers
    [dispatcher registerMethod:@"tools.ozone.team.listMembers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSError *error = nil;
        NSArray *members = [moderationService listTeamMembers:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"members": members ?: @[]}];
    }];

#pragma mark - Set Management (6)

    // tools.ozone.set.upsertSet (replaces create/update)
    [dispatcher registerMethod:@"tools.ozone.set.upsertSet"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *name = body[@"name"];
        if (!name) {
            [XrpcErrorHelper setValidationError:response message:@"name is required"];
            return;
        }

        NSError *error = nil;
        NSString *setId = body[@"id"]; // Optional: if provided, update existing set
        if (setId) {
            // Update existing set
            BOOL success = [moderationService updateSet:setId
                                               newName:name
                                             newValues:body[@"values"]
                                             updatedBy:adminDid
                                                 error:&error];
            if (!success) {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                return;
            }
            response.statusCode = 200;
            [response setJsonBody:@{@"id": setId}];
        } else {
            // Create new set
            NSString *newSetId = [moderationService createSet:body createdBy:adminDid error:&error];
            if (error) {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
                return;
            }
            response.statusCode = 200;
            [response setJsonBody:@{@"id": newSetId}];
        }
    }];

    // tools.ozone.set.deleteSet
    [dispatcher registerMethod:@"tools.ozone.set.deleteSet"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *setId = body[@"id"];
        if (!setId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService deleteSet:setId deletedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // tools.ozone.set.getValues
    [dispatcher registerMethod:@"tools.ozone.set.getValues"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *setId = [request queryParamForKey:@"id"];
        if (!setId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSInteger limit = 100;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0) {
            limit = [limitParam integerValue];
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSDictionary *result = [moderationService getSetValues:setId limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:result ?: @{ @"values": @[] }];
    }];

    // tools.ozone.set.querySets
    [dispatcher registerMethod:@"tools.ozone.set.querySets"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSInteger limit = 50;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0) {
            limit = [limitParam integerValue];
        }
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *namePrefix = [request queryParamForKey:@"namePrefix"];

        NSError *error = nil;
        NSDictionary *result = [moderationService querySets:limit cursor:cursor namePrefix:namePrefix error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:result ?: @{ @"sets": @[] }];
    }];

    // tools.ozone.set.addValues
    [dispatcher registerMethod:@"tools.ozone.set.addValues"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *setId = body[@"id"];
        NSArray *values = body[@"values"];
        if (!setId || !values) {
            [XrpcErrorHelper setValidationError:response message:@"id and values are required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService addSetValues:setId values:values addedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // tools.ozone.set.deleteValues
    [dispatcher registerMethod:@"tools.ozone.set.deleteValues"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *setId = body[@"id"];
        NSArray *values = body[@"values"];
        if (!setId || !values) {
            [XrpcErrorHelper setValidationError:response message:@"id and values are required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService deleteSetValues:setId values:values deletedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

#pragma mark - Communication Templates (4)

    // tools.ozone.communication.createTemplate
    [dispatcher registerMethod:@"tools.ozone.communication.createTemplate"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        if (!body[@"name"] || !body[@"contentMarkdown"]) {
            [XrpcErrorHelper setValidationError:response message:@"name and contentMarkdown are required"];
            return;
        }

        NSMutableDictionary *templateInput = [body mutableCopy];
        templateInput[@"text"] = body[@"contentMarkdown"];

        NSError *error = nil;
        NSString *templateId = [moderationService createCommunicationTemplate:templateInput createdBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"id": templateId}];
    }];

    // tools.ozone.communication.updateTemplate
    [dispatcher registerMethod:@"tools.ozone.communication.updateTemplate"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *templateId = body[@"id"];
        if (!templateId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService updateCommunicationTemplate:templateId
                                                              newName:body[@"name"]
                                                             newText:body[@"contentMarkdown"]
                                                          updatedBy:adminDid
                                                                error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.communication.deleteTemplate
    [dispatcher registerMethod:@"tools.ozone.communication.deleteTemplate"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *templateId = body[@"id"];
        if (!templateId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService deleteCommunicationTemplate:templateId deletedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.communication.listTemplates
    [dispatcher registerMethod:@"tools.ozone.communication.listTemplates"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSError *error = nil;
        NSArray *templates = [moderationService listCommunicationTemplates:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"templates": templates ?: @[]}];
    }];

#pragma mark - Verification (3)

    // tools.ozone.verification.grantVerifications
    [dispatcher registerMethod:@"tools.ozone.verification.grantVerifications"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *did = body[@"did"];
        if (!did) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSError *error = nil;
        NSString *verificationId = [moderationService grantVerification:did grantedBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"id": verificationId}];
    }];

    // tools.ozone.verification.revokeVerifications
    [dispatcher registerMethod:@"tools.ozone.verification.revokeVerifications"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *did = body[@"did"];
        if (!did) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService revokeVerification:did revokedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.verification.listVerifications
    [dispatcher registerMethod:@"tools.ozone.verification.listVerifications"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSError *error = nil;
        NSArray *verifications = [moderationService listVerifications:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"verifications": verifications ?: @[]}];
    }];

#pragma mark - Safelinks (5)

    // tools.ozone.safelink.queryRules
    [dispatcher registerMethod:@"tools.ozone.safelink.queryRules"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSArray *rules = [moderationService listSafelinks:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"rules": rules ?: @[], @"cursor": cursor ?: @""}];
    }];

    // tools.ozone.safelink.queryEvents
    [dispatcher registerMethod:@"tools.ozone.safelink.queryEvents"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        response.statusCode = 200;
        [response setJsonBody:@{@"events": @[], @"cursor": cursor ?: @""}];
    }];

    // tools.ozone.safelink.addRule
    [dispatcher registerMethod:@"tools.ozone.safelink.addRule"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *url = body[@"url"];
        NSString *action = body[@"action"];

        if (!url || url.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"url is required"];
            return;
        }

        if (!action || action.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"action is required"];
            return;
        }

        NSError *error = nil;
        NSString *ruleId = [moderationService createSafelink:body createdBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"id": ruleId ?: @"", @"url": url, @"action": action}];
    }];

    // tools.ozone.safelink.updateRule
    [dispatcher registerMethod:@"tools.ozone.safelink.updateRule"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *ruleId = body[@"id"];
        NSString *url = body[@"url"];
        NSString *action = body[@"action"];

        if (!ruleId || ruleId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService updateSafelink:ruleId newUrl:url newAction:action updatedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.safelink.removeRule
    [dispatcher registerMethod:@"tools.ozone.safelink.removeRule"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *ruleId = body[@"id"];

        if (!ruleId || ruleId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService deleteSafelink:ruleId deletedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

#pragma mark - Settings Options (3)

    // tools.ozone.setting.upsertOption
    [dispatcher registerMethod:@"tools.ozone.setting.upsertOption"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *key = body[@"key"];
        NSString *value = body[@"value"];
        NSString *scope = body[@"scope"] ?: @"global";

        if (!key || key.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"key is required"];
            return;
        }

        if (!value) {
            [XrpcErrorHelper setValidationError:response message:@"value is required"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{
            @"key": key,
            @"value": value,
            @"scope": scope
        }];
    }];

    // tools.ozone.setting.listOptions
    [dispatcher registerMethod:@"tools.ozone.setting.listOptions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *scope = [request queryParamForKey:@"scope"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        response.statusCode = 200;
        [response setJsonBody:@{
            @"options": @[],
            @"cursor": cursor ?: @""
        }];
    }];

    // tools.ozone.setting.removeOptions
    [dispatcher registerMethod:@"tools.ozone.setting.removeOptions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSArray *keys = body[@"keys"];

        if (!keys || keys.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"keys array is required"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

#pragma mark - Signatures (3)

    // tools.ozone.signature.findRelatedAccounts
    [dispatcher registerMethod:@"tools.ozone.signature.findRelatedAccounts"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *did = body[@"did"];

        if (!did || did.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSString *limitStr = body[@"limit"];
        NSString *cursor = body[@"cursor"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        response.statusCode = 200;
        [response setJsonBody:@{
            @"accounts": @[],
            @"cursor": cursor ?: @""
        }];
    }];

    // tools.ozone.signature.findCorrelation
    [dispatcher registerMethod:@"tools.ozone.signature.findCorrelation"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *did1 = body[@"did1"];
        NSString *did2 = body[@"did2"];

        if (!did1 || did1.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"did1 is required"];
            return;
        }

        if (!did2 || did2.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"did2 is required"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{
            @"correlation": @"none",
            @"confidence": @0.0,
            @"sharedSignals": @[]
        }];
    }];

    // tools.ozone.signature.searchAccounts
    [dispatcher registerMethod:@"tools.ozone.signature.searchAccounts"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *query = [request queryParamForKey:@"query"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (!query || query.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"query is required"];
            return;
        }

        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        response.statusCode = 200;
        [response setJsonBody:@{
            @"accounts": @[],
            @"cursor": cursor ?: @""
        }];
    }];

#pragma mark - Hosting History (1)

    // tools.ozone.hosting.getAccountHistory
    [dispatcher registerMethod:@"tools.ozone.hosting.getAccountHistory"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSString *did = [request queryParamForKey:@"did"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (!did || did.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }

        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSArray *history = [moderationService getAccountHostingHistory:did limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{
            @"events": history ?: @[],
            @"cursor": cursor ?: @""
        }];
    }];

#pragma mark - Server Settings (2)

    // tools.ozone.server.getConfig
    [dispatcher registerMethod:@"tools.ozone.server.getConfig"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSError *error = nil;
        NSDictionary *config = [moderationService getServerConfig:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:config ?: @{}];
    }];

    // tools.ozone.server.updateConfig
    [dispatcher registerMethod:@"tools.ozone.server.updateConfig"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *adminDid = ExtractAdminDid(request, response, services);
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSError *error = nil;
        BOOL success = [moderationService updateServerSettings:body updatedBy:adminDid error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];
}

@end
