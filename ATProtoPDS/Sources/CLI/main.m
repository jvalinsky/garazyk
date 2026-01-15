#import <Foundation/Foundation.h>
#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

/**
 * @file main.m
 * @brief Entry point for the PDS command-line interface.
 *
 * This file implements the main function that parses command-line arguments,
 * initializes the execution context, and dispatches commands to the appropriate
 * handlers. The CLI supports various global options and commands for managing
 * the ATProto PDS server.
 */

/// The name of the executable for usage messages.
static const char *executable_name = "pds";

/**
 * @brief Prints usage information for the PDS CLI.
 *
 * Displays a summary of available commands and general usage instructions.
 */
void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("A command-line interface for managing the ATProto PDS.\n\n");
    printf("Commands:\n");
    printf("  serve       Start the PDS server\n");
    printf("  health      Check PDS health status\n");
    printf("  account     Manage PDS accounts\n");
    printf("  invite      Manage invite codes\n");
    printf("  help        Show help information\n");
    printf("  version     Show version information\n\n");
    printf("Use '%s help <command>' for more information about a command.\n", executable_name);
}

/**
 * @brief Parses global command-line options and initializes the context.
 *
 * @param argc      The argument count from main().
 * @param argv      The argument vector from main().
 * @param args      The mutable array to populate with remaining arguments.
 * @param context   The command context to configure.
 * @return The index of the first command argument in argv, or argc if no command.
 */
static NSUInteger parse_global_options(int argc, const char * argv[],
                                       NSMutableArray *args,
                                       PDSCLICommandContext *context) {
    NSUInteger firstCommandArg = 0;
    for (int i = 1; i < argc; i++) {
        NSString *arg = [NSString stringWithUTF8String:argv[i]];
        if ([arg hasPrefix:@"-"]) {
            if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
                if (i + 1 < argc) {
                    context.dataDir = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
                if (i + 1 < argc) {
                    context.configPath = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                context.verbose = YES;
                [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
            } else if ([arg isEqualToString:@"--json"] || [arg isEqualToString:@"-j"]) {
                context.jsonOutput = YES;
            } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                print_usage();
                exit(0);
            }
            firstCommandArg = i + 1;
        } else {
            break;
        }
    }
    return firstCommandArg;
}

/**
 * @brief The entry point for the PDS CLI application.
 *
 * Initializes the logging system, parses command-line arguments,
 * creates the execution context, and dispatches the appropriate command.
 *
 * Supported global options:
 *   -d, --data-dir <path>   Set the data directory
 *   -c, --config <path>     Set the configuration file path
 *   -v, --verbose           Enable verbose (debug) logging
 *   -j, --json              Output in JSON format
 *   -h, --help              Show help and exit
 *
 * @param argc The number of command-line arguments.
 * @param argv An array of command-line argument strings.
 * @return The exit code indicating success or failure.
 */
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSMutableArray *args = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];
        NSUInteger firstCommandArg = parse_global_options(argc, argv, args, context);

        // Fix index mismatch between argv (1-based for args) and args array (0-based)
        // firstCommandArg is an index into argv.
        // If it's 0, it means no options were parsed, so command starts at argv[1] (args[0]).
        // If it's > 0, it points to argv[firstCommandArg], which corresponds to args[firstCommandArg - 1].
        NSUInteger commandIndex = (firstCommandArg == 0) ? 0 : firstCommandArg - 1;

        if (commandIndex >= args.count) {
            print_usage();
            return PDSCLIExitCodeSuccess;
        }

        NSString *commandName = args[commandIndex];
        NSMutableArray *commandArgs = [NSMutableArray array];
        for (NSUInteger i = commandIndex + 1; i < args.count; i++) {
            [commandArgs addObject:args[i]];
        }

        [[PDSCLIDispatcher sharedDispatcher] dispatchWithCommandName:commandName
                                                            arguments:commandArgs
                                                             context:context];
    }
    return PDSCLIExitCodeSuccess;
}
