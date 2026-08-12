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
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Germ/AdminUI/GermAdminUIPack.h"

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
        NSError *bootstrapError = nil;
        if (![GZServiceLifecycle bootstrapWithExecutableName:executable_name error:&bootstrapError]) {
            fprintf(stderr, "FATAL: %s\n", bootstrapError.localizedDescription.UTF8String);
            return 1;
        }

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

        GZGermRuntime *runtime = [GZGermRuntime sharedRuntime];
        GZCommandLineOptions *optionsParser = [[GZCommandLineOptions alloc] init];
        NSArray<GZCommandLineOption *> *options = @[
            [GZCommandLineOption optionWithLongName:@"port" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"verbose" shortName:@"v" type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"admin-password-file" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
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

        // --- Embedded admin UI listener ---
        NSString *adminPassword = nil;
        NSString *adminPasswordFile = parsed[@"admin-password-file"];
        if (adminPasswordFile.length > 0) {
            adminPassword = [NSString stringWithContentsOfFile:adminPasswordFile
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil];
            adminPassword = [adminPassword stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (adminPassword.length == 0) {
            adminPassword = [[[NSProcessInfo processInfo] environment]
                             objectForKey:@"GERM_ADMIN_PASSWORD"];
        }

        if (adminPassword.length > 0) {
            GZAdminUIServiceConfig *adminConfig = [[GZAdminUIServiceConfig alloc] init];
            adminConfig.host = @"127.0.0.1";
            adminConfig.port = 2599;
            adminConfig.adminPassword = adminPassword;
            adminConfig.serviceIdentifier = @"germ";
            GZAdminUIHost *adminUIHost = [[GZAdminUIHost alloc] initWithConfiguration:adminConfig
                                                                                  packs:@[GZGermAdminUIPack.class]];
            NSError *adminErr = nil;
            if (![adminUIHost startWithError:&adminErr]) {
                GZ_LOG_WARN(@"Germ admin UI failed to start: %@", adminErr.localizedDescription);
            } else {
                GZ_LOG_INFO(@"Germ admin UI listening on 127.0.0.1:%lu", (unsigned long)adminConfig.port);
            }
        } else {
            GZ_LOG_INFO(@"Germ admin UI disabled: set GERM_ADMIN_PASSWORD or --admin-password-file");
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
