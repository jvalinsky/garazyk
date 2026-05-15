// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcHandlerContext.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcErrorHelper.h"
#import "Network/XrpcRoutePackServices.h"
#import "Auth/JWT.h"
#import "Admin/PDSAdminController.h"

@implementation XrpcHandlerContext

- (instancetype)initWithRequest:(HttpRequest *)request
                       response:(HttpResponse *)response
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
    [XrpcErrorHelper setAuthenticationError:_response
                                    message:@"Authentication required"];
    return NO;
  }

  JWTMinter *jwtMinter = _services.jwtMinter;
  id<PDSAdminController> adminController = _services.adminController;
  if (jwtMinter && adminController) {
    NSString *resolvedDID =
        [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
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

  if (did) {
    *did = nil;
  }
  return YES;
}

@end
