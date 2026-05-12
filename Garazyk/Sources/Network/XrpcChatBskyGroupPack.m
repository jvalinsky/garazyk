// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcChatBskyGroupPack.h"

#import "Debug/GZLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"
#import "AppView/Services/GroupService.h"
#import "AppView/Services/ActorService.h"
#import "Database/PDSDatabase.h"
#import "Admin/PDSAdminAuth.h"

@implementation XrpcChatBskyGroupPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(JWTMinter *)jwtMinter
              adminController:(id<PDSAdminController>)adminController {

    GroupService *groupService = [[GroupService alloc] initWithDatabase:appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];

    // chat.bsky.group.createGroup - Create new group
    [dispatcher registerMethod:@"chat.bsky.group.createGroup"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *name = body[@"name"];
        NSString *description = body[@"description"];
        NSString *privacy = body[@"privacy"] ?: @"private";
        NSString *joinability = body[@"joinability"] ?: @"invite_only";

        if (![name isKindOfClass:[NSString class]] || name.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"name is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *group = [groupService createGroupWithName:name
                                                     description:description
                                                        creator:actorDID
                                                        privacy:privacy
                                                    joinability:joinability
                                                          error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"group": group ?: @{}}];
    }];

    // chat.bsky.group.deleteGroup - Delete group (Admin only)
    [dispatcher registerMethod:@"chat.bsky.group.deleteGroup"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        if (![[PDSAdminAuth sharedAuth] isAdminDid:actorDID]) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Admin privileges required"];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];

        if (!groupUri) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }

        NSError *error = nil;
        if (![groupService deleteGroup:groupUri error:&error]) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.editGroup - Edit group metadata
    [dispatcher registerMethod:@"chat.bsky.group.editGroup"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];
        NSString *newName = body[@"name"];
        NSString *newDescription = body[@"description"];
        NSString *newPrivacy = body[@"privacy"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }

        // Check permission: user must be admin
        NSError *permError = nil;
        BOOL isAdmin = [groupService isUserAdmin:actorDID inGroup:groupUri error:&permError];
        if (!isAdmin) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Only group admins can edit group"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService editGroup:groupUri
                                      newName:newName
                                newDescription:newDescription
                                    newPrivacy:newPrivacy
                                         error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to edit group"];
            return;
        }

        NSDictionary *group = [groupService getGroupPublicInfo:groupUri error:nil];
        response.statusCode = 200;
        [response setJsonBody:@{@"group": group ?: @{}}];
    }];

    // chat.bsky.group.getGroupPublicInfo - Get group information
    [dispatcher registerMethod:@"chat.bsky.group.getGroupPublicInfo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *groupUri = [request queryParamForKey:@"groupUri"];
        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri parameter is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *group = [groupService getGroupPublicInfo:groupUri error:&error];
        if (error) {
            if (error.code == 404) {
                [XrpcErrorHelper setValidationError:response message:@"Group not found"];
            } else {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            }
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"group": group ?: @{}}];
    }];

    // chat.bsky.group.addMembers - Add members to group
    [dispatcher registerMethod:@"chat.bsky.group.addMembers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];
        NSArray *memberDids = body[@"members"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }
        if (![memberDids isKindOfClass:[NSArray class]] || memberDids.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"members must be an array with at least 1 DID"];
            return;
        }

        // Check permission: user must be moderator or admin
        NSError *permError = nil;
        BOOL isAdmin = [groupService isUserAdmin:actorDID inGroup:groupUri error:&permError];
        if (!isAdmin) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Only group admins/moderators can add members"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService addMembersToGroup:groupUri
                                               members:memberDids
                                             invitedBy:actorDID
                                                error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to add members"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.removeMembers - Remove members from group
    [dispatcher registerMethod:@"chat.bsky.group.removeMembers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];
        NSArray *memberDids = body[@"members"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }
        if (![memberDids isKindOfClass:[NSArray class]] || memberDids.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"members must be an array with at least 1 DID"];
            return;
        }

        // Check permission: user must be admin
        NSError *permError = nil;
        BOOL isAdmin = [groupService isUserAdmin:actorDID inGroup:groupUri error:&permError];
        if (!isAdmin) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Only group admins can remove members"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService removeMembersFromGroup:groupUri
                                                    members:memberDids
                                                      error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to remove members"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.listMembers - List group members
    [dispatcher registerMethod:@"chat.bsky.group.listMembers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *groupUri = [request queryParamForKey:@"groupUri"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri parameter is required"];
            return;
        }

        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSArray *members = [groupService listGroupMembers:groupUri limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"members": members ?: @[]}];
    }];

    // chat.bsky.group.listGroups - List all groups (Admin only)
    [dispatcher registerMethod:@"chat.bsky.group.listGroups"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        if (![[PDSAdminAuth sharedAuth] isAdminDid:actorDID]) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Admin privileges required"];
            return;
        }

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *query = [request queryParamForKey:@"q"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;

        NSError *error = nil;
        NSArray *groups = [groupService listAllGroupsWithLimit:limit cursor:cursor query:query error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"groups": groups ?: @[]}];
    }];

    // chat.bsky.group.listInviteLinks - List all invite links (Admin only)
    [dispatcher registerMethod:@"chat.bsky.group.listInviteLinks"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        if (![[PDSAdminAuth sharedAuth] isAdminDid:actorDID]) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Admin privileges required"];
            return;
        }

        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *query = [request queryParamForKey:@"q"];
        NSInteger limit = limitStr ? [limitStr integerValue] : 50;

        NSError *error = nil;
        NSArray *links = [groupService listAllInviteLinksWithLimit:limit cursor:cursor query:query error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"links": links ?: @[]}];
    }];

    // chat.bsky.group.createJoinLink - Create invite link
    [dispatcher registerMethod:@"chat.bsky.group.createJoinLink"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];
        NSString *expiresAt = body[@"expiresAt"];
        NSNumber *maxUses = body[@"maxUses"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }

        // Check permission: user must be admin
        NSError *permError = nil;
        BOOL isAdmin = [groupService isUserAdmin:actorDID inGroup:groupUri error:&permError];
        if (!isAdmin) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Only group admins can create invite links"];
            return;
        }

        NSError *error = nil;
        NSString *linkId = [groupService createInviteLinkForGroup:groupUri
                                                        createdBy:actorDID
                                                         expiresAt:expiresAt
                                                          maxUses:maxUses
                                                            error:&error];
        if (error || !linkId) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to create invite link"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"linkId": linkId}];
    }];

    // chat.bsky.group.editJoinLink - Edit invite link
    [dispatcher registerMethod:@"chat.bsky.group.editJoinLink"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *linkId = body[@"linkId"];
        NSNumber *enabled = body[@"enabled"];
        NSString *expiresAt = body[@"expiresAt"];
        NSNumber *maxUses = body[@"maxUses"];

        if (![linkId isKindOfClass:[NSString class]] || linkId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"linkId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService editInviteLink:linkId
                                             enabled:enabled
                                            expiresAt:expiresAt
                                             maxUses:maxUses
                                               error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to edit invite link"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.disableJoinLink - Disable invite link
    [dispatcher registerMethod:@"chat.bsky.group.disableJoinLink"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *linkId = body[@"linkId"];

        if (![linkId isKindOfClass:[NSString class]] || linkId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"linkId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService disableInviteLink:linkId error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to disable invite link"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.requestJoin - Request to join group
    [dispatcher registerMethod:@"chat.bsky.group.requestJoin"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }

        NSError *error = nil;
        NSString *requestId = [groupService requestJoinGroup:groupUri
                                                requesterDid:actorDID
                                                      error:&error];
        if (error || !requestId) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to request join"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"requestId": requestId}];
    }];

    // chat.bsky.group.approveJoinRequest - Approve join request
    [dispatcher registerMethod:@"chat.bsky.group.approveJoinRequest"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *requestId = body[@"requestId"];

        if (![requestId isKindOfClass:[NSString class]] || requestId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"requestId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService approveJoinRequest:requestId
                                          approvingDid:actorDID
                                                error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to approve join request"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.rejectJoinRequest - Reject join request
    [dispatcher registerMethod:@"chat.bsky.group.rejectJoinRequest"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *requestId = body[@"requestId"];

        if (![requestId isKindOfClass:[NSString class]] || requestId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"requestId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService rejectJoinRequest:requestId
                                         rejectingDid:actorDID
                                               error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to reject join request"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.listJoinRequests - List pending join requests
    [dispatcher registerMethod:@"chat.bsky.group.listJoinRequests"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSString *groupUri = [request queryParamForKey:@"groupUri"];
        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri parameter is required"];
            return;
        }

        // Check permission: user must be admin
        NSError *permError = nil;
        BOOL isAdmin = [groupService isUserAdmin:actorDID inGroup:groupUri error:&permError];
        if (!isAdmin) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Only group admins can list join requests"];
            return;
        }

        NSError *error = nil;
        NSArray *requests = [groupService listJoinRequestsForGroup:groupUri error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"requests": requests ?: @[]}];
    }];

    // chat.bsky.group.leaveGroup - Leave a group
    [dispatcher registerMethod:@"chat.bsky.group.leaveGroup"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService leaveGroup:groupUri memberDid:actorDID error:&error];
        if (error) {
            if (error.code == 403) {
                [XrpcErrorHelper setAuthenticationError:response message:error.localizedDescription];
            } else {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            }
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.sendMessage - Send message to group
    [dispatcher registerMethod:@"chat.bsky.group.sendMessage"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *groupUri = body[@"groupUri"];
        NSString *text = body[@"text"];
        NSString *embed = body[@"embed"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri is required"];
            return;
        }
        if (![text isKindOfClass:[NSString class]] || text.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"text is required"];
            return;
        }

        NSError *error = nil;
        NSString *messageId = [groupService sendMessageToGroup:groupUri
                                                     senderDid:actorDID
                                                         text:text
                                                        embed:embed
                                                        error:&error];
        if (error) {
            if (error.code == 403) {
                [XrpcErrorHelper setAuthenticationError:response message:error.localizedDescription];
            } else {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            }
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"messageId": messageId}];
    }];

    // chat.bsky.group.getMessages - Get messages from group
    [dispatcher registerMethod:@"chat.bsky.group.getMessages"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *groupUri = [request queryParamForKey:@"groupUri"];
        NSString *limitStr = [request queryParamForKey:@"limit"];
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (![groupUri isKindOfClass:[NSString class]] || groupUri.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"groupUri parameter is required"];
            return;
        }

        NSInteger limit = limitStr ? [limitStr integerValue] : 50;
        if (limit <= 0) limit = 50;
        if (limit > 100) limit = 100;

        NSError *error = nil;
        NSArray *messages = [groupService getMessagesForGroup:groupUri limit:limit cursor:cursor error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"messages": messages ?: @[]}];
    }];

    // chat.bsky.group.addReaction - Add reaction to group message
    [dispatcher registerMethod:@"chat.bsky.group.addReaction"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *messageId = body[@"messageId"];
        NSString *emoji = body[@"emoji"];

        if (![messageId isKindOfClass:[NSString class]] || messageId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"messageId is required"];
            return;
        }
        if (![emoji isKindOfClass:[NSString class]] || emoji.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"emoji is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService addReactionToGroupMessage:messageId
                                                     actorDid:actorDID
                                                       emoji:emoji
                                                       error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to add reaction"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.removeReaction - Remove reaction from group message
    [dispatcher registerMethod:@"chat.bsky.group.removeReaction"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *messageId = body[@"messageId"];
        NSString *emoji = body[@"emoji"];

        if (![messageId isKindOfClass:[NSString class]] || messageId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"messageId is required"];
            return;
        }
        if (![emoji isKindOfClass:[NSString class]] || emoji.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"emoji is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService removeReactionFromGroupMessage:messageId
                                                          actorDid:actorDID
                                                            emoji:emoji
                                                            error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to remove reaction"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.deleteMessageForSelf - Delete message for self
    [dispatcher registerMethod:@"chat.bsky.group.deleteMessageForSelf"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *messageId = body[@"messageId"];

        if (![messageId isKindOfClass:[NSString class]] || messageId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"messageId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [groupService deleteGroupMessageForSelf:messageId memberDid:actorDID error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to delete message"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"success": @YES}];
    }];

    // chat.bsky.group.enableJoinLink - Re-enable a disabled join link
    [dispatcher registerMethod:@"chat.bsky.group.enableJoinLink"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *linkId = body[@"linkId"];
        if (!linkId) {
            [XrpcErrorHelper setValidationError:response message:@"linkId is required"];
            return;
        }

        // Would re-enable join link
        response.statusCode = 200;
        [response setJsonBody:@{@"link": @{@"id": linkId, @"enabled": @YES}}];
    }];
}

@end
