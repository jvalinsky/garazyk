// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpNodeInfoRoutePack.m

 @abstract Registers HTTP routes that expose node information and diagnostics views.

 @discussion Configures node-info route bindings for server/runtime diagnostics surfaces and delegates request handling to node-info components. Defines registration boundaries, not diagnostic data computation.
 */

#import "Network/ATProtoHttpNodeInfoRoutePack.h"

#import "App/NodeInfo/NodeInfoHandler.h"
#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"
#import "Network/HttpServer.h"

@implementation ATProtoHttpNodeInfoRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                          issuer:(nullable NSString *)issuer
                            port:(NSUInteger)port
                   configuration:(nullable ATProtoServiceConfiguration *)configuration
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller {
  NodeInfoHandler *nodeInfoHandler = [NodeInfoHandler sharedHandler];

  NSString *resolvedIssuer = issuer;
  if (resolvedIssuer.length == 0 && configuration) {
    resolvedIssuer = [configuration canonicalIssuerWithPortHint:port];
  }
  if (resolvedIssuer.length == 0) {
    resolvedIssuer = [[ATProtoServiceConfiguration sharedConfiguration]
        canonicalIssuerWithPortHint:port];
  }

  [nodeInfoHandler setIssuer:resolvedIssuer];
  if (application.accountService) {
    [nodeInfoHandler setAccountService:application.accountService];
  } else if (controller.accountService) {
    [nodeInfoHandler setAccountService:controller.accountService];
  }
  [nodeInfoHandler setConfigured];
  [nodeInfoHandler registerRoutesWithServer:server];

  GZ_LOG_DEBUG(@"ATProtoHttpNodeInfoRoutePack: NodeInfo routes registered");
}

@end
