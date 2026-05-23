// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcChatBskyConvoPack.m

 @abstract XRPC route pack for chat.bsky.convo.* endpoints.
 Implements conversation management, messaging, reactions, read state,
 muting, locking, and event log.
 */

#import "Network/XrpcChatBskyConvoPack.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Chat/Server/ChatAuthManager.h"
#import "Chat/Server/Services/ChatService.h"
#import "Chat/Server/Config/ChatSchemaManager.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Services/PDS/PDSRecordService.h"
#import "Core/DID.h"
#import "Debug/GZLogger.h"

@implementation XrpcChatBskyConvoPack

+ (NSString *)routePackIdentifier {
  return @"chat.bsky.convo";
}

static NSString *XrpcChatActorDIDForRequest(HttpRequest *request,
                                            HttpResponse *response,
                                            id<XrpcRoutePackServices> services) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
        [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
        return nil;
    }

    if (!services.jwtMinter && !services.adminController) {
        // Extract method NSID from request path for lxm validation
        NSString *methodNSID = request.pathParameters[@"method"] ?: @"";
        return [[ChatAuthManager sharedManager] authenticateRequest:request
                                                           response:response
                                                      expectedMethod:methodNSID.length > 0 ? methodNSID : nil];
    }

    return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                         jwtMinter:services.jwtMinter
                                   adminController:services.adminController
                                           request:request
                                          response:response];
}

static BOOL XrpcChatConversationIncludesActor(NSDictionary *convo, NSString *actorDID) {
    if (actorDID.length == 0) return NO;

    NSArray *members = [convo[@"members"] isKindOfClass:[NSArray class]] ? convo[@"members"] : @[];
    for (id member in members) {
        NSString *memberDID = nil;
        if ([member isKindOfClass:[NSString class]]) {
            memberDID = member;
        } else if ([member isKindOfClass:[NSDictionary class]]) {
            memberDID = ((NSDictionary *)member)[@"did"];
        }
        if ([memberDID isEqualToString:actorDID]) return YES;
    }
    return NO;
}

/*! Fetch the allowIncoming preference for a DID from the PDS repo.
    Returns "all" (default), "none", or "following".
    On any error, returns "all" (fail-open for availability). */
