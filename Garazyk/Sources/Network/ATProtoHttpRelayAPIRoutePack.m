// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoHttpRelayAPIRoutePack.m

 @abstract Registers relay API HTTP routes for relay-facing operational and sync endpoints.

 @discussion Maps relay API paths into the HTTP router and delegates execution to relay/runtime components. Maintains route namespace and registration concerns separate from relay business logic.
 */

#import "Network/ATProtoHttpRelayAPIRoutePack.h"

#import "Debug/GZLogger.h"
#import "Admin/PDSAdminAuth.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Sync/Relay/RelayAPIHandler.h"

static BOOL RelayAPIAuthorizeMutation(HttpRequest *request,
                                      HttpResponse *response) {
  NSError *authError = nil;
  if ([[PDSAdminAuth sharedAuth] authenticateHeaders:request.headers
                                               error:&authError]) {
    return YES;
  }

  NSInteger statusCode = authError.code;
  if (statusCode < 400 || statusCode > 599) {
    statusCode = HttpStatusUnauthorized;
  }
  response.statusCode = statusCode;
  [response setJsonBody:@{
    @"error": statusCode == HttpStatusForbidden ? @"Forbidden" : @"Unauthorized",
    @"message": authError.localizedDescription ?: @"Admin authentication required"
  }];
  return NO;
}

@implementation ATProtoHttpRelayAPIRoutePack

+ (void)registerRoutesWithServer:(HttpServer *)server {
  RelayAPIHandler *relayAPIHandler = [RelayAPIHandler sharedHandler];

  [server addRoute:@"GET"
              path:@"/api/relay/metrics"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"GET"
              path:@"/api/relay/capabilities"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"GET"
              path:@"/api/relay/upstreams"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"POST"
              path:@"/api/relay/upstreams"
           handler:^(HttpRequest *request, HttpResponse *response) {
              if (!RelayAPIAuthorizeMutation(request, response)) return;
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"POST"
              path:@"/api/relay/upstreams/reconnect-all"
           handler:^(HttpRequest *request, HttpResponse *response) {
              if (!RelayAPIAuthorizeMutation(request, response)) return;
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"POST"
              path:@"/api/relay/upstreams/disconnect-all"
           handler:^(HttpRequest *request, HttpResponse *response) {
              if (!RelayAPIAuthorizeMutation(request, response)) return;
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"GET"
              path:@"/api/relay/health"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"POST"
              path:@"/api/relay/requestCrawl"
           handler:^(HttpRequest *request, HttpResponse *response) {
              if (!RelayAPIAuthorizeMutation(request, response)) return;
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"*"
              path:@"/api/relay/upstreams/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
              if (request.method != HttpMethodGET &&
                  !RelayAPIAuthorizeMutation(request, response)) return;
              [relayAPIHandler handleRequest:request response:response];
            }];

  GZ_LOG_DEBUG(@"ATProtoHttpRelayAPIRoutePack: Relay API routes registered");
}

@end
