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
#import "AdminUIServer/GZAdminUIHost.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Chat/AdminUI/ChatAdminUIPack.h"

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

        if ([command isEqualToString:@"version"] || [command isEqualToString:@"-V"] || [command isEqualToString:@"--version"]) {
            printf("Syrena Chat 0.2.0 (AT Protocol Chat Service)\n");
            return 0;
        }

        GZChatRuntime *runtime = [GZChatRuntime sharedRuntime];
        [runtime loadConfigurationFromEnvironment];

        if ([command isEqualToString:@"serve"]) {
            GZCommandLineOptions *optionsParser = [[GZCommandLineOptions alloc] init];
            NSArray<GZCommandLineOption *> *options = @[
                [GZCommandLineOption optionWithLongName:@"port" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
                [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
                [GZCommandLineOption optionWithLongName:@"config" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
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
                                 objectForKey:@"CHAT_ADMIN_PASSWORD"];
            }

            GZAdminUIHost *adminUIHost = nil;
            if (adminPassword.length > 0) {
                // One operator secret covers the UI session and Bearer-gated /_admin/*.
                runtime.configuration.adminSecret = adminPassword;

                GZAdminUIServiceConfig *adminConfig = [[GZAdminUIServiceConfig alloc] init];
                adminConfig.host = @"127.0.0.1";
                NSString *adminPortEnv = [[[NSProcessInfo processInfo] environment]
                                         objectForKey:@"CHAT_ADMIN_UI_PORT"];
                adminConfig.port = adminPortEnv.length > 0 ? (NSUInteger)adminPortEnv.integerValue : 2598;
                adminConfig.adminPassword = adminPassword;
                adminConfig.serviceIdentifier = @"chat";
                adminUIHost = [[GZAdminUIHost alloc] initWithConfiguration:adminConfig
                                                                      packs:@[GZChatAdminUIPack.class]];
                NSError *adminErr = nil;
                if (![adminUIHost startWithError:&adminErr]) {
                    GZ_LOG_WARN(@"Chat admin UI failed to start: %@", adminErr.localizedDescription);
                    adminUIHost = nil;
                } else {
                    NSURL *serviceURL = [NSURL URLWithString:
                        [NSString stringWithFormat:@"http://127.0.0.1:%lu",
                         (unsigned long)runtime.configuration.httpPort]];
                    [GZChatAdminUIPack configureHost:adminUIHost
                                     serviceBaseURL:serviceURL
                                        adminSecret:adminPassword];
                    GZ_LOG_INFO(@"Chat admin UI listening on 127.0.0.1:%lu",
                                (unsigned long)adminConfig.port);
                }
            } else {
                GZ_LOG_INFO(@"Chat admin UI disabled: set CHAT_ADMIN_PASSWORD or --admin-password-file");
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
