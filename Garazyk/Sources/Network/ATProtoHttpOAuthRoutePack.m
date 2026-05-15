// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpOAuthRoutePack.m

 @abstract Registers core OAuth-related HTTP routes for authentication protocol endpoints.

 @discussion Wires OAuth endpoint paths into server routing and delegates implementation to auth/runtime handlers. Establishes endpoint exposure and integration points without implementing token/state logic directly.
 */

#import "Network/ATProtoHttpOAuthRoutePack.h"

#import "App/PDSApplication.h"
#import "App/ATProtoServiceConfiguration.h"
#import "App/PDSController.h"
#import "Auth/JWT.h"
#import "Auth/OAuth2.h"
#import "Auth/OAuth2Handler.h"
#import "Auth/WebAuthnRegistrationHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
#import "Network/HttpServer.h"

@implementation ATProtoHttpOAuthRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server
                serviceDatabases:(nullable PDSServiceDatabases *)serviceDatabases
                       jwtMinter:(nullable JWTMinter *)jwtMinter
                   dataDirectory:(nullable NSString *)dataDirectory
                     application:(nullable PDSApplication *)application
                      controller:(nullable PDSController *)controller {
  if (!serviceDatabases || !jwtMinter) {
    GZ_LOG_WARN(@"ATProtoHttpOAuthRoutePack: OAuth routes not registered - missing "
                 @"serviceDatabases or jwtMinter");
    return;
  }

  NSError *dbError = nil;
  PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:&dbError];
  if (!db) {
    GZ_LOG_WARN(@"ATProtoHttpOAuthRoutePack: OAuth routes not registered - could "
                 @"not get service database: %@",
                 dbError);
    return;
  }

  OAuth2Handler *oauthHandler = [[OAuth2Handler alloc] initWithDatabase:db];
  oauthHandler.minter = jwtMinter;
  oauthHandler.dataDirectory = dataDirectory;

  ATProtoServiceConfiguration *config = [ATProtoServiceConfiguration sharedConfiguration];
  oauthHandler.oauthServer.issuer = config.issuer;

  if (application.accountService) {
    oauthHandler.accountService = application.accountService;
  } else if (controller.accountService) {
    oauthHandler.accountService = controller.accountService;
  }
  [oauthHandler registerRoutesWithServer:server];
  GZ_LOG_DEBUG(@"ATProtoHttpOAuthRoutePack: OAuth routes registered");

  WebAuthnRegistrationHandler *webauthnHandler =
      [[WebAuthnRegistrationHandler alloc] initWithDatabase:db
                                                serverOrigin:config.issuer];
  [webauthnHandler registerRoutesWithServer:server];
  GZ_LOG_DEBUG(@"ATProtoHttpOAuthRoutePack: WebAuthn routes registered");
}

@end
