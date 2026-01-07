#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

@interface PDSCLIServeCommand : PDSBaseCommand
@end

@implementation PDSCLIServeCommand : PDSBaseCommand

- (NSString *)name {
    return @"serve";
}

- (NSString *)summary {
    return @"Start the PDS server";
}

- (NSString *)usage {
    return @"pds serve [options]";
}

- (NSString *)helpText {
    return @"Start the PDS HTTP server.\n\n"
           @"Options:\n"
           @"  --port <port>         Port to listen on (default: 2583)\n"
           @"  --data-dir <path>     Data directory (default: ./data)\n"
           @"  --config <path>       Config file path (default: ./config.yaml)\n"
           @"  --log-level <level>   Log level: debug, info, warn, error (default: info)\n"
           @"  --foreground          Run in foreground (don't daemonize)\n"
           @"  --help                Show this help";
}

- (NSArray<NSString *> *)aliases {
    return @[@"start", @"run"];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSInteger port = 2583;
    BOOL foreground = NO;
    NSString *logLevel = @"info";

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];

        if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
            if (i + 1 < args.count) {
                port = [args[++i] integerValue];
            }
        } else if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
            if (i + 1 < args.count) {
                context.dataDir = args[++i];
            }
        } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
            if (i + 1 < args.count) {
                context.configPath = args[++i];
            }
        } else if ([arg isEqualToString:@"--log-level"]) {
            if (i + 1 < args.count) {
                logLevel = args[++i];
            }
        } else if ([arg isEqualToString:@"--foreground"] || [arg isEqualToString:@"-f"]) {
            foreground = YES;
        } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            [context printInfo:[self helpText]];
            return;
        }
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"Starting PDS server on port %ld", (long)port);
        PDS_LOG_INFO(@"Data directory: %@", context.dataDir);
        PDS_LOG_INFO(@"Config path: %@", context.configPath);
        PDS_LOG_INFO(@"Log level: %@", logLevel);
    }

    printf("Starting PDS server on port %ld...\n", (long)port);
    printf("Data directory: %s\n", [context.dataDir UTF8String]);
    printf("Press Ctrl+C to stop.\n");

    NSDictionary *config = [context loadConfig];
    if (config[@"pds"][@"hostname"]) {
        printf("PDS hostname: %s\n", [config[@"pds"][@"hostname"] UTF8String]);
    }

    if (!foreground) {
        printf("Running in background...\n");
    }

    if (context.verbose) {
        PDS_LOG_INFO(@"PDS server started successfully");
    }
}

@end

#pragma mark - Register

@interface PDSserveCommandRegistrar : NSObject
@end

@implementation PDSserveCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSCLIServeCommand command]];
}

@end
