// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyDraftsPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcHandler.h"
#import "AppView/Services/DraftService.h"

@implementation XrpcAppBskyDraftsPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                  draftService:(DraftService *)draftService
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {

  // app.bsky.draft.createDraft
  [dispatcher registerMethod:@"app.bsky.draft.createDraft"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }

                       NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                                           jwtMinter:jwtMinter
                                                                     adminController:adminController
                                                                             request:request];
                       if (!actorDID) {
                         [XrpcErrorHelper setAuthenticationError:response
                                                        message:@"Invalid authentication token"];
                         return;
                       }

                       NSDictionary *body = [request jsonBody];
                       NSDictionary *content = body[@"content"];
                       if (!content) {
                           content = @{};
                       }

                       NSError *error = nil;
                       NSDictionary *result = [draftService createDraftForDID:actorDID
                                                                      content:content
                                                                        error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                       message:error.localizedDescription ?: @"Failed to create draft"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:result ?: @{}];
                     }];

  // app.bsky.draft.updateDraft
  [dispatcher registerMethod:@"app.bsky.draft.updateDraft"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }

                       NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                                           jwtMinter:jwtMinter
                                                                     adminController:adminController
                                                                             request:request];
                       if (!actorDID) {
                         [XrpcErrorHelper setAuthenticationError:response
                                                        message:@"Invalid authentication token"];
                         return;
                       }

                       NSDictionary *body = [request jsonBody];
                       NSString *draftID = body[@"id"];
                       if (!draftID) {
                         [XrpcErrorHelper setValidationError:response
                                                   message:@"Missing draft id"];
                         return;
                       }

                       NSDictionary *content = body[@"content"];
                       if (!content) {
                           content = @{};
                       }

                       NSError *error = nil;
                       BOOL success = [draftService updateDraftForDID:actorDID
                                                             draftID:draftID
                                                             content:content
                                                               error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                       message:error.localizedDescription ?: @"Failed to update draft"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  // app.bsky.draft.getDrafts
  [dispatcher registerMethod:@"app.bsky.draft.getDrafts"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }

                       NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                                           jwtMinter:jwtMinter
                                                                     adminController:adminController
                                                                             request:request];
                       if (!actorDID) {
                         [XrpcErrorHelper setAuthenticationError:response
                                                        message:@"Invalid authentication token"];
                         return;
                       }

                       NSError *error = nil;
                       NSArray *drafts = [draftService getDraftsForDID:actorDID
                                                                error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                       message:error.localizedDescription ?: @"Failed to get drafts"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"drafts": drafts ?: @[]}];
                     }];

  // app.bsky.draft.deleteDraft
  [dispatcher registerMethod:@"app.bsky.draft.deleteDraft"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       NSString *authHeader =
                           [request headerForKey:@"Authorization"];
                       if (!authHeader) {
                         [XrpcErrorHelper
                             setAuthenticationError:response
                                            message:@"Authentication required"];
                         return;
                       }

                       NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                                           jwtMinter:jwtMinter
                                                                     adminController:adminController
                                                                             request:request];
                       if (!actorDID) {
                         [XrpcErrorHelper setAuthenticationError:response
                                                        message:@"Invalid authentication token"];
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
                                                       message:error.localizedDescription ?: @"Failed to delete draft"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];
}

@end
