#import <Foundation/Foundation.h>
#import "PDSController.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcMethodRegistry.h"
#import "Database/PDSDatabase.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"ATProto PDS Starting...");

        NSError *error = nil;
        NSURL *dbURL = [[NSURL fileURLWithPath:@"/tmp/atproto_pds.db"] URLByStandardizingPath];
        PDSDatabase *database = [PDSDatabase databaseAtURL:dbURL];

        if (![database openWithError:&error]) {
            NSLog(@"Failed to open database: %@", error);
            return 1;
        }

        PDSController *controller = [[PDSController alloc] initWithDatabase:database];
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
