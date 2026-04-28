/*!
 @file XrpcChatBskyActorPack.m

 @abstract XRPC route pack for chat.bsky.actor and chat.bsky.moderation endpoints.
 */

#import "Network/XrpcChatBskyActorPack.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcChatBskyActorPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
    // chat.bsky.actor.deleteAccount - Delete chat account
    [dispatcher registerMethod:@"chat.bsky.actor.deleteAccount"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        // Extract DID from auth header (simplified: assume it's the DID)
        NSString *token = [authHeader hasPrefix:@"Bearer "] ? [authHeader substringFromIndex:7] : authHeader;
        NSString *did = token;

        // Would delete all chat data for the actor
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    // chat.bsky.actor.exportAccountData - Export chat account data
    [dispatcher registerMethod:@"chat.bsky.actor.exportAccountData"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        // Would export all chat data as JSON
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"conversations": @[], @"messages": @[]}];
    }];

#pragma mark - Moderation

    // chat.bsky.moderation.getActorMetadata - Get actor moderation metadata
    [dispatcher registerMethod:@"chat.bsky.moderation.getActorMetadata"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSString *actor = [request queryParamForKey:@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"actor is required"];
            return;
        }

        // Stub response — chat moderation is handled by the dedicated syrena-chat service
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"did": actor,
            @"actor": actor,
            @"muted": @NO,
            @"blocked": @NO,
            @"labels": @[]
        }];
    }];

    // chat.bsky.moderation.getMessageContext - Get message context for moderation
    [dispatcher registerMethod:@"chat.bsky.moderation.getMessageContext"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSString *messageId = [request queryParamForKey:@"messageId"];
        if (!messageId) {
            [XrpcErrorHelper setValidationError:response message:@"messageId is required"];
            return;
        }

        // Stub response — chat moderation is handled by the dedicated syrena-chat service
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"message": @{@"id": messageId},
            @"context": @[]
        }];
    }];

    // chat.bsky.moderation.updateActorAccess - Update actor's chat access
    [dispatcher registerMethod:@"chat.bsky.moderation.updateActorAccess"
                       handler:^(HttpRequest *request, HttpResponse *response) {
        NSString *authHeader = [request headerForKey:@"Authorization"];
        if (!authHeader) {
            [XrpcErrorHelper setAuthenticationError:response message:@"Authentication required"];
            return;
        }

        NSDictionary *body = request.jsonBody;
        NSString *actor = body[@"actor"];
        if (!actor) {
            [XrpcErrorHelper setValidationError:response message:@"actor is required"];
            return;
        }

        // Stub response — chat moderation is handled by the dedicated syrena-chat service
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

@end
