#import "Network/PDSHttpRelayAPIRoutePack.h"

#import "Debug/PDSLogger.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Sync/Relay/RelayAPIHandler.h"

@implementation PDSHttpRelayAPIRoutePack

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
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"GET"
              path:@"/api/relay/upstreams/reconnect-all"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"POST"
              path:@"/api/relay/upstreams/reconnect-all"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"GET"
              path:@"/api/relay/upstreams/disconnect-all"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"POST"
              path:@"/api/relay/upstreams/disconnect-all"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"GET"
              path:@"/api/relay/health"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  [server addRoute:@"*"
              path:@"/api/relay/upstreams/*"
           handler:^(HttpRequest *request, HttpResponse *response) {
              [relayAPIHandler handleRequest:request response:response];
            }];

  PDS_LOG_DEBUG(@"PDSHttpRelayAPIRoutePack: Relay API routes registered");
}

@end
