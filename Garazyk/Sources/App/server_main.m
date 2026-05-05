/*!
 @file server_main.m

 @abstract Command-line server entry point for ATProto PDS.

 @discussion Provides a non-GUI entry point for running the PDS as a standalone
 server. Initializes the controller and HTTP server, registers XRPC methods,
 and runs the main run loop. Used for headless or container deployments.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "PDSController.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "App/PDSConfiguration.h"
#import "Debug/PDSLogger.h"
#import "Network/XrpcMethodRegistry.h"
#import "Database/PDSDatabase.h"
#import "Database/Monitoring/PDSHealthCheck.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        PDS_LOG_INFO_C(PDSLogComponentCore, @"ATProto PDS Starting...");

        NSError *error = nil;
        NSString *dataDirectory = @"/tmp/atproto_pds_data";

        PDSController *controller = [[PDSController alloc] initWithDirectory:dataDirectory
                                                           serviceMaxSize:100
                                                         userDatabaseSize:30000];
        HttpServer *server = [HttpServer serverWithPort:2583];
        XrpcDispatcher *xrpcDispatcher = [XrpcDispatcher sharedDispatcher];

        [XrpcMethodRegistry registerMethodsWithDispatcher:xrpcDispatcher controller:controller];

        [server addHandlerForPath:@"/xrpc" handler:^(HttpRequest *request, HttpResponse *response) {
            [xrpcDispatcher handleRequest:request response:response];
        }];

        [server addHandlerForPath:@"/xrpc/" handler:^(HttpRequest *request, HttpResponse *response) {
            [xrpcDispatcher handleRequest:request response:response];
        }];

        [server addHandlerForPath:@"/_health" handler:^(HttpRequest *request, HttpResponse *response) {
            NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
            response.statusCode = [health[@"status"] isEqualToString:@"critical"] ? 503 : 200;
            [response setJsonBody:health];
        }];

        // /xrpc/_health is handled by xrpcDispatcher via XrpcServerMethods
        // We can keep a direct handler for better performance or just let it fall through.
        // Let's make it consistent.
        [server addHandlerForPath:@"/xrpc/_health" handler:^(HttpRequest *request, HttpResponse *response) {
            NSDictionary *health = [[PDSHealthCheck sharedInstance] performHealthCheck];
            response.statusCode = [health[@"status"] isEqualToString:@"critical"] ? 503 : 200;
            [response setJsonBody:health];
        }];

        [server addHandlerForPath:@"/robots.txt" handler:^(HttpRequest *request, HttpResponse *response) {
            response.statusCode = HttpStatusOK;
            response.contentType = @"text/plain";
            [response setBodyString:@"User-agent: *\nDisallow: /"];
        }];

        [server addHandlerForPath:@"/account/" handler:^(HttpRequest *request, HttpResponse *response) {
            response.statusCode = HttpStatusOK;
            response.contentType = @"text/html";
            NSString *html = @"<!DOCTYPE html><html><head><title>ATProto Account</title></head><body><h1>Account Management</h1><p>Account web UI coming soon.</p></body></html>";
            [response setBodyString:html];
        }];

        if (![server startWithError:&error]) {
            PDS_LOG_ERROR_C(PDSLogComponentCore, @"Failed to start server: %@", error);
            return 1;
        }

        PDS_LOG_INFO_C(PDSLogComponentCore, @"ATProto PDS running on port %hu", server.port);
        PDS_LOG_INFO_C(PDSLogComponentCore, @"XRPC endpoint: /xrpc/*");
        PDS_LOG_INFO_C(PDSLogComponentCore, @"Press Ctrl+C to stop");

        CFRunLoopRun();
    }
    return 0;
}
