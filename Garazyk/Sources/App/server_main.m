// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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
#import "App/ATProtoServiceConfiguration.h"
#import "Debug/GZLogger.h"
#import "Network/XrpcMethodRegistry.h"
#import "Database/PDSDatabase.h"
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Compat/PlatformShims/CrashReporting/PDSCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/PDSSignalManager.h"

int main(int argc, const char * argv[]) {
    [[PDSSignalManager sharedManager] installIgnoredSignals];
    [PDSCrashReporter installCrashHandlersWithExecutableName:"kaszlak-headless"];
    @autoreleasepool {
        GZ_LOG_INFO_C(GZLogComponentCore, @"ATProto PDS Starting...");

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

        // /xrpc/_health is handled by xrpcDispatcher via XrpcServerPack
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
            GZ_LOG_ERROR_C(GZLogComponentCore, @"Failed to start server: %@", error);
            return 1;
        }

        GZ_LOG_INFO_C(GZLogComponentCore, @"ATProto PDS running on port %hu", server.port);
        GZ_LOG_INFO_C(GZLogComponentCore, @"XRPC endpoint: /xrpc/*");
        GZ_LOG_INFO_C(GZLogComponentCore, @"Press Ctrl+C to stop");

        // Register signal handlers for graceful shutdown
        __block volatile sig_atomic_t shouldExit = 0;
        [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGINT handler:^(int sig) {
            shouldExit = 1;
            GZ_LOG_SERVICE_INFO(@"Received SIGINT — shutting down");
        }];
        [[PDSSignalManager sharedManager] registerHandlerForSignal:SIGTERM handler:^(int sig) {
            shouldExit = 1;
            GZ_LOG_SERVICE_INFO(@"Received SIGTERM — shutting down");
        }];

        // Drain the run loop instead of CFRunLoopRun() so we can check shouldExit
        while (!shouldExit && server.running) {
            @autoreleasepool {
                [[NSRunLoop mainRunLoop]
                     runMode:NSDefaultRunLoopMode
                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
            }
        }

        [server stop];
        GZ_LOG_INFO_C(GZLogComponentCore, @"ATProto PDS stopped");
    }
    return 0;
}
