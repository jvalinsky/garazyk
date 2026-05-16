// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcRoutePackServices.h"

#import "AppView/Services/AgeAssuranceService.h"
#import "App/ATProtoServiceConfiguration.h"
#import "Auth/JWT.h"
#import "Database/Service/ServiceDatabases.h"
#import "Network/RateLimiter.h"
#import "Network/XrpcHandler.h"
#import "Admin/PDSAdminController.h"

@implementation XrpcRoutePackServiceBag

- (instancetype)initWithDispatcher:(XrpcDispatcher *)dispatcher
                         jwtMinter:(JWTMinter *)jwtMinter
                   adminController:(id<PDSAdminController>)adminController
                      configuration:(ATProtoServiceConfiguration *)configuration
                        adminSecret:(NSString *)adminSecret
                  serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                  userDatabasePool:(PDSDatabasePool *)userDatabasePool
                        rateLimiter:(RateLimiter *)rateLimiter {
  self = [super init];
  if (self) {
    _dispatcher = dispatcher;
    _jwtMinter = jwtMinter;
    _adminController = adminController;
    _configuration = configuration;
    _adminSecret = [adminSecret copy];
    _serviceDatabases = serviceDatabases;
    _userDatabasePool = userDatabasePool;
    _rateLimiter = rateLimiter;
  }
  return self;
}

@end
