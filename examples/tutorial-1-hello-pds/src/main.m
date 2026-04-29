#import <Foundation/Foundation.h>

// Import PDS headers
#import "App/PDSApplication.h"
#import "App/PDSConfiguration.h"
#import "Network/HttpServer.h"
#import "Core/NSDateFormatter+ATProto.h"

/*!
 @file main.m
 
 @abstract Tutorial 1: Hello PDS - Minimal PDS Example
 
 @discussion This example demonstrates:
 - Creating a PDSApplication instance
 - Configuring the server
 - Starting the HTTP server
 - Handling a basic XRPC request
 
 The server will respond to:
 - GET http://localhost:2583/xrpc/com.atproto.server.describeServer
 
 Expected output:
 {
   "did": "did:web:localhost:2583",
   "availableUserDomains": ["localhost"],
   "inviteCodeRequired": false,
   "phoneNumberRequired": false
 }
 */

int main(int argc, char *argv[]) {
    @autoreleasepool {
#ifdef LINUX
        // On Linux/GNUstep, verify critical categories are loaded
        if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) {
            fprintf(stderr, "FATAL: Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings.\n");
            return 1;
        }
#endif
        // 1. Create configuration
        PDSConfiguration *config = [[PDSConfiguration alloc] init];
        
        // Set basic server configuration
        config.serverPort = 2583;
        config.issuer = @"did:web:localhost:2583";
        
        // Use in-memory database for this example (no persistence)
        // In production, use a real data directory
        NSString *dataDir = [NSTemporaryDirectory() 
            stringByAppendingPathComponent:@"hello-pds"];
        
        // 2. Initialize PDS application
        NSError *error = nil;
        PDSApplication *app = [[PDSApplication alloc]
            initWithDataDirectory:dataDir
                           error:&error];
        
        if (!app) {
            NSLog(@"ERROR: Failed to initialize PDS: %@", error);
            return 1;
        }
        
        NSLog(@"✓ PDS initialized");
        
        // 3. Start the HTTP server
        if (![app startWithError:&error]) {
            NSLog(@"ERROR: Failed to start server: %@", error);
            return 1;
        }
        
        NSLog(@"✓ Server started on port %lu", (unsigned long)config.serverPort);
        NSLog(@"");
        NSLog(@"Test the server with:");
        NSLog(@"  curl http://localhost:2583/xrpc/com.atproto.server.describeServer");
        NSLog(@"");
        NSLog(@"Press Ctrl+C to stop");
        NSLog(@"");
        
        // 4. Keep the server running
        [[NSRunLoop mainRunLoop] run];
        
        // Cleanup (unreachable unless interrupted)
        [app stop];
    }
    
    return 0;
}
