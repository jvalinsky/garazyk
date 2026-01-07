#import <Foundation/Foundation.h>
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"=== HTTP Server Test ===\n");

        HttpServer *server = [HttpServer serverWithPort:8080];
        NSLog(@"Created HTTP server on port 8080");

        [server addHandlerForPath:@"/" handler:^(HttpRequest *request, HttpResponse *response) {
            NSLog(@"Received request: %@ %@", request.methodString, request.path);
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"message": @"Hello from ATProto PDS!", @"status": @"running"}];
        }];

        [server addHandlerForPath:@"/health" handler:^(HttpRequest *request, HttpResponse *response) {
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{@"status": @"healthy"}];
        }];

        XrpcDispatcher *xrpc = [XrpcDispatcher sharedDispatcher];

        [xrpc registerComAtprotoServerCreateSession:^(HttpRequest *request, HttpResponse *response) {
            NSDictionary *params = request.jsonBody ?: @{};
            NSString *identifier = params[@"identifier"] ?: params[@"email"] ?: @"unknown";
            NSLog(@"Create session for: %@", identifier);
            response.statusCode = HttpStatusOK;
            [response setJsonBody:@{
                @"session": @{
                    @"did": @"did:web:localhost",
                    @"handle": @"localhost",
                    @"accessJwt": @"mock-access-jwt",
                    @"refreshJwt": @"mock-refresh-jwt"
                }
            }];
        }];

        [server addHandlerForPath:@"/xrpc/*" handler:^(HttpRequest *request, HttpResponse *response) {
            [xrpc handleRequest:request response:response];
        }];

        NSError *error = nil;
        if ([server startWithError:&error]) {
            NSLog(@"✅ HTTP server started successfully!");
            NSLog(@"Listening on http://localhost:8080");
            NSLog(@"\nEndpoints:");
            NSLog(@"  GET  /              - Server info");
            NSLog(@"  GET  /health        - Health check");
            NSLog(@"  POST /xrpc/com.atproto.server.createSession - Create session");
            NSLog(@"\nPress Ctrl+C to stop...\n");

            dispatch_main();
        } else {
            NSLog(@"❌ Failed to start server: %@", error);
            return 1;
        }
    }
    return 0;
}
