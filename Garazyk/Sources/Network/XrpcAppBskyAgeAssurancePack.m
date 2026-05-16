// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyAgeAssurancePack.m

 @abstract XRPC route pack for app.bsky.ageassurance endpoints.
 */

#import "Network/XrpcAppBskyAgeAssurancePack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"
#import "AppView/Services/AgeAssuranceService.h"

@implementation XrpcAppBskyAgeAssurancePack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.ageassurance";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
           ageAssuranceService:(AgeAssuranceService *)ageAssuranceService {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:dispatcher.jwtMinter
                                          adminController:nil
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  services.ageAssuranceService = ageAssuranceService;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  AgeAssuranceService *ageAssuranceService = nil;
  if ([services respondsToSelector:@selector(ageAssuranceService)]) {
    ageAssuranceService = services.ageAssuranceService;
  }

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

  [dispatcher registerMethod:@"app.bsky.ageassurance.begin"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *did = nil;
                       if (![context requireAuthenticatedDID:&did]) {
                         return;
                       }

                       NSDictionary *body = request.jsonBody;
                       NSString *email = body[@"email"];
                       NSString *language = body[@"language"];
                       NSString *countryCode = body[@"countryCode"];
                       NSString *regionCode = body[@"regionCode"];

                       if (!email || !language || !countryCode) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"email, language, and countryCode are required"];
                         return;
                       }

                       if (ageAssuranceService) {
                         NSError *error = nil;
                         NSDictionary *result =
                             [ageAssuranceService beginAgeAssurance:did
                                                              email:email
                                                           language:language
                                                        countryCode:countryCode
                                                         regionCode:regionCode
                                                              error:&error];
                         if (error) {
                           [XrpcErrorHelper setInternalServerError:response
                                                           message:error.localizedDescription];
                           return;
                         }
                         response.statusCode = HttpStatusOK;
                         [response setJsonBody:result];
                         return;
                       }

                       NSString *stateId = [[NSUUID UUID] UUIDString];
                       NSString *token = [[NSUUID UUID] UUIDString];
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"id" : stateId,
                         @"status" : @"pending",
                         @"token" : token
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.ageassurance.getConfig"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       (void)request;
                       if (ageAssuranceService) {
                         NSError *error = nil;
                         NSDictionary *config = [ageAssuranceService getAgeAssuranceConfig:&error];
                         if (error) {
                           [XrpcErrorHelper setInternalServerError:response
                                                           message:error.localizedDescription];
                           return;
                         }
                         response.statusCode = HttpStatusOK;
                         [response setJsonBody:config];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"enabled" : @YES,
                         @"methods" : @[
                           @{@"type" : @"email", @"description" : @"Verify age via email"},
                           @{@"type" : @"id", @"description" : @"Verify age with ID document"}
                         ],
                         @"minimumAge" : @18,
                         @"supportedCountries" : @[ @"US", @"CA", @"GB", @"AU", @"NZ" ]
                       }];
                     }];

  [dispatcher registerMethod:@"app.bsky.ageassurance.getState"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *did = nil;
                       if (![context requireAuthenticatedDID:&did]) {
                         return;
                       }

                       NSString *countryCode = [request queryParamForKey:@"countryCode"];
                       NSString *regionCode = [request queryParamForKey:@"regionCode"];
                       if (!countryCode) {
                         [XrpcErrorHelper setValidationError:response
                                                     message:@"countryCode is required"];
                         return;
                       }

                       if (ageAssuranceService) {
                         NSError *error = nil;
                         NSDictionary *state = [ageAssuranceService getAgeAssuranceState:did
                                                                             countryCode:countryCode
                                                                              regionCode:regionCode
                                                                                   error:&error];
                         if (error) {
                           [XrpcErrorHelper setInternalServerError:response
                                                           message:error.localizedDescription];
                           return;
                         }
                         response.statusCode = HttpStatusOK;
                         [response setJsonBody:@{
                           @"state" : state ?: @{@"id" : @"", @"status" : @"none"},
                           @"metadata" : @{
                             @"countryCode" : countryCode,
                             @"regionCode" : regionCode ?: @"",
                             @"computedAt" : [NSString
                                 stringWithFormat:@"%.0f",
                                                  [[NSDate date] timeIntervalSince1970]]
                           }
                         }];
                         return;
                       }

                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:@{
                         @"state" : @{@"id" : @"", @"status" : @"none"},
                         @"metadata" : @{
                           @"countryCode" : countryCode,
                           @"regionCode" : regionCode ?: @"",
                           @"computedAt" : [NSString
                               stringWithFormat:@"%.0f",
                                                [[NSDate date] timeIntervalSince1970]]
                         }
                       }];
                     }];
}

@end