static NSString *XrpcChatAllowIncomingForDID(NSString *targetDid) {
    NSString *pdsUrl = [ChatAuthManager sharedManager].pdsUrl;
    if (pdsUrl.length == 0) {
        pdsUrl = @"http://127.0.0.1:2583";
    }

    NSString *encodedDid =
        [targetDid stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *getUrl = [NSString stringWithFormat:
        @"%@/xrpc/com.atproto.repo.getRecord?collection=chat.bsky.actor.declaration&rkey=self&repo=%@",
        pdsUrl, encodedDid];

    NSURL *url = [NSURL URLWithString:getUrl];
    if (!url) {
        GZ_LOG_ERROR(@"allowIncoming: invalid URL for DID %@", targetDid);
        return @"all";
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                            timeoutInterval:5.0];
    [request setHTTPMethod:@"GET"];

    ATProtoSafeHTTPClientOptions *options = [ATProtoSafeHTTPClientOptions defaultOptions];
    options.allowHTTP = YES;
    options.allowPrivateHosts = YES;

    NSHTTPURLResponse *urlResponse = nil;
    NSError *error = nil;
    NSData *data = [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:request
                                                                        options:options
                                                                       response:&urlResponse
                                                                          error:&error];

    if (error) {
        GZ_LOG_ERROR(@"allowIncoming: network error for %@ at %@: %@",
                      targetDid, pdsUrl, error.localizedDescription);
    }

    if (!data || urlResponse.statusCode == 404) {
        if (urlResponse.statusCode == 404) {
            NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(no body)";
            GZ_LOG_INFO(@"allowIncoming: no declaration found for %@ (404). Body: %@", targetDid, body);
        }
        return @"all";
    }

    if (urlResponse.statusCode < 200 || urlResponse.statusCode >= 300) {
        NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(no body)";
        GZ_LOG_ERROR(@"allowIncoming: PDS returned %ld for %@ at %@: %@",
                      (long)urlResponse.statusCode, targetDid, pdsUrl, body);
        return @"all";
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        GZ_LOG_WARN(@"allowIncoming: invalid JSON from PDS for %@", targetDid);
        return @"all";
    }

    NSDictionary *value = ((NSDictionary *)json)[@"value"];
    if (![value isKindOfClass:[NSDictionary class]]) {
        GZ_LOG_INFO(@"allowIncoming: no 'value' in declaration for %@, defaulting to 'all'", targetDid);
        return @"all";
    }

    NSString *allowIncoming = value[@"allowIncoming"];
    GZ_LOG_INFO(@"allowIncoming: for %@ is '%@'", targetDid, allowIncoming);
    if ([allowIncoming isEqualToString:@"none"] ||
        [allowIncoming isEqualToString:@"following"] ||
        [allowIncoming isEqualToString:@"all"]) {
        return allowIncoming;
    }

    return @"all";
}

static NSString *XrpcChatAllowIncomingForDIDFromRepo(NSString *targetDid,
                                                     PDSRecordService *recordService) {
    if (!recordService || targetDid.length == 0) {
        return XrpcChatAllowIncomingForDID(targetDid);
    }

    NSString *uri = [NSString stringWithFormat:@"at://%@/chat.bsky.actor.declaration/self", targetDid];
    NSError *error = nil;
    NSDictionary *record = [recordService getRecord:uri forDid:targetDid error:&error];
    if (!record) {
        return XrpcChatAllowIncomingForDID(targetDid);
    }

    NSDictionary *value = [record[@"value"] isKindOfClass:[NSDictionary class]] ? record[@"value"] : nil;
    NSString *allowIncoming = [value[@"allowIncoming"] isKindOfClass:[NSString class]] ? value[@"allowIncoming"] : nil;
    if ([allowIncoming isEqualToString:@"none"] ||
        [allowIncoming isEqualToString:@"following"] ||
        [allowIncoming isEqualToString:@"all"]) {
        return allowIncoming;
    }
    return @"all";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    id<PDSQueryDatabase> appViewDatabase = services.appViewDatabase;
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    PDSRecordService *recordService = services.recordService;

    // Ensure chat schema tables exist
    PDSDatabase *db = (PDSDatabase *)appViewDatabase;
    ChatSchemaManager *schemaManager = [ChatSchemaManager sharedManager];
    [db executeParameterizedUpdate:[schemaManager chatSchemaSQL] params:@[] error:nil];

    ChatService *chatService = [[ChatService alloc] initWithDatabase:appViewDatabase];

    // chat.bsky.convo.getConvoForMembers
    [dispatcher registerMethod:@"chat.bsky.convo.getConvoForMembers"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        // getConvoForMembers is a query (GET); members arrive as repeated
        // query parameters. Some clients send ?members=a&members=b, others
        // ?members[]=a&members[]=b. Check both key forms.
        id membersParam = request.queryParams[@"members"] ?: request.queryParams[@"members[]"];
        NSArray *members = nil;
        if ([membersParam isKindOfClass:[NSArray class]]) {
            members = (NSArray *)membersParam;
        } else if ([membersParam isKindOfClass:[NSString class]]) {
            members = @[(NSString *)membersParam];
        }
        if ((!members || members.count == 0) && [request.jsonBody isKindOfClass:[NSDictionary class]]) {
            id bodyMembers = request.jsonBody[@"members"];
            if ([bodyMembers isKindOfClass:[NSArray class]]) {
                members = (NSArray *)bodyMembers;
            } else if ([bodyMembers isKindOfClass:[NSString class]]) {
                members = @[(NSString *)bodyMembers];
            }
        }
        if (!members || members.count < 2) {
            [XrpcErrorHelper setValidationError:response message:@"At least two members required"];
            return;
        }

        // Check allowIncoming for each non-self member
        for (NSString *memberDid in members) {
            if ([memberDid isEqualToString:actorDID]) continue;

            NSString *allowIncoming = XrpcChatAllowIncomingForDIDFromRepo(memberDid, recordService);
            if ([allowIncoming isEqualToString:@"none"]) {
                response.statusCode = 403;
                [response setJsonBody:@{
                    @"error": @"Blocked",
                    @"message": [NSString stringWithFormat:
                        @"Recipient %@ does not allow incoming messages", memberDid]
                }];
                return;
            }
            // "following" check requires graph query — not yet implemented.
            // For now, "following" is treated as "all" (fail-open).
            // TODO: Query PDS graph to check if actorDID follows memberDid.
        }

        NSError *error = nil;
        NSDictionary *convo = [chatService getConversationForMembers:members error:&error];
        if (!convo) {
            convo = [chatService createConversationWithMembers:members error:&error];
        }
        if (!convo) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to create conversation"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo}];
    }];

    // chat.bsky.convo.acceptConvo
    [dispatcher registerMethod:@"chat.bsky.convo.acceptConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService acceptConversation:convoId memberDid:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to accept conversation"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.leaveConvo
    [dispatcher registerMethod:@"chat.bsky.convo.leaveConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService leaveConversation:convoId memberDid:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to leave conversation"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.listConvoRequests
    [dispatcher registerMethod:@"chat.bsky.convo.listConvoRequests"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSError *error = nil;
        NSArray *requests = [chatService listConversationRequestsForActor:actorDID error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"requests": requests ?: @[]}];
    }];

    // chat.bsky.convo.getConvoAvailability
    [dispatcher registerMethod:@"chat.bsky.convo.getConvoAvailability"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        if (!did || did.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"did is required"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"available": @YES}];
    }];

    // chat.bsky.convo.addReaction
    [dispatcher registerMethod:@"chat.bsky.convo.addReaction"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *messageId = body[@"messageId"];
        NSString *emoji = body[@"emoji"];
        if (!messageId || !emoji) {
            [XrpcErrorHelper setValidationError:response message:@"messageId and emoji are required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService addReaction:messageId actorDid:actorDID emoji:emoji error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to add reaction"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"emoji": emoji}];
    }];

    // chat.bsky.convo.removeReaction
    [dispatcher registerMethod:@"chat.bsky.convo.removeReaction"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *messageId = body[@"messageId"];
        NSString *emoji = body[@"emoji"];
        if (!messageId || !emoji) {
            [XrpcErrorHelper setValidationError:response message:@"messageId and emoji are required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService removeReaction:messageId actorDid:actorDID emoji:emoji error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to remove reaction"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.updateRead
    [dispatcher registerMethod:@"chat.bsky.convo.updateRead"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        NSString *messageId = body[@"messageId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService updateLastReadMessage:convoId
                                                memberDid:actorDID
                                                messageId:messageId ?: @""
                                                    error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to update read state"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.updateAllRead
    [dispatcher registerMethod:@"chat.bsky.convo.updateAllRead"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        // Mark all as read by updating last read to current time
        NSError *error = nil;
        BOOL success = [chatService updateLastReadMessage:convoId
                                                memberDid:actorDID
                                                messageId:@""
                                                    error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to update read state"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.muteConvo
    [dispatcher registerMethod:@"chat.bsky.convo.muteConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService muteConversation:convoId memberDid:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to mute conversation"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.unmuteConvo
    [dispatcher registerMethod:@"chat.bsky.convo.unmuteConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService unmuteConversation:convoId memberDid:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to unmute conversation"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.sendMessageBatch
    [dispatcher registerMethod:@"chat.bsky.convo.sendMessageBatch"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        NSArray *messages = body[@"messages"];
        if (!convoId || !messages) {
            [XrpcErrorHelper setValidationError:response message:@"convoId and messages are required"];
            return;
        }

        // Verify the conversation exists and the sender is a member
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        if (!convo) {
            [XrpcErrorHelper setValidationError:response message:@"Conversation not found"];
            return;
        }
        if (!XrpcChatConversationIncludesActor(convo, actorDID)) {
            response.statusCode = 403;
            [response setJsonBody:@{
                @"error": @"Forbidden",
                @"message": @"Not a member of this conversation"
            }];
            return;
        }

        NSError *error = nil;
        NSArray *sentMessages = [chatService sendMessageBatch:convoId
                                                    senderDid:actorDID
                                                     messages:messages
                                                        error:&error];
        if (!sentMessages) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to send message batch"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"messages": sentMessages}];
    }];

    // chat.bsky.convo.lockConvo
    [dispatcher registerMethod:@"chat.bsky.convo.lockConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService lockConversation:convoId error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to lock conversation"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.unlockConvo
    [dispatcher registerMethod:@"chat.bsky.convo.unlockConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (!convoId) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService unlockConversation:convoId error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to unlock conversation"];
            return;
        }
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.deleteMessageForSelf
    [dispatcher registerMethod:@"chat.bsky.convo.deleteMessageForSelf"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *messageId = body[@"messageId"];
        if (!messageId) {
            [XrpcErrorHelper setValidationError:response message:@"messageId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService deleteMessageForSelf:messageId memberDid:actorDID error:&error];
        if (!success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to delete message"];
            return;
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.listConvos
    [dispatcher registerMethod:@"chat.bsky.convo.listConvos"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);

        NSInteger limit = 50;
        NSString *limitStr = [request queryParamForKey:@"limit"];
        if (limitStr) limit = [limitStr integerValue];
        if (limit < 1) limit = 1;
        if (limit > 100) limit = 100;

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSArray *convos = nil;

        if (actorDID) {
            convos = [chatService listConversationsForActor:actorDID
                                                      limit:limit
                                                     cursor:cursor
                                                      error:&error];
        } else {
            // Admin fallback: validate admin secret explicitly from config
            NSString *adminSecret = services.adminSecret;
            NSString *token = authHeader;
            if ([authHeader hasPrefix:@"Bearer "]) {
                token = [authHeader substringFromIndex:@"Bearer ".length];
            }
            if (adminSecret && adminSecret.length > 0 && [token isEqualToString:adminSecret]) {
                convos = [chatService listAllConversationsWithLimit:limit
                                                             cursor:cursor
                                                              error:&error];
            } else {
                [XrpcErrorHelper setAuthenticationError:response message:@"Invalid admin secret"];
                return;
            }
        }

        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to list conversations"];
            return;
        }

        // Reshape to lexicon convoView format
        NSMutableArray *convoViews = [NSMutableArray array];
        PDSDatabase *serviceDatabase = [serviceDatabases serviceDatabaseWithError:nil];
        NSDictionary *handleMap = [self resolveHandlesForDids:[[self collectDidsFromConversations:convos] allObjects]
                                             serviceDatabase:serviceDatabase];
        [serviceDatabase close];

        for (NSDictionary *convo in (convos ?: @[])) {
            [convoViews addObject:[self convoViewFromInternalDict:convo handleMap:handleMap]];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"convos"] = convoViews;
        // Cursor: use last convo id if we got limit+1 results
        if (convos.count > (NSUInteger)limit) {
            NSDictionary *lastConvo = convos[convos.count - 2];
            result[@"cursor"] = lastConvo[@"id"] ?: @"";
            // Remove the extra entry
            [convoViews removeLastObject];
        }
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // chat.bsky.convo.getConvo
    [dispatcher registerMethod:@"chat.bsky.convo.getConvo"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSString *convoId = [request queryParamForKey:@"convoId"];
        if (!convoId || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        NSDictionary *convo = [chatService getConversationWithId:convoId error:&error];
        if (!convo) {
            response.statusCode = 404;
            [response setJsonBody:@{@"error": @"NotFound", @"message": @"Conversation not found"}];
            return;
        }
        response.statusCode = HttpStatusOK;
        // Collect DIDs from this single convo for handle resolution
        NSMutableSet *convoDids = [NSMutableSet set];
        for (NSDictionary *member in (convo[@"members"] ?: @[])) {
            NSString *did = member[@"did"];
            if (did) [convoDids addObject:did];
        }
        PDSDatabase *serviceDatabase = [serviceDatabases serviceDatabaseWithError:nil];
        NSDictionary *handleMap = [self resolveHandlesForDids:[convoDids allObjects] serviceDatabase:serviceDatabase];
        [serviceDatabase close];
        [response setJsonBody:@{@"convo": [self convoViewFromInternalDict:convo handleMap:handleMap]}];
    }];

    // chat.bsky.convo.getMessages
    [dispatcher registerMethod:@"chat.bsky.convo.getMessages"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);

        // Admin fallback: if no valid JWT, check admin secret from config
        if (!actorDID) {
            NSString *adminSecret = services.adminSecret;
            NSString *token = authHeader;
            if ([authHeader hasPrefix:@"Bearer "]) {
                token = [authHeader substringFromIndex:@"Bearer ".length];
            }
            if (!(adminSecret && adminSecret.length > 0 && [token isEqualToString:adminSecret])) {
                [XrpcErrorHelper setAuthenticationError:response message:@"Invalid admin secret"];
                return;
            }
        }

        NSString *convoId = [request queryParamForKey:@"convoId"];
        if (!convoId || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSInteger limit = 50;
        NSString *limitStr = [request queryParamForKey:@"limit"];
        if (limitStr) limit = [limitStr integerValue];
        if (limit < 1) limit = 1;
        if (limit > 100) limit = 100;

        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSArray *messages = [chatService getMessagesForConversation:convoId
                                                             limit:limit
                                                            cursor:cursor
                                                             error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to get messages"];
            return;
        }

        // Reshape to lexicon messageView format
        NSMutableArray *messageViews = [NSMutableArray array];
        NSString *nextCursor = nil;

        // Collect unique sender DIDs for handle resolution
        NSMutableSet *senderDids = [NSMutableSet set];
        for (NSDictionary *msg in (messages ?: @[])) {
            NSString *did = msg[@"senderDid"];
            if (did) [senderDids addObject:did];
        }
        PDSDatabase *serviceDatabase = [serviceDatabases serviceDatabaseWithError:nil];
        NSDictionary *handleMap = [self resolveHandlesForDids:[senderDids allObjects]
                                             serviceDatabase:serviceDatabase];
        [serviceDatabase close];

        for (NSUInteger i = 0; i < (messages ?: @[]).count; i++) {
            NSDictionary *msg = messages[i];
            if (i >= (NSUInteger)limit) {
                nextCursor = msg[@"id"];
                break;
            }
            NSMutableDictionary *view = [NSMutableDictionary dictionary];
            view[@"id"] = msg[@"id"] ?: @"";
            view[@"rev"] = msg[@"id"] ?: @"";
            view[@"text"] = msg[@"text"] ?: @"";
            NSString *senderDid = msg[@"senderDid"] ?: @"";
            NSMutableDictionary *sender = [NSMutableDictionary dictionary];
            sender[@"did"] = senderDid;
            NSString *handle = handleMap[senderDid];
            if (handle) sender[@"handle"] = handle;
            view[@"sender"] = sender;
            view[@"sentAt"] = msg[@"createdAt"] ?: @"";
            [messageViews addObject:view];
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"messages"] = messageViews;
        if (nextCursor) result[@"cursor"] = nextCursor;
        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // chat.bsky.convo.sendMessage
    [dispatcher registerMethod:@"chat.bsky.convo.sendMessage"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        NSDictionary *message = body[@"message"];
        if (!convoId || !message) {
            [XrpcErrorHelper setValidationError:response message:@"convoId and message are required"];
            return;
        }

        // Verify the conversation exists and the sender is a member
        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        if (!convo) {
            [XrpcErrorHelper setValidationError:response message:@"Conversation not found"];
            return;
        }
        if (!XrpcChatConversationIncludesActor(convo, actorDID)) {
            response.statusCode = 403;
            [response setJsonBody:@{
                @"error": @"Forbidden",
                @"message": @"Not a member of this conversation"
            }];
            return;
        }

        NSString *text = message[@"text"];
        NSString *embedJson = nil;
        if (message[@"embed"]) {
            NSData *embedData = [NSJSONSerialization dataWithJSONObject:message[@"embed"] options:0 error:nil];
            if (embedData) embedJson = [[NSString alloc] initWithData:embedData encoding:NSUTF8StringEncoding];
        }

        NSError *error = nil;
        NSDictionary *sentMessage = [chatService sendMessage:convoId
                                                    senderDid:actorDID
                                                         text:text
                                                    embedJson:embedJson
                                                        error:&error];
        if (!sentMessage) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to send message"];
            return;
        }

        // Reshape to lexicon messageView format
        NSMutableDictionary *view = [NSMutableDictionary dictionary];
        view[@"id"] = sentMessage[@"id"] ?: @"";
        view[@"rev"] = sentMessage[@"id"] ?: @"";
        view[@"text"] = sentMessage[@"text"] ?: @"";
        NSString *senderDid = sentMessage[@"senderDid"] ?: @"";
        NSMutableDictionary *sender = [NSMutableDictionary dictionary];
        sender[@"did"] = senderDid;
        PDSDatabase *serviceDatabase = [serviceDatabases serviceDatabaseWithError:nil];
        NSDictionary *handleMap = [self resolveHandlesForDids:@[senderDid] serviceDatabase:serviceDatabase];
        [serviceDatabase close];
        NSString *handle = handleMap[senderDid];
        if (handle) sender[@"handle"] = handle;
        view[@"sender"] = sender;
        view[@"sentAt"] = sentMessage[@"createdAt"] ?: @"";
        response.statusCode = HttpStatusOK;
        [response setJsonBody:view];
    }];

    // chat.bsky.convo.getLog
    [dispatcher registerMethod:@"chat.bsky.convo.getLog"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = XrpcChatActorDIDForRequest(request, response, services);
        if (!actorDID) return;

        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSArray *logs = [chatService getChatLogWithLimit:limit cursor:cursor error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"logs": logs ?: @[]}];
    }];

    GZ_LOG_INFO(@"Registered chat.bsky.convo.* endpoints");
}

#pragma mark - Lexicon Shape Helpers

+ (NSDictionary *)convoViewFromInternalDict:(NSDictionary *)convo
                             handleMap:(NSDictionary<NSString *, NSString *> *)handleMap {
    // Reshape internal ChatService dict to chat.bsky.convo.defs#convoView
    // Internal: { id, createdAt, updatedAt, members: [{ did, status, muted, lastReadId, joinedAt }], memberList }
    // Lexicon:  { id, rev, members: [{ did, handle }], muted, unreadCount, status }
    NSMutableArray *memberViews = [NSMutableArray array];
    BOOL currentUserMuted = NO;
    NSString *currentUserStatus = @"accepted";

    for (NSDictionary *member in (convo[@"members"] ?: @[])) {
        NSString *did = member[@"did"] ?: @"";
        NSMutableDictionary *memberView = [NSMutableDictionary dictionary];
        memberView[@"did"] = did;
        NSString *handle = handleMap[did];
        if (handle) memberView[@"handle"] = handle;
        [memberViews addObject:memberView];
        // Use first member's mute/status as the current user's (simplified)
        if (!currentUserMuted && [member[@"muted"] boolValue]) {
            currentUserMuted = YES;
        }
        if (member[@"status"] && ![member[@"status"] isEqualToString:@"accepted"]) {
            currentUserStatus = member[@"status"];
        }
    }

    NSMutableDictionary *view = [NSMutableDictionary dictionary];
    view[@"id"] = convo[@"id"] ?: @"";
    view[@"rev"] = convo[@"updatedAt"] ?: @"";
    view[@"members"] = memberViews;
    view[@"muted"] = @(currentUserMuted);
    view[@"unreadCount"] = @(0);
    view[@"status"] = currentUserStatus;

    NSDictionary *lastMessage = [convo[@"lastMessage"] isKindOfClass:[NSDictionary class]] ? convo[@"lastMessage"] : nil;
    if (lastMessage) {
        NSString *senderDid = lastMessage[@"senderDid"] ?: @"";
        NSMutableDictionary *sender = [NSMutableDictionary dictionary];
        sender[@"did"] = senderDid;
        NSString *handle = handleMap[senderDid];
        if (handle) sender[@"handle"] = handle;

        id textValue = lastMessage[@"text"];
        NSMutableDictionary *messageView = [NSMutableDictionary dictionary];
        messageView[@"id"] = lastMessage[@"id"] ?: @"";
        messageView[@"rev"] = lastMessage[@"id"] ?: @"";
        messageView[@"text"] = [textValue isKindOfClass:[NSString class]] ? textValue : @"";
        messageView[@"sender"] = sender;
        messageView[@"sentAt"] = lastMessage[@"createdAt"] ?: @"";
        view[@"lastMessage"] = messageView;
    }
    return view;
}

/// Resolve handles for a set of DIDs: accounts table first, DID resolver fallback.
+ (NSDictionary<NSString *, NSString *> *)resolveHandlesForDids:(NSArray<NSString *> *)dids
                                               serviceDatabase:(nullable id<PDSQueryDatabase>)serviceDatabase {
    if (dids.count == 0) return @{};

    NSMutableDictionary<NSString *, NSString *> *handleMap = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *unresolvedDids = [NSMutableSet setWithArray:dids];

    // 1. Try accounts table for local accounts
    if (serviceDatabase) {
        NSMutableString *placeholders = [NSMutableString string];
        NSMutableArray *params = [NSMutableArray array];
        for (NSUInteger i = 0; i < unresolvedDids.count; i++) {
            if (i > 0) [placeholders appendString:@", "];
            [placeholders appendString:@"?"];
        }
        [params addObjectsFromArray:[unresolvedDids allObjects]];

        NSString *query = [NSString stringWithFormat:@"SELECT did, handle FROM accounts WHERE did IN (%@)", placeholders];
        NSError *error = nil;
        NSArray *rows = [(PDSDatabase *)serviceDatabase executeParameterizedQuery:query params:params error:&error];
        if (!error) {
            for (NSDictionary *row in (rows ?: @[])) {
                NSString *did = row[@"did"];
                NSString *handle = row[@"handle"];
                if (did && handle) {
                    handleMap[did] = handle;
                    [unresolvedDids removeObject:did];
                }
            }
        }
    }

    // 2. Fallback: resolve remaining DIDs via DID resolver
    if (unresolvedDids.count > 0) {
        DIDResolver *resolver = [DIDResolver sharedResolver];
        for (NSString *did in unresolvedDids) {
            NSError *error = nil;
            DIDDocument *doc = [resolver resolveDIDSync:did error:&error];
            if (doc && doc.alsoKnownAs.count > 0) {
                for (id entry in doc.alsoKnownAs) {
                    if ([entry isKindOfClass:[NSString class]]) {
                        NSString *entryStr = (NSString *)entry;
                        if ([entryStr hasPrefix:@"at://"]) {
                            handleMap[did] = [entryStr substringFromIndex:5];
                            break;
                        }
                    }
                }
            }
        }
    }

    return [handleMap copy];
}

/// Collect all unique DIDs from an array of conversation dicts.
+ (NSSet<NSString *> *)collectDidsFromConversations:(NSArray<NSDictionary *> *)convos {
    NSMutableSet *dids = [NSMutableSet set];
    for (NSDictionary *convo in convos) {
        for (NSDictionary *member in (convo[@"members"] ?: @[])) {
            NSString *did = member[@"did"];
            if (did) [dids addObject:did];
        }
    }
    return dids;
}

@end
