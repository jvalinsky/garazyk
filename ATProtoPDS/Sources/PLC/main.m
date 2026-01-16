#import <Foundation/Foundation.h>
#import "PLC/PLCServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCAuditor.h"

void print_usage(const char *executable_name) {
    printf("Usage: %s [options]\n\n", executable_name);
    printf("A standalone PLC server for ATProto.\n\n");
    printf("Options:\n");
    printf("  --port <number>    Port to listen on (default: 2582)\n");
    printf("  --database <path>  Path to SQLite database (optional, defaults to mock store)\n");
    printf("  --help, -h         Show help information\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUInteger port = 2582;
        NSString *dbPath = nil;

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--port"]) {
                if (i + 1 < argc) {
                    port = (NSUInteger)[[NSString stringWithUTF8String:argv[++i]] integerValue];
                }
            } else if ([arg isEqualToString:@"--database"]) {
                if (i + 1 < argc) {
                    dbPath = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                print_usage(argv[0]);
                return 0;
            }
        }

        // For now, we only have PLCMockStore.
        // If SQLiteStore is implemented later, we can use it here if dbPath is provided.
        id<PLCStore> store = [[PLCMockStore alloc] init];
        PLCAuditor *auditor = [[PLCAuditor alloc] initWithStore:store];
        PLCServer *server = [[PLCServer alloc] initWithStore:store auditor:auditor port:port];

        NSError *error = nil;
        if (![server startWithError:&error]) {
            fprintf(stderr, "Failed to start PLC server: %s\n", [error.localizedDescription UTF8String]);
            return 1;
        }

        printf("PLC server listening on port %lu\n", (unsigned long)port);

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
