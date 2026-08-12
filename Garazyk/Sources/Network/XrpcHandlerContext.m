// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcHandlerContext.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Auth/Crypto/JWT.h"
#import "Admin/PDSAdminController.h"
#import "Chat/Server/ChatAuthManager.h"

@implementation ATProtoXrpcHandlerContext

- (instancetype)initWithRequest:(ATProtoHttpRequest *)request
                       response:(ATProtoHttpResponse *)response
                       services:(id<XrpcRoutePackServices>)services {
  self = [super init];
  if (self) {
    _request = request;
    _response = response;
    _services = services;
  }
  return self;
}

- (BOOL)requireAuthentication {
  return [self requireAuthenticatedDID:NULL];
}

- (BOOL)requireAuthenticatedDID:(NSString **)did {
  NSString *authHeader = [_request headerForKey:@"Authorization"];
  if (authHeader.length == 0) {
    [ATProtoXrpcErrorHelper setAuthenticationError:_response
                                    message:@"Authentication required"];
    return NO;
  }

  ATProtoJWTMinter *jwtMinter = _services.jwtMinter;
  id<PDSAdminController> adminController = _services.adminController;
  if (jwtMinter && adminController) {
    NSString *resolvedDID =
        [ATProtoXrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                       jwtMinter:jwtMinter
                                 adminController:adminController
                                         request:_request
                                        response:_response];
    if (resolvedDID.length == 0) {
      return NO;
    }
    _authenticatedDID = resolvedDID;
    if (did) {
      *did = resolvedDID;
    }
    return YES;
  }

  // No jwtMinter/adminController — this is a standalone service (e.g., chat).
  // Use PDSChatAuthManager to validate the service auth ATProtoJWT.
  NSString *methodNSID = _request.pathParameters[@"method"] ?: @"";
  NSString *resolvedDID = [[PDSChatAuthManager sharedManager] authenticateRequest:_request
                                                                      response:_response
                                                                 expectedMethod:methodNSID.length > 0 ? methodNSID : nil];
  if (!resolvedDID) {
    return NO;
  }
  _authenticatedDID = resolvedDID;
  if (did) {
    *did = resolvedDID;
  }
  return YES;
}

@end
