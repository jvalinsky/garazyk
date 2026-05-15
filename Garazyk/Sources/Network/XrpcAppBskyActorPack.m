// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file XrpcAppBskyActorPack.m

 @abstract XRPC route pack for app.bsky.actor endpoints.
 */

#import "Network/XrpcAppBskyActorPack.h"

#import "AppView/Services/ActorService.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"

@implementation XrpcAppBskyActorPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.actor";
}

+ (nullable ActorService *)actorServiceForServices:(id<XrpcRoutePackServices>)services {
  id<PDSQueryDatabase> database = services.appViewDatabase;
  if (!database) {
    return nil;
  }
  return [[ActorService alloc] initWithDatabase:database];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  [self registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
  [self registerAppViewMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                     jwtMinter:(JWTMinter *)jwtMinter
                               adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                         serviceDatabases:nil
                                               rateLimiter:nil];
  services.appViewDatabase = appViewDatabase;
  [self registerPDSLevelMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                              appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                                    jwtMinter:(JWTMinter *)jwtMinter
                              adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                         serviceDatabases:nil
                                               rateLimiter:nil];
  services.appViewDatabase = appViewDatabase;
  [self registerAppViewMethodsWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               appViewDatabase:(id<PDSQueryDatabase>)appViewDatabase
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
  XrpcRoutePackServiceBag *services =
      [[XrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                         serviceDatabases:nil
                                               rateLimiter:nil];
  services.appViewDatabase = appViewDatabase;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerPDSLevelMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                     services:(id<XrpcRoutePackServices>)services {
  ActorService *actorService = [self actorServiceForServices:services];
  if (!actorService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerAppBskyActorGetPreferences:^(HttpRequest *request, HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSError *error = nil;
    NSDictionary *preferences = [actorService getPreferencesForActor:actorDID error:&error];
    if (error) {
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:preferences ?: @{@"preferences": @{}}];
  }];

  [dispatcher registerAppBskyActorPutPreferences:^(HttpRequest *request, HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSDictionary *body = request.jsonBody;
    NSArray *preferences = body[@"preferences"];
    if (!preferences || ![preferences isKindOfClass:[NSArray class]]) {
      [XrpcErrorHelper setValidationError:response
                                  message:@"Invalid preferences JSON (expected array under 'preferences' key)"];
      return;
    }

    NSError *error = nil;
    BOOL success = [actorService putPreferencesForActor:actorDID preferences:preferences error:&error];
    if (error || !success) {
      [XrpcErrorHelper setInternalServerError:response
                                      message:error.localizedDescription ?: @"Failed to store preferences"];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];
}

+ (void)registerAppViewMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                                    services:(id<XrpcRoutePackServices>)services {
  ActorService *actorService = [self actorServiceForServices:services];
  if (!actorService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerAppBskyActorGetProfile:^(HttpRequest *request, HttpResponse *response) {
    NSString *actor = [request queryParamForKey:@"actor"];
    if (!actor) {
      [XrpcErrorHelper setValidationError:response message:@"Missing actor parameter"];
      return;
    }

    NSError *error = nil;
    NSDictionary *profile = [actorService getProfileForActor:actor error:&error];
    if (error) {
      [XrpcErrorHelper setNotFoundError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:profile];
  }];

  [dispatcher registerAppBskyActorGetProfiles:^(HttpRequest *request, HttpResponse *response) {
    id actorsParam = request.queryParams[@"actors"];
    NSArray<NSString *> *actors = nil;

    if ([actorsParam isKindOfClass:[NSArray class]]) {
      actors = actorsParam;
    } else if ([actorsParam isKindOfClass:[NSString class]]) {
      actors = @[actorsParam];
    } else {
      [XrpcErrorHelper setValidationError:response message:@"Missing actors parameter"];
      return;
    }

    if (actors.count == 0) {
      [XrpcErrorHelper setValidationError:response message:@"Missing actors parameter"];
      return;
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *profiles = [actorService getProfilesForActors:actors error:&error];
    if (error) {
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"profiles" : profiles ?: @[]}];
  }];

  [dispatcher registerAppBskyActorSearchActors:^(HttpRequest *request, HttpResponse *response) {
    NSString *term = [request queryParamForKey:@"q"];
    if (!term || term.length == 0) {
      [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
      response.statusCode = HttpStatusBadRequest;
      return;
    }

    NSInteger limit = 25;
    if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
      return;
    }

    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [actorService searchActors:term limit:limit cursor:cursor error:&error];
    if (error) {
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  [dispatcher registerAppBskyActorSearchActorsTypeahead:^(HttpRequest *request, HttpResponse *response) {
    NSString *term = [request queryParamForKey:@"q"];
    if (!term || term.length == 0) {
      [XrpcErrorHelper setValidationError:response message:@"Missing search term (q parameter)"];
      response.statusCode = HttpStatusBadRequest;
      return;
    }

    NSInteger limit = 10;
    if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
      return;
    }

    NSError *error = nil;
    NSArray<NSDictionary *> *actors = [actorService searchActorsTypeahead:term limit:limit error:&error];
    if (error) {
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{@"actors" : actors ?: @[]}];
  }];

  [dispatcher registerMethod:@"app.bsky.actor.getSuggestions"
                     handler:^(HttpRequest *request, HttpResponse *response) {
                       XrpcHandlerContext *context =
                           [[XrpcHandlerContext alloc] initWithRequest:request
                                                             response:response
                                                             services:resolvedServices];
                       NSString *actorDID = nil;
                       if (![context requireAuthenticatedDID:&actorDID]) {
                         return;
                       }

                       NSInteger limit = 30;
                       if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
                         return;
                       }
                       NSString *cursor = [request queryParamForKey:@"cursor"];

                       NSError *error = nil;
                       NSDictionary *result = [actorService getSuggestionsForActor:actorDID
                                                                           limit:limit
                                                                          cursor:cursor
                                                                           error:&error];
                       if (error) {
                         [XrpcErrorHelper setInternalServerError:response
                                                         message:error.localizedDescription
                                                                   ?: @"Failed to get suggestions"];
                         return;
                       }
                       response.statusCode = HttpStatusOK;
                       [response setJsonBody:result ?: @{@"actors" : @[], @"cursor" : [NSNull null]}];
                     }];
}

@end
