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
