/*!
 @file main.m
 @brief Entry point for the Syrena Chat standalone service.
 */

#import <Foundation/Foundation.h>
#import "Chat/Server/ChatRuntime.h"
#import "Chat/Server/Config/ChatConfiguration.h"
#import "Debug/PDSLogger.h"

static const char *executable_name = "syrena-chat";
static ChatRuntime *gShutdownRuntime = nil;

void handleSignal(int sig) {
    [gShutdownRuntime stop];
    exit(0);
}

void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("Syrena Chat - Standalone AT Protocol Chat Service\n\n");
    printf("Provides private messaging (chat.bsky.*) as a standalone microservice.\n\n");
    printf("Commands:\n");
    printf("  serve        Start Chat server\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 2585)\n");
    printf("  --data-dir <path>     Data directory for database\n");
    printf("  --config <path>       Configuration file path (JSON)\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            print_usage();
            return 2;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            print_usage();
            return 0;
        }

        ChatRuntime *runtime = [ChatRuntime sharedRuntime];
        [runtime loadConfigurationFromEnvironment];

        // Parse basic arguments
        for (int i = 2; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--port"] && i + 1 < argc) {
                runtime.configuration.httpPort = (NSUInteger)[[NSString stringWithUTF8String:argv[++i]] integerValue];
            } else if ([arg isEqualToString:@"--data-dir"] && i + 1 < argc) {
                runtime.configuration.dataDirectory = [NSString stringWithUTF8String:argv[++i]];
            } else if ([arg isEqualToString:@"--config"] && i + 1 < argc) {
                NSError *error = nil;
                if (![runtime loadConfiguration:[NSString stringWithUTF8String:argv[++i]] error:&error]) {
                    fprintf(stderr, "Error loading config: %s\n", error.localizedDescription.UTF8String);
                    return 1;
                }
            } else if ([arg isEqualToString:@"-v"] || [arg isEqualToString:@"--verbose"]) {
                [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
            }
        }

        if ([command isEqualToString:@"serve"]) {
            NSError *error = nil;
            if (![runtime startWithError:&error]) {
                fprintf(stderr, "Failed to start Chat service: %s\n", error.localizedDescription.UTF8String);
                return 1;
            }

            printf("Syrena Chat server started on port %lu\n", (unsigned long)runtime.configuration.httpPort);
            
            gShutdownRuntime = runtime;
            signal(SIGTERM, handleSignal);
            signal(SIGINT,  handleSignal);

            [[NSRunLoop currentRunLoop] run];
        } else {
            fprintf(stderr, "Unknown command: %s\n", command.UTF8String);
            return 2;
        }
    }
    return 0;
}
