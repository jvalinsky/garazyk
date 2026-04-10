#import "PDSCLIDefinitions.h"
#import "CLI/PDSCLIDispatcher.h"
#import "CLI/PDSCLIInputHelper.h"
#import "Debug/PDSLogger.h"

#import <readline/readline.h>
#import <readline/history.h>

#pragma mark - REPL Command

@interface PDSCLIReplCommand : PDSBaseCommand
@end

@implementation PDSCLIReplCommand

- (NSString *)name {
    return @"repl";
}

- (NSString *)summary {
    return @"Interactive REPL mode for kaszlak CLI";
}

- (NSString *)usage {
    return @"pds repl [options]";
}

- (NSString *)helpText {
    return @"Interactive REPL (Read-Eval-Print Loop) mode for kaszlak CLI.\n\n"
           @"Usage: pds repl [options]\n\n"
           @"Features:\n"
           @"  - Command history (up/down arrows)\n"
           @"  - Tab completion for commands and arguments\n"
           @"  - REPL commands: .help, .history, .clear, .exit\n\n"
           @"Special REPL commands:\n"
           @"  .help              Show this help\n"
           @"  .history           Show command history\n"
           @"  .clear             Clear screen\n"
           @"  .exit              Exit REPL (Ctrl+D also works)\n\n"
           @"Examples:\n"
           @"  pds repl                           # Start interactive REPL\n"
           @"  pds repl --data-dir /var/lib/pds   # REPL with custom data dir";
}

- (NSArray<NSString *> *)aliases {
    return @[ @"shell", @"interactive" ];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    printf("Welcome to kaszlak REPL. Type .help for commands, .exit to quit.\n");
    printf("Loading PDS services...\n");

    NSString *prompt = @"kaszlak> ";
    NSMutableArray *history = [NSMutableArray array];

    using_history();
    stifle_history(100);

    while (1) {
        char *line = readline([prompt UTF8String]);
        
        if (line == NULL) {
            printf("\nExiting REPL.\n");
            break;
        }

        NSString *input = [NSString stringWithUTF8String:line];
        NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (trimmed.length == 0) {
            free(line);
            continue;
        }

        add_history(line);
        [history addObject:trimmed];

        if ([trimmed isEqualToString:@".exit"] || [trimmed isEqualToString:@".quit"]) {
            printf("Exiting REPL.\n");
            free(line);
            break;
        }

        if ([trimmed isEqualToString:@".help"]) {
            printf("\nREPL Commands:\n");
            printf("  .help              Show this help\n");
            printf("  .history           Show command history\n");
            printf("  .clear             Clear screen\n");
            printf("  .exit              Exit REPL\n");
            printf("\nAll pds commands are available (serve, account, invite, etc.)\n");
            printf("Use 'pds <command> --help' for command-specific help.\n\n");
            free(line);
            continue;
        }

        if ([trimmed isEqualToString:@".history"]) {
            printf("\nCommand history:\n");
            for (NSUInteger i = 0; i < history.count; i++) {
                printf("  %lu: %s\n", (unsigned long)(i + 1), [history[i] UTF8String]);
            }
            printf("\n");
            free(line);
            continue;
        }

        if ([trimmed isEqualToString:@".clear"]) {
            printf("\033[2J\033[H");
            free(line);
            continue;
        }

        if ([trimmed hasPrefix:@"."]) {
            [context printError:[NSString stringWithFormat:@"Unknown REPL command: %@", trimmed]];
            printf("Use .help for available commands.\n");
            free(line);
            continue;
        }

        NSArray *parts = [self parseCommandLine:trimmed];
        if (parts.count == 0) {
            free(line);
            continue;
        }

        NSString *commandName = parts[0];
        NSArray *commandArgs = parts.count > 1 ? [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] : @[];

        @try {
            int result = [[PDSCLIDispatcher sharedDispatcher] dispatchWithCommandName:commandName
                                                                            arguments:commandArgs
                                                                             context:context];
            if (result != 0 && context.jsonOutput) {
                printf("Command exited with code: %d\n", result);
            }
        } @catch (NSException *exception) {
            [context printError:[NSString stringWithFormat:@"Error: %@", exception.reason]];
        }

        free(line);
    }

    return 0;
}

- (NSArray<NSString *> *)parseCommandLine:(NSString *)line {
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inQuote = NO;
    unichar quoteChar = 0;

    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];

        if (!inQuote && (c == '"' || c == '\'')) {
            inQuote = YES;
            quoteChar = c;
        } else if (inQuote && c == quoteChar) {
            inQuote = NO;
            quoteChar = 0;
        } else if (!inQuote && c == ' ') {
            if (current.length > 0) {
                [parts addObject:[current copy]];
                current = [NSMutableString string];
            }
        } else {
            [current appendFormat:@"%C", c];
        }
    }

    if (current.length > 0) {
        [parts addObject:[current copy]];
    }

    return parts;
}

+ (instancetype)command {
    return [[PDSCLIReplCommand alloc] init];
}

@end