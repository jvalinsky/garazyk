// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyContactPack.m

 @abstract XRPC route pack for app.bsky.contact endpoints.
 */

#import "Network/XrpcAppBskyContactPack.h"

#import "AppView/Services/ContactService.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/Generated/GZXrpcNSID.h"

@implementation XrpcAppBskyContactPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.contact";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                 contactService:(ContactService *)contactService
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
  services.contactService = contactService;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  ContactService *contactService = services.contactService;
  if (!contactService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_startPhoneVerification
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
                       NSString *phoneNumber = body[@"phoneNumber"];
                       if (!phoneNumber || phoneNumber.length == 0) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"phoneNumber is required"];
                         return;
                       }

                       NSError *error = nil;
                       NSString *verificationId =
                           [contactService startPhoneVerification:phoneNumber
                                                            actor:actorDID
                                                            error:&error];
                       if (error || !verificationId) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to start verification"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"verificationId" : verificationId}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_verifyPhone
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
                       NSString *phoneNumber = body[@"phoneNumber"];
                       NSString *code = body[@"code"];
                       if (!phoneNumber || !code) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"phoneNumber and code are required"];
                         return;
                       }

                       NSError *error = nil;
                       NSString *token = [contactService verifyPhone:phoneNumber
                                                                code:code
                                                               actor:actorDID
                                                               error:&error];
                       if (error || !token) {
                         response.statusCode = HttpStatusBadRequest;
                         [response setJsonBody:@{
                           @"error" : @"InvalidCode",
                           @"message" : error.localizedDescription ?: @"Invalid verification code"
                         }];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"token" : token}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_importContacts
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
                       NSString *token = body[@"token"];
                       NSArray *contacts = body[@"contacts"];
                       if (!token || !contacts) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"token and contacts are required"];
                         return;
                       }

                       NSError *error = nil;
                       NSDictionary *result = [contactService importContacts:contacts
                                                                       token:token
                                                                       actor:actorDID
                                                                       error:&error];
                       if (error || !result) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to import contacts"];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:result];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_getMatches
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
                       NSArray *matches = [contactService getMatchesForActor:actorDID error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{@"matches" : matches ?: @[]}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_dismissMatch
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
                       NSString *matchDID = body[@"did"];
                       if (!matchDID) {
                         [XrpcErrorHelper setValidationError:response message:@"did is required"];
                         return;
                       }

                       NSError *error = nil;
                       BOOL success = [contactService dismissMatch:matchDID
                                                               actor:actorDID
                                                               error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_getSyncStatus
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
                       NSDictionary *status =
                           [contactService getSyncStatusForActor:actorDID error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:status ?: @{@"syncedAt" : @"", @"matchesCount" : @(0)}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_removeData
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
                       BOOL success = [contactService removeDataForActor:actorDID error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_contact_sendNotification
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       if (![context requireAuthentication]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       NSString *fromDID = body[@"from"];
                       NSString *toDID = body[@"to"];
                       if (!fromDID || !toDID) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"from and to are required"];
                         return;
                       }

                       NSError *error = nil;
                       BOOL success = [contactService sendNotificationFrom:fromDID
                                                                        to:toDID
                                                                     error:&error];
                       if (!success) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{}];
                     }];
}

@end
