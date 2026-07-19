// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "PLC/PLCServer.h"
#import "PLC/PLCMockStore.h"
#import "PLC/PLCPersistentStore.h"
#import "PLC/PLCAuditor.h"
#import "PLC/PLCReplicaServer.h"
#import "PLC/PLCSyncEngine.h"
#import "PLC/PLCReplicaStore.h"
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif
#import "PLC/PLCSyncClient.h"
#import "Debug/GZLogger.h"
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
    printf("  --in-memory        Use an in-memory store for dev/test\n");
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

#import "CLI/GZCommandLineOptions.h"
#import "Runtime/GZServiceLifecycle.h"

static const char *executable_name = "campagnola";

@interface PLCRuntimeComposite : NSObject <GZServiceRuntimeProtocol>
@property (nonatomic, strong) PLCServer *server;
@property (nonatomic, strong, nullable) PLCSyncEngine *syncEngine;
@end

@implementation PLCRuntimeComposite
- (BOOL)startWithError:(NSError **)error {
    return [self.server startWithError:error];
}
- (void)stop {
    if (self.syncEngine) {
        [self.syncEngine stop];
    }
    [self.server stop];
}
@end

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
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    @autoreleasepool {
        [GZServiceLifecycle bootstrapWithExecutableName:executable_name];
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

        if ([command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"]) {
            print_usage(binaryName);
            return 0;
        }
        if ([command isEqualToString:@"version"] || [command isEqualToString:@"-V"] || [command isEqualToString:@"--version"]) {
            print_version();
            return 0;
        }

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        if ([args containsObject:@"--help"] || [args containsObject:@"-h"]) {
            print_usage(binaryName);
            return 0;
        }

        if (![command isEqualToString:@"serve"] &&
            ![command isEqualToString:@"replica"] &&
            ![command isEqualToString:@"status"] &&
            ![command isEqualToString:@"health"] &&
            ![command isEqualToString:@"repl"]) {
            return fail_with_usage(binaryName, [NSString stringWithFormat:@"Unknown command: %@", command]);
        }

        GZCommandLineOptions *parser = [[GZCommandLineOptions alloc] init];
        NSArray<GZCommandLineOption *> *serveOptions = @[
            [GZCommandLineOption optionWithLongName:@"host" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"database" shortName:@"d" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"in-memory" shortName:nil type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"replica" shortName:@"r" type:GZCommandLineOptionTypeBoolean isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"upstream" shortName:@"u" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"help" shortName:@"h" type:GZCommandLineOptionTypeBoolean isRequired:NO]
        ];
        [parser registerOptions:serveOptions forCommand:@"serve"];
        [parser registerOptions:serveOptions forCommand:@"replica"];

        NSArray<GZCommandLineOption *> *statusOptions = @[
            [GZCommandLineOption optionWithLongName:@"host" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"port" shortName:@"p" type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"help" shortName:@"h" type:GZCommandLineOptionTypeBoolean isRequired:NO]
        ];
        [parser registerOptions:statusOptions forCommand:@"status"];
        [parser registerOptions:statusOptions forCommand:@"health"];

        NSArray<GZCommandLineOption *> *replOptions = @[
            [GZCommandLineOption optionWithLongName:@"data-dir" shortName:nil type:GZCommandLineOptionTypeString isRequired:NO],
            [GZCommandLineOption optionWithLongName:@"help" shortName:@"h" type:GZCommandLineOptionTypeBoolean isRequired:NO]
        ];
        [parser registerOptions:replOptions forCommand:@"repl"];

        NSError *parseError = nil;
        NSDictionary<NSString *, id> *parsedArgs = [parser parseArguments:args forCommand:command error:&parseError];
        if (!parsedArgs) {
            return fail_with_usage(binaryName, parseError.localizedDescription);
        }

        NSUInteger port = parsedArgs[@"port"] ? (NSUInteger)[parsedArgs[@"port"] integerValue] : 2582;
        NSString *host = parsedArgs[@"host"] ?: @"127.0.0.1";
        NSString *dbPath = parsedArgs[@"database"];
        NSString *dataDir = parsedArgs[@"data-dir"];
        NSString *upstreamURL = parsedArgs[@"upstream"];
        BOOL replicaMode = [parsedArgs[@"replica"] boolValue] || [command isEqualToString:@"replica"];
        BOOL inMemory = [parsedArgs[@"in-memory"] boolValue];

        if ([command isEqualToString:@"status"] || [command isEqualToString:@"health"]) {
            return run_status_command(host, port);
        }
        if ([command isEqualToString:@"repl"]) {
            run_repl(dataDir);
            return 0;
        }

        if (replicaMode && !upstreamURL) {
            upstreamURL = @"https://plc.directory";
            printf("No --upstream specified, defaulting to %s\n", [upstreamURL UTF8String]);
        }

        PLCServer *server = nil;
        PLCSyncEngine *syncEngine = nil;

        if (replicaMode) {
            // Replica mode: use PLCReplicaStore + PLCSyncEngine for upstream sync
            NSString *replicaDBPath = dbPath;
            if (!replicaDBPath && dataDir) {
                replicaDBPath = [dataDir stringByAppendingPathComponent:@"plc-replica.db"];
            }
            if (!replicaDBPath) {
                return fail_with_usage(binaryName, @"Replica mode requires --database or --data-dir");
            }

            NSError *storeError = nil;
            PLCReplicaStore *replicaStore = [[PLCReplicaStore alloc] initWithPath:replicaDBPath];
            if (![replicaStore openWithError:&storeError]) {
                GZ_LOG_CORE_ERROR(@"Failed to open replica store at %@: %@",
                                    replicaDBPath, storeError.localizedDescription);
                return 1;
            }
            printf("Using replica store at %s\n", [replicaDBPath UTF8String]);

            PLCAuditor *auditor = [[PLCAuditor alloc] initWithStore:replicaStore];
            PLCSyncClient *syncClient = [[PLCSyncClient alloc] initWithUpstreamURL:upstreamURL];
            syncEngine = [[PLCSyncEngine alloc] initWithStore:replicaStore
                                                       client:syncClient
                                                      auditor:auditor];
            syncEngine.batchSize = 1000;

            printf("Starting PLC replica server on port %lu (upstream: %s)\n",
                   (unsigned long)port, [upstreamURL UTF8String]);
            server = [[PLCReplicaServer alloc] initWithStore:replicaStore
                                                      auditor:auditor
                                                         host:host
                                                         port:port
                                                 readOnlyMode:YES];
        } else {
            // Primary mode: standalone PLC server
            id<PLCStore> store = nil;
            if (dbPath) {
                NSError *storeError = nil;
                store = [PLCPersistentStore storeWithPath:dbPath error:&storeError];
                if (!store) {
                    GZ_LOG_CORE_ERROR(@"Failed to open persistent store at %@: %@",
                                        dbPath, storeError.localizedDescription);
                    return 1;
                }
                printf("Using persistent store at %s\n", [dbPath UTF8String]);
            } else if (inMemory) {
                store = [[PLCMockStore alloc] init];
                printf("Using in-memory mock store\n");
            } else {
                return fail_with_usage(binaryName, @"serve requires --database or explicit --in-memory");
            }

            PLCAuditor *auditor = [[PLCAuditor alloc] initWithStore:store];
            printf("Starting PLC server on port %lu\n", (unsigned long)port);
            server = [[PLCServer alloc] initWithStore:store
                                               auditor:auditor
                                                  host:host
                                                  port:port];
        }

        PLCRuntimeComposite *composite = [[PLCRuntimeComposite alloc] init];
        composite.server = server;
        composite.syncEngine = syncEngine;

        return [GZServiceLifecycle runServiceWithRuntime:composite
                                             serviceName:@"PLC server"
                                                 onStart:^{
                                                     if (syncEngine) {
                                                         [syncEngine start];
                                                         printf("Sync engine started (upstream: %s)\n", [upstreamURL UTF8String]);
                                                     }
                                                     printf("PLC server listening on port %lu\n", (unsigned long)port);
                                                     printf("Use --help for options, 'repl' for interactive mode\n");
                                                 }
                                         announceSignals:NO];
    }
    return 0;
}
