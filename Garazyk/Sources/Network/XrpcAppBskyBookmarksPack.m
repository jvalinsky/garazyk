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

@implementation XrpcAppBskyBookmarksPack

+ (NSString *)routePackIdentifier {
  return @"app.bsky.bookmark";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               bookmarkService:(BookmarkService *)bookmarkService
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
  services.bookmarkService = bookmarkService;
  [self registerWithDispatcher:dispatcher services:services];
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  BookmarkService *bookmarkService = services.bookmarkService;
  if (!bookmarkService) {
    return;
  }

  id<XrpcRoutePackServices> resolvedServices = services;

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_bookmark_getBookmarks handler:^(HttpRequest *request,
                                                    HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request
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
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_bookmark_createBookmark handler:^(HttpRequest *request,
                                                      HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSDictionary *body = [request jsonBody];
    NSString *subjectURI = body[@"uri"];
    NSString *subjectCID = body[@"cid"];
    if (!subjectURI) {
      [XrpcErrorHelper setValidationError:response message:@"Missing uri"];
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
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  [dispatcher registerMethod:kGZXrpcNSID_app_bsky_bookmark_deleteBookmark handler:^(HttpRequest *request,
                                                      HttpResponse *response) {
    XrpcHandlerContext *context =
        [[XrpcHandlerContext alloc] initWithRequest:request
                                           response:response
                                           services:resolvedServices];
    NSString *actorDID = nil;
    if (![context requireAuthenticatedDID:&actorDID]) {
      return;
    }

    NSDictionary *body = [request jsonBody];
    NSString *subjectURI = body[@"uri"];
    if (!subjectURI) {
      [XrpcErrorHelper setValidationError:response message:@"Missing uri"];
      return;
    }

    NSError *error = nil;
    BOOL success = [bookmarkService unindexBookmarkWithSubjectURI:subjectURI
                                                               did:actorDID
                                                             error:&error];
    if (!success) {
      [XrpcErrorHelper setInternalServerError:response message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];
}

@end
