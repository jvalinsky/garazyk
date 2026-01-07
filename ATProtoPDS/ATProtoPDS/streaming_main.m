#import <Foundation/Foundation.h>
#import "PDSController.h"
#import "Database/PDSDatabase.h"
#import "Sync/SubscribeReposHandler.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Starting ATProto PDS with WebSocket streaming...");

        // Initialize database
        NSURL *dbURL = [NSURL fileURLWithPath:@"test_streaming.db"];
        PDSDatabase *database = [PDSDatabase databaseAtURL:dbURL];
        
        NSError *dbError = nil;
        if (![database openWithError:&dbError]) {
            NSLog(@"Failed to open database: %@", dbError);
            return 1;
        }

        // Initialize PDS controller
        PDSController *controller = [[PDSController alloc] initWithDatabase:database];

        // Start the server (which includes the WebSocket streaming)
        [controller startServer];

        // Keep the server running
        [[NSRunLoop mainRunLoop] run];

        return 0;
    }
}