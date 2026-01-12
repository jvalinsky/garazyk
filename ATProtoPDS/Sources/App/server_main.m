#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "PDSController.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Database/PDSDatabase.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"ATProto PDS Starting...");

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
            NSLog(@"Failed to start server: %@", error);
            return 1;
        }

        NSLog(@"ATProto PDS running on port %hu", server.port);
        NSLog(@"XRPC endpoint: /xrpc/*");
        NSLog(@"Press Ctrl+C to stop");

        CFRunLoopRun();
    }
    return 0;
}
