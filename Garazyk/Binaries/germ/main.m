// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m
 @brief Entry point for the Germ E2EE Mailbox standalone service.
 */

#import <Foundation/Foundation.h>
#import "Germ/Server/Runtime/GermRuntime.h"
#import "CLI/GZCommandLineOptions.h"
#import "Debug/GZLogger.h"
#import "Runtime/GZServiceLifecycle.h"

static const char *executable_name = "germ";

void print_usage(void) {
    printf("Usage: %s serve [options]\n\n", executable_name);
    printf("Germ - Standalone AT Protocol E2EE Mailbox Service\n\n");
    printf("Provides encrypted message storage and relay (com.germnetwork.*).\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 8082)\n");
    printf("  --data-dir <path>     Data directory for database\n");
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

        if (![command isEqualToString:@"serve"]) {
            fprintf(stderr, "Unknown command: %s\n", command.UTF8String);
            return 2;
        }

        GermRuntime *runtime = [GermRuntime sharedRuntime];
        GZCommandLineOptions *optionsParser = [[GZCommandLineOptions alloc] init];
        NSArray<GZCommandLineOption *> *options = @[
            [GZCommandLineOption optionWithLongName:@"port" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
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
        if (parsed[@"port"]) {
            runtime.port = (uint16_t)[parsed[@"port"] integerValue];
        }
        if (parsed[@"data-dir"]) {
            runtime.dataDirectory = parsed[@"data-dir"];
        }
        if ([parsed[@"verbose"] boolValue]) {
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
        }

        return [GZServiceLifecycle runServiceWithRuntime:(id<GZServiceRuntimeProtocol>)runtime
                                             serviceName:@"Germ service"
                                                 onStart:^{
                                                     printf("Germ E2EE mailbox server started on port %u\n", runtime.port != 0 ? runtime.port : 8082);
                                                 }
                                         announceSignals:NO];
    }
    return 0;
}
