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
#import "Core/NSDateFormatter+ATProto.h"

#import <readline/readline.h>
#import <readline/history.h>

void print_usage(const char *executable_name) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("A standalone PLC server for ATProto (PLC Directory).\n\n");
    printf("Commands:\n");
    printf("  serve              Start PLC server\n");
    printf("  replica            Start as read-only replica\n");
    printf("  status             Check PLC status\n");
    printf("  repl               Interactive REPL mode\n");
    printf("  version            Show version\n");
    printf("  help               Show this help\n\n");
    printf("Options:\n");
    printf("  --host <address>   Address to bind to (default: 127.0.0.1)\n");
    printf("  --port <number>    Port to listen on (default: 2582)\n");
    printf("  --database <path>  Path to SQLite database\n");
    printf("  --replica          Run serve command in read-only replica mode\n");
    printf("  --upstream <url>   Upstream PLC URL for replica sync\n");
    printf("  --data-dir <path>  Data directory for replica\n");
    printf("  --help, -h         Show help information\n\n");
    printf("Examples:\n");
    printf("  %s serve --port 2582                    # Start on default port\n", executable_name);
    printf("  %s serve --database /var/lib/plc.db     # Use persistent store\n", executable_name);
    printf("  %s replica --upstream https://plc.directory  # Run as replica\n", executable_name);
    printf("  %s status                               # Check server health\n", executable_name);
    printf("  %s repl                                 # Interactive REPL\n", executable_name);
}

void print_version(void) {
    printf("campagnola (AT Protocol PLC Directory) 1.0.0\n");
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

static int fail_with_usage(const char *executable_name, NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\n\n", [message UTF8String]);
    }
    print_usage(executable_name);
    return 2;
}

static BOOL parse_server_options(NSArray<NSString *> *args,
                                 NSString **host,
                                 NSUInteger *port,
                                 NSString **dbPath,
                                 NSString **dataDir,
                                 NSString **upstreamURL,
                                 BOOL *replicaMode,
                                 NSString **errorMessage) {
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--host"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --host";
                }
                return NO;
            }
            if (host) {
                *host = args[++i];
            }
        } else if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --port";
                }
                return NO;
            }
            if (port) {
                *port = (NSUInteger)[args[++i] integerValue];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--database"] || [arg isEqualToString:@"-d"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --database";
                }
                return NO;
            }
            if (dbPath) {
                *dbPath = args[++i];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--data-dir"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --data-dir";
                }
                return NO;
            }
            if (dataDir) {
                *dataDir = args[++i];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--upstream"] || [arg isEqualToString:@"-u"]) {
            if (i + 1 >= args.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --upstream";
                }
                return NO;
            }
            if (upstreamURL) {
                *upstreamURL = args[++i];
            } else {
                i++;
            }
        } else if ([arg isEqualToString:@"--replica"] || [arg isEqualToString:@"-r"]) {
            if (replicaMode) {
                *replicaMode = YES;
            }
        } else if ([arg hasPrefix:@"-"]) {
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"Unknown option: %@", arg];
            }
            return NO;
        } else {
            if (errorMessage) {
                *errorMessage = [NSString stringWithFormat:@"Unexpected argument: %@", arg];
            }
            return NO;
        }
    }
    return YES;
}

static int run_status_command(NSString *host, NSUInteger port) {
    NSString *urlString = [NSString stringWithFormat:@"http://%@:%lu/_health", host, (unsigned long)port];
    NSURL *url = [NSURL URLWithString:urlString];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!data || error) {
        printf("PLC status: NOT RUNNING (host=%s port=%lu)\n", [host UTF8String], (unsigned long)port);
        if (error) {
            printf("  Error: %s\n", [error.localizedDescription UTF8String]);
        }
        return 1;
    }

    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    printf("PLC status: RUNNING\n");
    if (body.length > 0) {
        printf("  Response: %s\n", [body UTF8String]);
    }
    return 0;
}

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSDateFormatterLinkATProtoCategory();
#ifdef LINUX
        // On Linux/GNUstep, verify critical categories are loaded
        if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) {
            fprintf(stderr, "FATAL: Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings.\n");
            return 1;
        }
#endif
        const char *binaryName = argv[0] ? argv[0] : "campagnola";
        if (argc < 2) {
            return fail_with_usage(binaryName, @"Missing command");
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command hasPrefix:@"-"]) {
            return fail_with_usage(binaryName, @"Flags must follow the command name");
        }

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        if ([args containsObject:@"--help"] || [args containsObject:@"-h"]) {
            print_usage(binaryName);
            return 0;
        }

        if ([command isEqualToString:@"help"]) {
            print_usage(binaryName);
            return 0;
        }
        if ([command isEqualToString:@"version"]) {
            print_version();
            return 0;
        }

        NSUInteger port = 2582;
        NSString *host = @"127.0.0.1";
        NSString *dbPath = nil;
        NSString *dataDir = nil;
        NSString *upstreamURL = nil;
        BOOL replicaMode = NO;
        NSString *parseError = nil;
        if ([command isEqualToString:@"status"] || [command isEqualToString:@"health"]) {
            if (!parse_server_options(args, &host, &port, nil, nil, nil, nil, &parseError)) {
                return fail_with_usage(binaryName, parseError);
            }
            return run_status_command(host, port);
        }
        if ([command isEqualToString:@"repl"]) {
            if (!parse_server_options(args, nil, nil, nil, &dataDir, nil, nil, &parseError)) {
                return fail_with_usage(binaryName, parseError);
            }
            run_repl(dataDir);
            return 0;
        }
        if (![command isEqualToString:@"serve"] && ![command isEqualToString:@"replica"]) {
            return fail_with_usage(binaryName, [NSString stringWithFormat:@"Unknown command: %@", command]);
        }
        if (!parse_server_options(args, &host, &port, &dbPath, &dataDir, &upstreamURL, &replicaMode, &parseError)) {
            return fail_with_usage(binaryName, parseError);
        }
        if ([command isEqualToString:@"replica"]) {
            replicaMode = YES;
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
            server = [[PLCServer alloc] initWithStore:store auditor:auditor host:host port:port];
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
