// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcRoutePackRegistrar.h"

#import "Debug/GZLogger.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePack.h"
#import "Network/XrpcRoutePackServices.h"

@implementation XrpcRoutePackRegistrar

+ (void)registerRoutePacks:(NSArray<Class> *)routePackClasses
                dispatcher:(XrpcDispatcher *)dispatcher
                  services:(id<XrpcRoutePackServices>)services {
  for (Class routePackClass in routePackClasses) {
    if (![(id)routePackClass conformsToProtocol:@protocol(XrpcRoutePack)]) {
      GZ_LOG_WARN(@"Skipping XRPC route pack %@: does not conform to XrpcRoutePack",
                  routePackClass);
      continue;
    }
    if ([routePackClass respondsToSelector:@selector(routePackIdentifier)]) {
      GZ_LOG_DEBUG(@"Registering XRPC route pack %@ (%@)",
                   routePackClass,
                   [routePackClass routePackIdentifier]);
    } else {
      GZ_LOG_DEBUG(@"Registering XRPC route pack %@", routePackClass);
    }
    [routePackClass registerWithDispatcher:dispatcher services:services];
  }
}

@end
