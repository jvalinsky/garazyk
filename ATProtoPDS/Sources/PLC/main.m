#import <Foundation/Foundation.h>
#import "PLC/PLCServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCPersistentStore.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCReplicaServer.h"
#import "PLC/PLCSyncEngine.h"
#import "PLC/PLCReplicaStore.h"
#import "PLC/PLCSyncClient.h"
#import "Debug/PDSLogger.h"

#import <readline/readline.h>
#import <readline/history.h>

void print_usage(const char *executable_name) {
    printf("Usage: %s [options]\n\n", executable_name);
    printf("A standalone PLC server for ATProto (PLC Directory).\n\n");
    printf("Commands:\n");
    printf("  serve              Start PLC server (default)\n");
    printf("  replica             Start as read-only replica\n");
    printf("  repl                Interactive REPL mode\n");
    printf("  version             Show version\n");
    printf("  help                Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>    Port to listen on (default: 2582)\n");
    printf("  --database <path>  Path to SQLite database\n");
    printf("  --replica          Run as read-only replica\n");
    printf("  --upstream <url>   Upstream PLC URL for replica sync\n");
    printf("  --data-dir <path>  Data directory for replica\n");
    printf("  --help, -h         Show help information\n\n");
    printf("Examples:\n");
    printf("  %s --port 2582                          # Start on default port\n", executable_name);
    printf("  %s --database /var/lib/plc.db           # Use persistent store\n", executable_name);
    printf("  %s --replica --upstream https://plc.directory  # Run as replica\n", executable_name);
    printf("  %s repl                                 # Interactive REPL\n", executable_name);
}

void print_version(void) {
    printf("atproto-plc (kaszlak PLC) 1.0.0\n");
    printf("PLC Directory server for ATProto\n");
}

void run_repl(NSString *dataDir) {
    printf("Welcome to PLC REPL. Type .help for commands, .exit to quit.\n");
    printf("Available: resolve, audit, metrics, health\n");

    using_history();
    stifle_history(100);

    char *line;
    while ((line = readline("plc> ")) != NULL) {
        NSString *input = [NSString stringWithUTF8String:line];
        NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (trimmed.length == 0) {
            free(line);
            continue;
        }
        add_history(line);

        if ([trimmed isEqualToString:@".exit"] || [trimmed isEqualToString:@".quit"]) {
            printf("Exiting PLC REPL.\n");
            break;
        }
        if ([trimmed isEqualToString:@".help"]) {
            printf("\nPLC REPL Commands:\n");
            printf("  .help              Show this help\n");
            printf("  .history           Show command history\n");
            printf("  .clear             Clear screen\n");
            printf("  .exit              Exit REPL\n");
            printf("  resolve <did>      Resolve a DID\n");
            printf("  audit <did>        Audit DID operations\n");
            printf("  metrics            Show PLC metrics\n");
            printf("  health             Check server health\n");
            printf("\n");
            free(line);
            continue;
        }
        if ([trimmed isEqualToString:@".history"]) {
            free(line);
            continue;
        }
        if ([trimmed isEqualToString:@".clear"]) {
            printf("\033[2J\033[H");
            free(line);
            continue;
        }
        if ([trimmed hasPrefix:@"."]) {
            printf("Unknown command: %s\n", [trimmed UTF8String]);
            free(line);
            continue;
        }

        printf("Command '%s' not implemented in REPL. Use --help for server options.\n", [trimmed UTF8String]);
        free(line);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUInteger port = 2582;
        NSString *dbPath = nil;
        NSString *dataDir = nil;
        NSString *upstreamURL = nil;
        BOOL replicaMode = NO;
        BOOL replMode = NO;
        NSString *command = @"serve";

        for (int i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
                if (i + 1 < argc) {
                    port = (NSUInteger)[[NSString stringWithUTF8String:argv[++i]] integerValue];
                }
            } else if ([arg isEqualToString:@"--database"] || [arg isEqualToString:@"-d"]) {
                if (i + 1 < argc) {
                    dbPath = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--data-dir"]) {
                if (i + 1 < argc) {
                    dataDir = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--upstream"] || [arg isEqualToString:@"-u"]) {
                if (i + 1 < argc) {
                    upstreamURL = [NSString stringWithUTF8String:argv[++i]];
                }
            } else if ([arg isEqualToString:@"--replica"] || [arg isEqualToString:@"-r"]) {
                replicaMode = YES;
            } else if ([arg isEqualToString:@"serve"]) {
                command = @"serve";
            } else if ([arg isEqualToString:@"replica"]) {
                command = @"replica";
            } else if ([arg isEqualToString:@"repl"]) {
                command = @"repl";
            } else if ([arg isEqualToString:@"version"]) {
                print_version();
                return 0;
            } else if ([arg isEqualToString:@"help"] || [arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]) {
                print_usage(argv[0]);
                return 0;
            }
        }

        if ([command isEqualToString:@"repl"]) {
            run_repl(dataDir);
            return 0;
        }

        id<PLCStore> store = nil;
        if (dbPath) {
            NSError *storeError = nil;
            store = [PLCPersistentStore storeWithPath:dbPath error:&storeError];
            if (!store) {
                PDS_LOG_CORE_ERROR(@"Failed to open persistent store at %@: %@", dbPath, storeError.localizedDescription);
                return 1;
            }
            printf("Using persistent store at %s\n", [dbPath UTF8String]);
        } else {
            store = [[PLCMockStore alloc] init];
            printf("Using in-memory mock store\n");
        }

        PLCAuditor *auditor = [[PLCAuditor alloc] initWithStore:store];

        id server;
        if (replicaMode || [command isEqualToString:@"replica"]) {
            printf("Starting PLC replica server on port %lu\n", (unsigned long)port);
            server = [[PLCReplicaServer alloc] initWithStore:store auditor:auditor port:port readOnlyMode:YES];
        } else {
            printf("Starting PLC server on port %lu\n", (unsigned long)port);
            server = [[PLCServer alloc] initWithStore:store auditor:auditor port:port];
        }

        NSError *error = nil;
        if (![server startWithError:&error]) {
            PDS_LOG_CORE_ERROR(@"Failed to start PLC server: %@", error.localizedDescription ?: @"unknown error");
            return 1;
        }

        printf("PLC server listening on port %lu\n", (unsigned long)port);
        printf("Use --help for options, 'repl' for interactive mode\n");

        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
