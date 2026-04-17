#import "Network/XrpcToolsOzonePack.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"
#import "AppView/Services/ModerationService.h"
#import "Database/PDSDatabase.h"

@implementation XrpcToolsOzonePack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(JWTMinter *)jwtMinter
              adminController:(id<PDSAdminController>)adminController {

    ModerationService *moderationService = [[ModerationService alloc] initWithDatabase:appViewDatabase];

#pragma mark - Moderation Core Endpoints (15)

    // tools.ozone.moderation.emitEvent - Emit moderation event
    [dispatcher registerMethod:@"tools.ozone.moderation.emitEvent"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSDictionary *action = body[@"action"];
        if (!action) {
            [XrpcErrorHelper setValidationError:response message:@"action is required"];
            return;
        }

        NSError *error = nil;
        NSString *actionId = [moderationService scheduleAction:action createdBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"id": actionId}];
    }];

    // tools.ozone.moderation.listScheduledActions - List scheduled actions
    [dispatcher registerMethod:@"tools.ozone.moderation.listScheduledActions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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

#pragma mark - Team Management (4)

    // tools.ozone.team.addMember
    [dispatcher registerMethod:@"tools.ozone.team.addMember"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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

    // tools.ozone.set.create
    [dispatcher registerMethod:@"tools.ozone.set.create"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        if (!body[@"name"]) {
            [XrpcErrorHelper setValidationError:response message:@"name is required"];
            return;
        }

        NSError *error = nil;
        NSString *setId = [moderationService createSet:body createdBy:adminDid error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"id": setId}];
    }];

    // tools.ozone.set.update
    [dispatcher registerMethod:@"tools.ozone.set.update"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        NSString *setId = body[@"id"];
        if (!setId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [moderationService updateSet:setId
                                           newName:body[@"name"]
                                         newValues:body[@"values"]
                                         updatedBy:adminDid
                                             error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.set.delete
    [dispatcher registerMethod:@"tools.ozone.set.delete"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        [response setJsonBody:@{@"success": @YES}];
    }];

    // tools.ozone.set.get
    [dispatcher registerMethod:@"tools.ozone.set.get"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

        NSString *setId = [request queryParamForKey:@"id"];
        if (!setId) {
            [XrpcErrorHelper setValidationError:response message:@"id is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *set = [moderationService getSet:setId error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"set": set ?: @{}}];
    }];

    // tools.ozone.set.list
    [dispatcher registerMethod:@"tools.ozone.set.list"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

        NSError *error = nil;
        NSArray *sets = [moderationService listSets:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"sets": sets ?: @[]}];
    }];

    // tools.ozone.set.addValues
    [dispatcher registerMethod:@"tools.ozone.set.addValues"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        [response setJsonBody:@{@"success": @YES}];
    }];

#pragma mark - Communication Templates (4)

    // tools.ozone.communication.createTemplate
    [dispatcher registerMethod:@"tools.ozone.communication.createTemplate"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!adminDid) return;

        NSDictionary *body = request.jsonBody;
        if (!body[@"name"] || !body[@"contentMarkdown"]) {
            [XrpcErrorHelper setValidationError:response message:@"name and contentMarkdown are required"];
            return;
        }

        NSError *error = nil;
        NSString *templateId = [moderationService createCommunicationTemplate:body createdBy:adminDid error:&error];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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

    // tools.ozone.verification.grantVerification
    [dispatcher registerMethod:@"tools.ozone.verification.grantVerification"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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

    // tools.ozone.verification.revokeVerification
    [dispatcher registerMethod:@"tools.ozone.verification.revokeVerification"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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

#pragma mark - Server Settings (2)

    // tools.ozone.server.getConfig
    [dispatcher registerMethod:@"tools.ozone.server.getConfig"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader jwtMinter:jwtMinter
                                 adminController:adminController request:request response:response];
        if (!authHeader) return;

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
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *adminDid = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
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
