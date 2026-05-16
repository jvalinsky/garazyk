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
#import "Auth/PDSSecondFactorService.h"
#import "Auth/WebAuthnRegistrationHandler.h"
#import "Database/PDSDatabase.h"
#import "Database/Service/ServiceDatabases.h"
#import "Debug/GZLogger.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Services/PDS/PDSAccountService.h"

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

  id<PDSAccountService> accountService = nil;
  if (application.accountService) {
    oauthHandler.accountService = application.accountService;
    accountService = application.accountService;
  } else if (controller.accountService) {
    oauthHandler.accountService = controller.accountService;
    accountService = controller.accountService;
  }
  [oauthHandler registerRoutesWithServer:server];
  GZ_LOG_DEBUG(@"ATProtoHttpOAuthRoutePack: OAuth routes registered");

  [server addRoute:@"POST"
              path:@"/auth/2fa/webauthn/begin"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSDictionary *body = request.jsonBody ?: @{};
             NSString *identifier = body[@"identifier"];
             NSString *password = body[@"password"];
             if (identifier.length == 0 || password.length == 0) {
               response.statusCode = HttpStatusBadRequest;
               [response setJsonBody:@{
                 @"error": @"InvalidRequest",
                 @"message": @"Missing identifier or password"
               }];
               return;
             }
             if (![accountService respondsToSelector:@selector(beginWebAuthnSecondFactorForIdentifier:password:error:)]) {
               response.statusCode = HttpStatusInternalServerError;
               [response setJsonBody:@{
                 @"error": @"ServiceUnavailable",
                 @"message": @"Second-factor service is unavailable"
               }];
               return;
             }

             NSError *error = nil;
             NSDictionary *result =
                 [(PDSAccountService *)accountService beginWebAuthnSecondFactorForIdentifier:identifier
                                                                                    password:password
                                                                                       error:&error];
             if (!result) {
               response.statusCode = HttpStatusUnauthorized;
               [response setJsonBody:@{
                 @"error": @"AuthenticationFailed",
                 @"message": error.localizedDescription ?: @"Unable to begin WebAuthn login"
               }];
               return;
             }

             [response setHeader:@"no-store" forKey:@"Cache-Control"];
             [response setHeader:@"no-cache" forKey:@"Pragma"];
             response.statusCode = HttpStatusOK;
             [response setJsonBody:result];
           }];

  [server addRoute:@"POST"
              path:@"/auth/2fa/webauthn/complete"
           handler:^(HttpRequest *request, HttpResponse *response) {
             NSDictionary *body = request.jsonBody ?: @{};
             NSString *identifier = body[@"identifier"];
             NSString *sessionID = body[@"sessionId"];
             NSDictionary *assertion = body[@"assertion"];
             if (identifier.length == 0 || sessionID.length == 0 ||
                 ![assertion isKindOfClass:[NSDictionary class]]) {
               response.statusCode = HttpStatusBadRequest;
               [response setJsonBody:@{
                 @"error": @"InvalidRequest",
                 @"message": @"Missing identifier, sessionId, or assertion"
               }];
               return;
             }
             if (![accountService respondsToSelector:@selector(completeWebAuthnSecondFactorForIdentifier:sessionID:assertion:error:)]) {
               response.statusCode = HttpStatusInternalServerError;
               [response setJsonBody:@{
                 @"error": @"ServiceUnavailable",
                 @"message": @"Second-factor service is unavailable"
               }];
               return;
             }

             NSError *error = nil;
             NSString *authFactorToken =
                 [(PDSAccountService *)accountService completeWebAuthnSecondFactorForIdentifier:identifier
                                                                                      sessionID:sessionID
                                                                                      assertion:assertion
                                                                                         error:&error];
             if (authFactorToken.length == 0) {
               response.statusCode = HttpStatusUnauthorized;
               [response setJsonBody:@{
                 @"error": @"AuthenticationFailed",
                 @"message": error.localizedDescription ?: @"Unable to complete WebAuthn login"
               }];
               return;
             }

             [response setHeader:@"no-store" forKey:@"Cache-Control"];
             [response setHeader:@"no-cache" forKey:@"Pragma"];
             response.statusCode = HttpStatusOK;
             [response setJsonBody:@{@"authFactorToken": authFactorToken}];
           }];

  WebAuthnRegistrationHandler *webauthnHandler =
      [[WebAuthnRegistrationHandler alloc] initWithDatabase:db
                                                serverOrigin:config.issuer];
  [webauthnHandler registerRoutesWithServer:server];
  GZ_LOG_DEBUG(@"ATProtoHttpOAuthRoutePack: WebAuthn routes registered");
}

@end
