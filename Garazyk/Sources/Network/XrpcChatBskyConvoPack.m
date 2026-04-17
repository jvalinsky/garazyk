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

    PDS_LOG_INFO(@"Registered chat.bsky.convo.* core endpoints");
}

@end
