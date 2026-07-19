// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m
 @brief Entry point for the Syrena Chat standalone service.
 */

#import <Foundation/Foundation.h>
#import "Chat/Server/ChatRuntime.h"
#import "Chat/Server/Config/ChatConfiguration.h"
#import "CLI/GZCommandLineOptions.h"
#import "Debug/GZLogger.h"
#import "Runtime/GZServiceLifecycle.h"

static const char *executable_name = "syrena-chat";

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
        [GZServiceLifecycle bootstrapWithExecutableName:executable_name];

        if (argc < 2) {
            print_usage();
            return 2;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            print_usage();
            return 0;
        }

        if ([command isEqualToString:@"version"] || [command isEqualToString:@"-V"] || [command isEqualToString:@"--version"]) {
            printf("Syrena Chat 0.2.0 (AT Protocol Chat Service)\n");
            return 0;
        }

        ChatRuntime *runtime = [ChatRuntime sharedRuntime];
        [runtime loadConfigurationFromEnvironment];

        if ([command isEqualToString:@"serve"]) {
            GZCommandLineOptions *optionsParser = [[GZCommandLineOptions alloc] init];
            NSArray<GZCommandLineOption *> *options = @[
                [GZCommandLineOption optionWithLongName:@"port" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
                [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
                [GZCommandLineOption optionWithLongName:@"config" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
                [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO],
                [GZCommandLineOption optionWithLongName:@"help" shortName:@"h" type:GZCommandLineOptionTypeBoolean isRequired:NO]
            ];
            [optionsParser registerOptions:options forCommand:@"serve"];

            NSMutableArray<NSString *> *arguments = [NSMutableArray array];
            for (int i = 2; i < argc; i++) {
                [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
            }

            NSError *error = nil;
            NSDictionary<NSString *, id> *parsed = [optionsParser parseArguments:arguments forCommand:@"serve" error:&error];
            if (!parsed) {
                fprintf(stderr, "%s\n", error.localizedDescription.UTF8String ?: "Invalid arguments");
                return 1;
            }
            if ([parsed[@"help"] boolValue]) {
                print_usage();
                return 0;
            }
            if (parsed[@"config"]) {
                NSError *configError = nil;
                if (![runtime loadConfiguration:parsed[@"config"] error:&configError]) {
                    fprintf(stderr, "Error loading config: %s\n", configError.localizedDescription.UTF8String);
                    return 1;
                }
            }
            if (parsed[@"port"]) {
                runtime.configuration.httpPort = (NSUInteger)[parsed[@"port"] integerValue];
            }
            if (parsed[@"data-dir"]) {
                runtime.configuration.dataDirectory = parsed[@"data-dir"];
            }
            if ([parsed[@"verbose"] boolValue]) {
                [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
            }

            return [GZServiceLifecycle runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                                                 serviceName:@"Chat service"
                                                     onStart:^{
                                                         printf("Syrena Chat server started on port %lu\n", (unsigned long)runtime.configuration.httpPort);
                                                     }
                                             announceSignals:NO];
        } else {
            fprintf(stderr, "Unknown command: %s\n", command.UTF8String);
            return 2;
        }
    }
    return 0;
}
