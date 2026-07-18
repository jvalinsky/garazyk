// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyDraftsPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"
#import "AppView/Services/DraftService.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcAppBskyDraftsPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.draft";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                  draftService:(DraftService *)draftService
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  services.draftService = draftService;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  DraftService *draftService = services.draftService;
  if (!draftService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_draft_createDraft
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSDictionary *body = [request jsonBody];
                       NSDictionary *content = body[@"content"] ?: @{};

                       NSError *error = nil;
                       NSDictionary *result = [draftService createDraftForDID:actorDID
                                                                      content:content
                                                                        error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to create draft"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:result ?: @{}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_draft_updateDraft
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSDictionary *body = [request jsonBody];
                       NSString *draftID = body[@"id"];
                       if (!draftID) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"Missing draft id"];
                         return;
                       }

                       NSDictionary *content = body[@"content"] ?: @{};
                       NSError *error = nil;
                       BOOL success = [draftService updateDraftForDID:actorDID
                                                             draftID:draftID
                                                             content:content
                                                               error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to update draft"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_draft_getDrafts
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSError *error = nil;
                       NSArray *drafts = [draftService getDraftsForDID:actorDID error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to get drafts"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"drafts" : drafts ?: @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_draft_deleteDraft
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       NSString *draftID = body[@"id"] ?: body[@"uri"];
                       if (!draftID) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"Missing draft id parameter"];
                         return;
                       }

                       NSError *error = nil;
                       BOOL success = [draftService deleteDraftForDID:actorDID
                                                             draftID:draftID
                                                               error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to delete draft"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];
}

@end
