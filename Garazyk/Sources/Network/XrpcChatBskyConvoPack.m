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
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Chat/Server/Services/ChatService.h"
#import "Chat/Server/Config/ChatSchemaManager.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

@implementation XrpcChatBskyConvoPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                      jwtMinter:(nullable JWTMinter *)jwtMinter
                adminController:(nullable id<PDSAdminController>)adminController {

    // Ensure chat schema tables exist
    PDSDatabase *db = (PDSDatabase *)appViewDatabase;
    ChatSchemaManager *schemaManager = [ChatSchemaManager sharedManager];
    [db executeRawSQL:[schemaManager chatSchemaSQL] error:nil];

    ChatService *chatService = [[ChatService alloc] initWithDatabase:appViewDatabase];

    // chat.bsky.convo.getConvoForMembers
    [dispatcher registerMethod:@"chat.bsky.convo.getConvoForMembers"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSArray *members = body[@"members"];
        if (!members || members.count < 2) {
            [XrpcErrorHelper setValidationError:response message:@"At least two members required"];
            return;
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        NSArray *messages = body[@"messages"];
        if (!convoId || !messages) {
            [XrpcErrorHelper setValidationError:response message:@"convoId and messages are required"];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
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

    // chat.bsky.convo.getLog
    [dispatcher registerMethod:@"chat.bsky.convo.getLog"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                            jwtMinter:jwtMinter
                                                      adminController:adminController
                                                              request:request
                                                             response:response];
        if (!actorDID) return;

        NSInteger limit = 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        NSError *error = nil;
        NSArray *logs = [chatService getChatLogWithLimit:limit cursor:cursor error:&error];
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"logs": logs ?: @[]}];
    }];

    PDS_LOG_INFO(@"Registered chat.bsky.convo.* endpoints");
}

@end
