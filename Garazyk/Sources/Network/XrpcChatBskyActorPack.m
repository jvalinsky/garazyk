// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcChatBskyActorPack.m

 @abstract XRPC route pack for chat.bsky.actor and chat.bsky.moderation endpoints.
 */

#import "Network/XrpcChatBskyActorPack.h"

#import "Chat/Server/ChatAuthManager.h"
#import "Network/ATProtoSafeHTTPClient.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"
#import "Debug/GZLogger.h"

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

#pragma mark - Declaration (convenience query)

  // chat.bsky.actor.declaration is a record type stored in the user's PDS repo
  // at at://<did>/chat.bsky.actor.declaration/self. Clients access it via
  // com.atproto.repo.getRecord, but the Bluesky reference chat service also
  // exposes a convenience query endpoint that reads the record and returns it.
  [dispatcher registerMethod:@"chat.bsky.actor.declaration"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       // Authenticate via ChatAuthManager (same pattern as ConvoPack)
                       NSString *methodNSID = request.pathParameters[@"method"] ?: @"chat.bsky.actor.declaration";
                       NSString *actorDID =
                           [[ChatAuthManager sharedManager] authenticateRequest:request
                                                                        response:response
                                                                   expectedMethod:methodNSID];
                       if (!actorDID) {
                         return;
                       }

                       NSString *pdsUrl = [ChatAuthManager sharedManager].pdsUrl;
                       if (pdsUrl.length == 0) {
                         pdsUrl = @"http://127.0.0.1:2583";
                       }

                       NSString *encodedDid =
                           [actorDID stringByAddingPercentEncodingWithAllowedCharacters:
                               [NSCharacterSet URLQueryAllowedCharacterSet]];
                       NSString *getUrl = [NSString stringWithFormat:
                           @"%@/xrpc/com.atproto.repo.getRecord?collection=chat.bsky.actor.declaration&rkey=self&repo=%@",
                           pdsUrl, encodedDid];

                       NSURL *url = [NSURL URLWithString:getUrl];
                       if (!url) {
                         GZ_LOG_ERROR(@"chat.bsky.actor.declaration: invalid PDS URL: %@", getUrl);
                         response.statusCode = 500;
                         [response setJsonBody:@{
                           @"error": @"InternalServerError",
                           @"message": @"Failed to construct PDS record URL"
                         }];
                         return;
                       }

                       NSMutableURLRequest *urlRequest =
                           [NSMutableURLRequest requestWithURL:url
                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                              timeoutInterval:10.0];
                       [urlRequest setHTTPMethod:@"GET"];

                       ATProtoSafeHTTPClientOptions *options =
                           [ATProtoSafeHTTPClientOptions defaultOptions];
                       options.allowHTTP = YES;
                       options.allowPrivateHosts = YES;

                       NSHTTPURLResponse *urlResponse = nil;
                       NSError *fetchError = nil;
                       NSData *responseData =
                           [[ATProtoSafeHTTPClient sharedClient] sendSynchronousRequest:urlRequest
                                                                                 options:options
                                                                                response:&urlResponse
                                                                                   error:&fetchError];

                       NSInteger statusCode = urlResponse.statusCode;

                       // Record not found — return default declaration (allowIncoming = "all")
                       if (!responseData || statusCode == 404) {
                         NSString *uri = [NSString stringWithFormat:
                             @"at://%@/chat.bsky.actor.declaration/self", actorDID];
                         response.statusCode = HttpStatusOK;
                         [response setJsonBody:@{
                           @"uri": uri,
                           @"value": @{
                             @"$type": @"chat.bsky.actor.declaration",
                             @"allowIncoming": @"all"
                           }
                         }];
                         return;
                       }

                       if (statusCode < 200 || statusCode >= 300) {
                         GZ_LOG_ERROR(@"chat.bsky.actor.declaration: PDS returned status %ld for %@",
                                      (long)statusCode, actorDID);
                         // Fall back to default on PDS error
                         NSString *uri = [NSString stringWithFormat:
                             @"at://%@/chat.bsky.actor.declaration/self", actorDID];
                         response.statusCode = HttpStatusOK;
                         [response setJsonBody:@{
                           @"uri": uri,
                           @"value": @{
                             @"$type": @"chat.bsky.actor.declaration",
                             @"allowIncoming": @"all"
                           }
                         }];
                         return;
                       }

                       id json = [NSJSONSerialization JSONObjectWithData:responseData
                                                                  options:0
                                                                    error:nil];
                       if (![json isKindOfClass:[NSDictionary class]]) {
                         GZ_LOG_ERROR(@"chat.bsky.actor.declaration: PDS response not JSON for %@",
                                      actorDID);
                         response.statusCode = 500;
                         [response setJsonBody:@{
                           @"error": @"InternalServerError",
                           @"message": @"Invalid PDS response"
                         }];
                         return;
                       }

                       NSDictionary *pdsResult = (NSDictionary *)json;
                       // PDS returns {uri, cid, value} — forward it
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:pdsResult];
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
