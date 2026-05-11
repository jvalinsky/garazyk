// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Video/VideoPDSAuthProvider.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

@implementation VideoPDSAuthProvider

- (instancetype)initWithJwtMinter:(JWTMinter *)jwtMinter
                   adminController:(nullable id<PDSAdminController>)adminController {
    self = [super init];
    if (self) {
        _jwtMinter = jwtMinter;
        _adminController = adminController;
    }
    return self;
}

- (nullable NSString *)authenticateRequest:(HttpRequest *)request
                                   response:(HttpResponse *)response {
    NSString *authHeader = [request headerForKey:@"Authorization"];
    return [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                          jwtMinter:self.jwtMinter
                                    adminController:self.adminController
                                            request:request
                                           response:response];
}

@end
