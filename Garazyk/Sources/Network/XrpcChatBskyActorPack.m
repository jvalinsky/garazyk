// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcChatBskyActorPack.m

 @abstract XRPC route pack for chat.bsky.actor and chat.bsky.moderation endpoints.
 */

#import "Network/XrpcChatBskyActorPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"

@implementation XrpcChatBskyActorPack

+ (NSString *)routePackIdentifier {
  return @"chat.bsky.actor";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:dispatcher.jwtMinter
                                          adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  id<XrpcRoutePackServices> resolvedServices = services;
  if (!resolvedServices) {
    resolvedServices =
        [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                  jwtMinter:dispatcher.jwtMinter
                                            adminController:nil
                                               configuration:nil
                                                 adminSecret:nil
                                           serviceDatabases:nil
                                           userDatabasePool:nil
                                                 rateLimiter:nil];
  }

  [dispatcher registerMethod:@"chat.bsky.actor.deleteAccount"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       if (![context requireAuthentication]) {
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  [dispatcher registerMethod:@"chat.bsky.actor.exportAccountData"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       if (![context requireAuthentication]) {
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"conversations" : @[], @"messages" : @[]}];
                     }];

#pragma mark - Moderation

  [dispatcher registerMethod:@"chat.bsky.moderation.getActorMetadata"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       if (![context requireAuthentication]) {
                         return;
                       }

                       NSString *actor = [request queryParamForKey:@"actor"];
                       if (!actor) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"actor is required"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"did" : actor,
                         @"actor" : actor,
                         @"muted" : @NO,
                         @"blocked" : @NO,
                         @"labels" : @[]
                       }];
                     }];

  [dispatcher registerMethod:@"chat.bsky.moderation.getMessageContext"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       if (![context requireAuthentication]) {
                         return;
                       }

                       NSString *messageId = [request queryParamForKey:@"messageId"];
                       if (!messageId) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"messageId is required"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"message" : @{@"id" : messageId},
                         @"context" : @[]
                       }];
                     }];

  [dispatcher registerMethod:@"chat.bsky.moderation.updateActorAccess"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       if (![context requireAuthentication]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       NSString *actor = body[@"actor"];
                       if (!actor) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"actor is required"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];
}

@end
