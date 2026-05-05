#import "Network/XrpcAppBskyBookmarksPack.h"
#import "Network/XrpcAppBskyGraphHelpers.h"
#import "AppView/Services/BookmarkService.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcHandler.h"

@implementation XrpcAppBskyBookmarksPack

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
               bookmarkService:(BookmarkService *)bookmarkService
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController {
  [dispatcher registerAppBskyBookmarkGetBookmarks:^(HttpRequest *request,
                                                    HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
      [XrpcErrorHelper setAuthenticationError:response
                                      message:@"Authentication required"];
      return;
    }

    NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                        jwtMinter:jwtMinter
                                                  adminController:adminController
                                                          request:request
                                                         response:response];
    if (!actorDID) {
      return;
    }

    NSInteger limit = 50;
    if (!XrpcParseLimit(request.queryParams[@"limit"], &limit, 1, 100,
                        response)) {
      return;
    }

    NSString *cursor = [request queryParamForKey:@"cursor"];

    NSError *error = nil;
    NSDictionary *result = [bookmarkService getBookmarksForActor:actorDID
                                                           limit:limit
                                                          cursor:cursor
                                                           error:&error];
    if (error) {
      [XrpcErrorHelper setInternalServerError:response
                                      message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];

  [dispatcher registerAppBskyBookmarkCreateBookmark:^(HttpRequest *request,
                                                      HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
      [XrpcErrorHelper setAuthenticationError:response
                                      message:@"Authentication required"];
      return;
    }

    NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                        jwtMinter:jwtMinter
                                                  adminController:adminController
                                                          request:request
                                                         response:response];
    if (!actorDID) {
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
      [XrpcErrorHelper setInternalServerError:response
                                      message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];

  [dispatcher registerAppBskyBookmarkDeleteBookmark:^(HttpRequest *request,
                                                      HttpResponse *response) {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    if (!authHeader) {
      [XrpcErrorHelper setAuthenticationError:response
                                      message:@"Authentication required"];
      return;
    }

    NSString *actorDID = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                        jwtMinter:jwtMinter
                                                  adminController:adminController
                                                          request:request
                                                         response:response];
    if (!actorDID) {
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
      [XrpcErrorHelper setInternalServerError:response
                                      message:error.localizedDescription];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:@{}];
  }];
}

@end
