#import "Network/XrpcChatBskyConvoPack.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"
#import "AppView/Services/ChatService.h"
#import "AppView/Services/ActorService.h"
#import "Database/PDSDatabase.h"

@implementation XrpcChatBskyConvoPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                    jwtMinter:(JWTMinter *)jwtMinter
              adminController:(id<PDSAdminController>)adminController {

    ChatService *chatService = [[ChatService alloc] initWithDatabase:appViewDatabase];
    ActorService *actorService = [[ActorService alloc] initWithDatabase:appViewDatabase];
    // chat.bsky.convo.getConvoForMembers - Get or create conversation for members
    [dispatcher registerMethod:@"chat.bsky.convo.getConvoForMembers"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSArray *memberDids = body[@"members"];
        if (![memberDids isKindOfClass:[NSArray class]] || memberDids.count < 2) {
            [XrpcErrorHelper setValidationError:response message:@"members must be an array with at least 2 DIDs"];
            return;
        }

        NSError *error = nil;
        NSDictionary *convo = [chatService getConversationForMembers:memberDids error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.acceptConvo - Accept pending conversation
    [dispatcher registerMethod:@"chat.bsky.convo.acceptConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService acceptConversation:convoId memberDid:actorDID error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to accept conversation"];
            return;
        }

        NSDictionary *convo = [chatService getConversationWithId:convoId error:nil];
        response.statusCode = 200;
        [response setJsonBody:@{@"convo": convo ?: @{}}];
    }];

    // chat.bsky.convo.leaveConvo - Leave a conversation
    [dispatcher registerMethod:@"chat.bsky.convo.leaveConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService leaveConversation:convoId memberDid:actorDID error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to leave conversation"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.listConvoRequests - List pending conversation requests
    [dispatcher registerMethod:@"chat.bsky.convo.listConvoRequests"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSError *error = nil;
        NSArray *requests = [chatService listConversationRequestsForActor:actorDID error:&error];
        if (error) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"requests": requests ?: @[]}];
    }];

    // chat.bsky.convo.getConvoAvailability - Check if can message actor
    [dispatcher registerMethod:@"chat.bsky.convo.getConvoAvailability"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        if (![did isKindOfClass:[NSString class]] || did.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"did parameter is required"];
            return;
        }

        // Check if actor exists
        NSDictionary *actor = [actorService getProfileForActor:did error:nil];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"Actor not found"];
            return;
        }

        // For now, assume available if actor exists
        // In future: check blocks, privacy settings, etc.
        BOOL available = YES;

        response.statusCode = 200;
        [response setJsonBody:@{@"available": @(available)}];
    }];

    // chat.bsky.convo.addReaction - Add emoji reaction to message
    [dispatcher registerMethod:@"chat.bsky.convo.addReaction"
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
        BOOL success = [chatService addReaction:messageId actorDid:actorDID emoji:emoji error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to add reaction"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"messageId": messageId, @"emoji": emoji, @"actorDid": actorDID}];
    }];

    // chat.bsky.convo.removeReaction - Remove emoji reaction from message
    [dispatcher registerMethod:@"chat.bsky.convo.removeReaction"
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
        BOOL success = [chatService removeReaction:messageId actorDid:actorDID emoji:emoji error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to remove reaction"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.updateRead - Update read state for a message
    [dispatcher registerMethod:@"chat.bsky.convo.updateRead"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        NSString *messageId = body[@"messageId"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }
        if (![messageId isKindOfClass:[NSString class]] || messageId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"messageId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService updateLastReadMessage:convoId memberDid:actorDID messageId:messageId error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to update read state"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.updateAllRead - Mark all messages as read
    [dispatcher registerMethod:@"chat.bsky.convo.updateAllRead"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        // Get latest message ID for this conversation
        NSString *query = @"SELECT id FROM messages WHERE convo_id = ? ORDER BY created_at DESC LIMIT 1";
        NSArray *rows = [(PDSDatabase *)appViewDatabase executeParameterizedQuery:query
                                                                           params:@[convoId]
                                                                            error:nil];
        if (rows.count == 0) {
            response.statusCode = 200;
            [response setJsonBody:@{}];
            return;
        }

        NSString *latestMessageId = rows[0][@"id"];
        NSError *error = nil;
        BOOL success = [chatService updateLastReadMessage:convoId memberDid:actorDID messageId:latestMessageId error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to mark all as read"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.muteConvo - Mute conversation notifications
    [dispatcher registerMethod:@"chat.bsky.convo.muteConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService muteConversation:convoId memberDid:actorDID error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to mute conversation"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.unmuteConvo - Unmute conversation notifications
    [dispatcher registerMethod:@"chat.bsky.convo.unmuteConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService unmuteConversation:convoId memberDid:actorDID error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to unmute conversation"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.deleteMessageForSelf - Delete message locally (not for others)
    [dispatcher registerMethod:@"chat.bsky.convo.deleteMessageForSelf"
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
        BOOL success = [chatService deleteMessageForSelf:messageId memberDid:actorDID error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to delete message"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.lockConvo - Lock conversation (prevent messages)
    [dispatcher registerMethod:@"chat.bsky.convo.lockConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService lockConversation:convoId error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to lock conversation"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.unlockConvo - Unlock conversation
    [dispatcher registerMethod:@"chat.bsky.convo.unlockConvo"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }

        NSError *error = nil;
        BOOL success = [chatService unlockConversation:convoId error:&error];
        if (error || !success) {
            [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to unlock conversation"];
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.convo.sendMessageBatch - Send multiple messages
    [dispatcher registerMethod:@"chat.bsky.convo.sendMessageBatch"
                     handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                           jwtMinter:jwtMinter
                                                     adminController:adminController
                                                             request:request
                                                            response:response];
        if (!actorDID) return;

        NSDictionary *body = request.jsonBody;
        NSString *convoId = body[@"convoId"];
        NSArray *messages = body[@"messages"];

        if (![convoId isKindOfClass:[NSString class]] || convoId.length == 0) {
            [XrpcErrorHelper setValidationError:response message:@"convoId is required"];
            return;
        }
        if (![messages isKindOfClass:[NSArray class]] || messages.count == 0) {
            [XrpcErrorHelper setValidationError:response message:@"messages array is required and must not be empty"];
            return;
        }

        NSError *error = nil;
        NSArray *sentMessages = [chatService sendMessageBatch:convoId
                                                   senderDid:actorDID
                                                    messages:messages
                                                       error:&error];
        if (error || !sentMessages) {
            NSInteger statusCode = ([error.domain isEqualToString:@"ChatService"] && error.code == 403) ? 403 : 400;
            if (statusCode == 403) {
                [XrpcErrorHelper setValidationError:response message:error.localizedDescription];
            } else {
                [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription ?: @"Failed to send messages"];
            }
            return;
        }

        response.statusCode = 200;
        [response setJsonBody:@{@"messages": sentMessages}];
    }];

    PDS_LOG_INFO(@"Registered chat.bsky.convo.* endpoints (core + features)");
}

@end
