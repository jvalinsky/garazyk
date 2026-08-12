// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcAppBskyBookmarksPack.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "AppView/Services/BookmarkService.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcHandlerContext.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Auth/AuthClaimTypeCheck.h"

@implementation ATProtoXrpcAppBskyBookmarksPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.bookmark";
}

+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
               bookmarkService:(PDSBookmarkService *)bookmarkService
                     jwtMinter:(ATProtoJWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
  ATProtoXrpcRoutePackServiceBag *services =
      [[ATProtoXrpcRoutePackServiceBag alloc] initWithDispatcher:dispatcher
                                                jwtMinter:jwtMinter
                                          adminController:adminController
                                             configuration:nil
                                               adminSecret:nil
                                         serviceDatabases:nil
                                         userDatabasePool:nil
                                               rateLimiter:nil];
  services.bookmarkService = bookmarkService;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  PDSBookmarkService *bookmarkService = services.bookmarkService;
  if (!bookmarkService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_bookmark_getBookmarks handler:^(ATProtoHttpRequest *request,
                                                    ATProtoHttpResponse *response) {
    ATProtoXrpcHandlerContext *context =
        [[ATProtoXrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSInteger limit = 50;
    if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100, response)) {
      return;
    }

    NSString *cursor = [request queryParamForKey:@"cursor"];
    NSError *error = nil;
    NSDictionary *result = [bookmarkService getBookmarksForActor:actorDID
                                                           limit:limit
                                                          cursor:cursor
                                                           error:&error];
    if (error) {
      [ATProtoXrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_bookmark_createBookmark handler:^(ATProtoHttpRequest *request,
                                                      ATProtoHttpResponse *response) {
    ATProtoXrpcHandlerContext *context =
        [[ATProtoXrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSDictionary *body = [request jsonBody];
    BOOL typeMismatch = NO;
    NSString *subjectURI = AuthTypedValue(body, @"uri", [NSString class], &typeMismatch);
    NSString *subjectCID = AuthTypedValue(body, @"cid", [NSString class], &typeMismatch);
    if (typeMismatch) {
      [ATProtoXrpcErrorHelper setValidationError:response message:@"Request field has wrong type"];
      return;
    }
    if (!subjectURI) {
      [ATProtoXrpcErrorHelper setValidationError:response message:@"Missing uri"];
      return;
    }

    NSString *now = [NSDateFormatter atproto_stringFromDate:[NSDate date]];
    NSError *error = nil;
    BOOL success = [bookmarkService indexBookmarkWithDid:actorDID
                                              subjectURI:subjectURI
                                              subjectCID:subjectCID
                                               createdAt:now
                                                   error:&error];
    if (!success) {
      [ATProtoXrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_bookmark_deleteBookmark handler:^(ATProtoHttpRequest *request,
                                                      ATProtoHttpResponse *response) {
    ATProtoXrpcHandlerContext *context =
        [[ATProtoXrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSDictionary *body = [request jsonBody];
    BOOL typeMismatch = NO;
    NSString *subjectURI = AuthTypedValue(body, @"uri", [NSString class], &typeMismatch);
    if (typeMismatch) {
      [ATProtoXrpcErrorHelper setValidationError:response message:@"Request field has wrong type"];
      return;
    }
    if (!subjectURI) {
      [ATProtoXrpcErrorHelper setValidationError:response message:@"Missing uri"];
      return;
    }

    NSError *error = nil;
    BOOL success = [bookmarkService unindexBookmarkWithSubjectURI:subjectURI
                                                               did:actorDID
                                                             error:&error];
    if (!success) {
      [ATProtoXrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];
}

@end
