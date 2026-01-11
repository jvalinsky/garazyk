#import <Foundation/Foundation.h>
#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSMutableArray *args = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];

        NSUInteger firstCommandArg = args.count;
        for (NSUInteger i = 0; i < args.count; i++) {
            NSString *arg = args[i];
            if ([arg hasPrefix:@"-"]) {
                if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
                    if (i + 1 < args.count) {
                        context.dataDir = args[++i];
                    } else {
                        fprintf(stderr, "Error: --data-dir requires a path\n");
                        return PDSCLIExitCodeInvalidArguments;
                    }
                } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
                    if (i + 1 < args.count) {
                        context.configPath = args[++i];
                    } else {
                        fprintf(stderr, "Error: --config requires a path\n");
                        return PDSCLIExitCodeInvalidArguments;
                    }
                } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                    context.verbose = YES;
                    [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
                } else if ([arg isEqualToString:@"--json"] || [arg isEqualToString:@"-j"]) {
                    context.jsonOutput = YES;
                } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                    [[PDSCLIDispatcher sharedDispatcher] printUsage];
                    return PDSCLIExitCodeSuccess;
                } else {
                    fprintf(stderr, "Error: Unknown option %s\n", [arg UTF8String]);
                    [[PDSCLIDispatcher sharedDispatcher] printUsage];
                    return PDSCLIExitCodeInvalidArguments;
                }
            } else {
                firstCommandArg = i;
                break;
            }
        }

        if (firstCommandArg >= args.count) {
            [[PDSCLIDispatcher sharedDispatcher] printUsage];
            return PDSCLIExitCodeSuccess;
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
    return PDSCLIExitCodeSuccess;
}

