// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "CLI/PDSCLIDefinitions.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/GZLogger.h"
#import "Compat/PlatformShims/CrashReporting/PDSCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"

/**
 * @file main.m
 * @brief Entry point for the PDS command-line interface.
 *
 * This file implements the main function that parses command-line arguments,
 * initializes the execution context, and dispatches commands to the appropriate
 * handlers. The CLI supports various global options and commands for managing
 * the ATProto PDS server.
 */

// On Linux/GNUstep with GNU ld, +load methods in unreferenced objects within
// static archives are stripped. Import the explicit registration function
// so all CLI commands are available.
extern void PDSCLIRegisterAllCommands(void);

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

/// The name of the executable for usage messages.
static const char *executable_name = "kaszlak";

/**
 * @brief Prints usage information for the PDS CLI.
 *
 * Displays a summary of available commands and general usage instructions.
 */
void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("A command-line interface for managing kaszlak (ATProto PDS).\n");
    printf("Global flags (--config, --data-dir, --verbose, --json) must follow the command name.\n\n");
    printf("Commands:\n");
    printf("  serve       Start the PDS server\n");
    printf("  status      Local status (alias: health)\n");
    printf("  account     Account lifecycle\n");
    printf("  invite      Invite codes\n");
    printf("  oauth       OAuth client registration and inspection\n");
    printf("  repo        Repository inspection and helpers\n");
    printf("  admin       Administrator management\n");
    printf("  relay       In-process relay helpers\n");
    printf("  daemon      Background process lifecycle\n");
    printf("  init        Interactive config bootstrap\n");
    printf("  install     Service installation\n");
    printf("  nuke-data   Destructive data reset\n");
    printf("  repl        Interactive shell (aliases: shell, interactive)\n");
    printf("  help        Help for a command\n");
    printf("  version     Version information\n\n");
    printf("Use '%s help <command>' for more information about a command.\n", executable_name);
}

/**
 * @brief Parses global command-line options from command args.
 *
 * Global options are only accepted after the command token.
 *
 * @param commandArgs Mutable command argument array.
 * @param context   The command context to configure.
 * @param errorMessage Receives a human-readable error on invalid arguments.
 * @return YES on success, NO when parsing fails.
 */
static BOOL parse_global_options(NSMutableArray<NSString *> *commandArgs,
                                 PDSCLICommandContext *context,
                                 NSString **errorMessage) {
    for (NSUInteger i = 0; i < commandArgs.count;) {
        NSString *arg = commandArgs[i];
        if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
            if (i + 1 >= commandArgs.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --data-dir";
                }
                return NO;
            }
            context.dataDir = commandArgs[i + 1];
            [commandArgs removeObjectsInRange:NSMakeRange(i, 2)];
            continue;
        }
        if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
            if (i + 1 >= commandArgs.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --config";
                }
                return NO;
            }
            context.configPath = commandArgs[i + 1];
            [commandArgs removeObjectsInRange:NSMakeRange(i, 2)];
            continue;
        }
        if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            context.verbose = YES;
            [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
            [commandArgs removeObjectAtIndex:i];
            continue;
        }
        if ([arg isEqualToString:@"--json"] || [arg isEqualToString:@"-j"]) {
            context.jsonOutput = YES;
            [commandArgs removeObjectAtIndex:i];
            continue;
        }

        i++;
    }

    return YES;
}

static int fail_with_usage(NSString *errorMessage) {
    if (errorMessage.length > 0) {
        fprintf(stderr, "Error: %s\n\n", [errorMessage UTF8String]);
    }
    print_usage();
    return PDSCLIExitCodeInvalidArguments;
}

/**
 * @brief The entry point for the PDS CLI application.
 *
 * Enforces strict invocation format:
 *   kaszlak <command> [options]
 * Flags before command are rejected.
 */
int main(int argc, const char * argv[]) {
    [[GZSignalManager sharedManager] installIgnoredSignals];
    [PDSCrashReporter installCrashHandlersWithExecutableName:"kaszlak"];
    @autoreleasepool {
        PDSCLIRegisterAllCommands();
        // Force linkage of NSDateFormatter category on static builds
        NSDateFormatterLinkATProtoCategory();
#ifdef LINUX
        // On Linux/GNUstep, verify critical categories are loaded
        if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) {
            fprintf(stderr, "FATAL: Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings.\n");
            return PDSCLIExitCodeGeneralError;
        }
#endif

        if (argc < 2) {
            return fail_with_usage(@"Missing command");
        }

        NSString *commandName = [NSString stringWithUTF8String:argv[1]];
        if ([commandName hasPrefix:@"-"]) {
            return fail_with_usage(@"Flags must follow the command name");
        }

        NSMutableArray<NSString *> *commandArgs = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [commandArgs addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];
        NSString *parseError = nil;
        if (!parse_global_options(commandArgs, context, &parseError)) {
            return fail_with_usage(parseError);
        }

        @try {
            int result = [[PDSCLIDispatcher sharedDispatcher] dispatchWithCommandName:commandName
                                                                            arguments:commandArgs
                                                                              context:context];
            return result;
        } @catch (NSException *exception) {
            if ([exception.name isEqualToString:@"PDSCLIUnknownCommandException"]) {
                return PDSCLIExitCodeNotFound;
            }
            if ([exception.name isEqualToString:@"PDSCLICommandFailedException"]) {
                return PDSCLIExitCodeGeneralError;
            }
            [context printError:[NSString stringWithFormat:@"Unexpected error: %@", exception.reason]];
            return PDSCLIExitCodeGeneralError;
        }
    }
    return PDSCLIExitCodeSuccess;
}
