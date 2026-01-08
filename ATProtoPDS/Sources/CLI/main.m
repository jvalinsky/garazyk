#import <Foundation/Foundation.h>
#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

void print_usage(void) {
    printf("Usage: pds <command> [options]\n\n");
    printf("A command-line interface for managing the ATProto PDS.\n\n");
    printf("Commands:\n");
    printf("  serve       Start the PDS server\n");
    printf("  health      Check PDS health status\n");
    printf("  account     Manage PDS accounts\n");
    printf("  invite      Manage invite codes\n");
    printf("  help        Show help information\n");
    printf("  version     Show version information\n\n");
    printf("Use 'pds help <command>' for more information about a command.\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSMutableArray *args = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];

        NSUInteger firstCommandArg = 0;
        for (NSUInteger i = 0; i < args.count; i++) {
            NSString *arg = args[i];
            if ([arg hasPrefix:@"-"]) {
                if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
                    if (i + 1 < args.count) {
                        context.dataDir = args[++i];
                    }
                } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
                    if (i + 1 < args.count) {
                        context.configPath = args[++i];
                    }
                } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                    context.verbose = YES;
                    [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
                } else if ([arg isEqualToString:@"--json"] || [arg isEqualToString:@"-j"]) {
                    context.jsonOutput = YES;
                } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                    print_usage();
                    return 0;
                }
                firstCommandArg = i + 1;
            } else {
                break;
            }
        }

        if (firstCommandArg >= args.count) {
            print_usage();
            return 0;
        }

        NSString *commandName = args[firstCommandArg];
        NSMutableArray *commandArgs = [NSMutableArray array];
        for (NSUInteger i = firstCommandArg + 1; i < args.count; i++) {
            [commandArgs addObject:args[i]];
        }

        [[PDSCLIDispatcher sharedDispatcher] dispatchWithCommandName:commandName
                                                            arguments:commandArgs
                                                             context:context];
    }
    return 0;
}
