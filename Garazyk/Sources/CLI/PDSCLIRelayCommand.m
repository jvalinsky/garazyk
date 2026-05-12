// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CLI/PDSCLIRelayCommand.h"
#import "Sync/Relay/RelayConfiguration.h"
#import "Sync/Relay/RelayUpstreamManager.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Relay/RelayRepoStateManager.h"
#import "Sync/Relay/RelayEventBuffer.h"
#import "Debug/GZLogger.h"

@interface PDSCLIRelayCommand ()
@property (nonatomic, assign) BOOL running;
@end

@implementation PDSCLIRelayCommand

- (NSString *)name {
    return @"relay";
}

- (NSString *)summary {
    return @"Start the ATProto Relay service";
}

- (NSString *)usage {
    return @"kaszlak relay serve|start|stop|status|upstream [options]";
}

- (NSString *)helpText {
    return @"ATProto Relay (Sync v1.1) - Full network relaying.\n\n"
           @"Subcommands:\n"
           @"  serve           Start the relay HTTP/WS server\n"
           @"  start          Start relay in background\n"
           @"  stop           Stop the relay\n"
           @"  status         Show relay status\n"
           @"  upstream       Manage upstream PDS connections\n\n"
           @"Options:\n"
           @"  --port <port>      Downstream port (default: 2584)\n"
           @"  --upstream <url>   Upstream PDS URL (can repeat)\n"
           @"  --retention <hrs>  Event retention hours (default: 72)\n"
           @"  --mode <mode>      Validation mode: lenient, strict, logOnly\n"
           @"  --help             Show this help\n\n"
           @"Examples:\n"
           @"  kaszlak relay serve --upstream pds1.com --upstream pds2.com\n"
           @"  kaszlak relay serve --port 3000 --retention 48\n"
           @"  kaszlak relay status";
}

- (NSArray<NSString *> *)aliases {
    return @[ @"bgs", @"relayd" ];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args
                     context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];

    if ([subcommand isEqualToString:@"serve"] || [subcommand isEqualToString:@"start"]) {
        return [self executeServe:subArgs context:context];
    } else if ([subcommand isEqualToString:@"stop"]) {
        return [self executeStop:subArgs context:context];
    } else if ([subcommand isEqualToString:@"status"]) {
        return [self executeStatus:subArgs context:context];
    } else if ([subcommand isEqualToString:@"upstream"]) {
        return [self executeUpstream:subArgs context:context];
    } else if ([subcommand isEqualToString:@"help"]) {
        [context printInfo:[self helpText]];
        return 0;
    }

    [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
    return 1;
}

- (int)executeServe:(NSArray<NSString *> *)args
            context:(PDSCLICommandContext *)context {
    uint16_t port = 2584;
    NSMutableArray *upstreamURLs = [NSMutableArray array];
    NSUInteger retentionHours = 72;
    RelayValidationMode validationMode = RelayValidationModeLogOnly;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--port"] && i + 1 < args.count) {
            port = (uint16_t)[args[++i] integerValue];
        } else if ([arg isEqualToString:@"--upstream"] && i + 1 < args.count) {
            [upstreamURLs addObject:args[++i]];
        } else if ([arg isEqualToString:@"--retention"] && i + 1 < args.count) {
            retentionHours = (NSUInteger)[args[++i] integerValue];
        } else if ([arg isEqualToString:@"--mode"] && i + 1 < args.count) {
            NSString *mode = args[++i];
            if ([mode isEqualToString:@"lenient"]) {
                validationMode = RelayValidationModeLenient;
            } else if ([mode isEqualToString:@"strict"]) {
                validationMode = RelayValidationModeStrict;
            } else if ([mode isEqualToString:@"logOnly"]) {
                validationMode = RelayValidationModeLogOnly;
            }
        }
    }

    if (upstreamURLs.count == 0) {
        [context printError:@"At least one upstream PDS URL required (--upstream)"];
        return 1;
    }

    self.configuration = [[RelayConfiguration alloc] initWithUpstreamURLs:upstreamURLs
                                                              downstreamPort:port
                                                               retentionHours:retentionHours
                                                             validationMode:validationMode];

    self.metrics = [RelayMetrics sharedMetrics];
    self.repoStateManager = [[RelayRepoStateManager alloc] init];
    self.eventBuffer = [RelayEventBuffer bufferWithDefaultRetention];
    self.upstreamManager = [[RelayUpstreamManager alloc] initWithInitialURLs:upstreamURLs];

    GZ_LOG_INFO_C(@"Relay", @"Starting relay on port %d", port);
    GZ_LOG_INFO_C(@"Relay", @"Connecting to %lu upstream PDS(s)", (unsigned long)upstreamURLs.count);

    [self.upstreamManager connectAll];

    self.running = YES;

    while (self.running) {
        [NSThread sleepForTimeInterval:1.0];
    }

    [self.upstreamManager disconnectAll];
    GZ_LOG_INFO_C(@"Relay", @"Relay stopped");

    return 0;
}

- (int)executeStop:(NSArray<NSString *> *)args
            context:(PDSCLICommandContext *)context {
    self.running = NO;
    [context printInfo:@"Relay stopped"];
    return 0;
}

- (int)executeStatus:(NSArray<NSString *> *)args
             context:(PDSCLICommandContext *)context {
    [context printInfo:@"=== ATProto Relay Status ==="];
    [context printInfo:[NSString stringWithFormat:@"Status: %@", self.running ? @"Running" : @"Stopped"]];

    if (self.configuration) {
        [context printInfo:[NSString stringWithFormat:@"Port: %d", self.configuration.downstreamPort]];
        [context printInfo:[NSString stringWithFormat:@"Upstreams: %@", self.configuration.upstreamURLs]];
        [context printInfo:[NSString stringWithFormat:@"Retention: %lu hours", (unsigned long)self.configuration.retentionHours]];
    }

    if (self.metrics) {
        [context printInfo:[NSString stringWithFormat:@"Upstream connections: %lld", (long long)self.metrics.upstreamConnections]];
        [context printInfo:[NSString stringWithFormat:@"Events received: %lld", (long long)self.metrics.eventsReceived]];
        [context printInfo:[NSString stringWithFormat:@"Events forwarded: %lld", (long long)self.metrics.eventsForwarded]];
    }

    if (self.repoStateManager) {
        [context printInfo:[NSString stringWithFormat:@"Repos tracked: %lu", (unsigned long)[self.repoStateManager repoCount]]];
    }

    return 0;
}

- (int)executeUpstream:(NSArray<NSString *> *)args
               context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:@"Usage: kaszlak relay upstream add|remove|list [url]"];
        return 1;
    }

    NSString *action = args[0];

    if ([action isEqualToString:@"list"]) {
        if (self.upstreamManager) {
            NSArray *upstreams = [self.upstreamManager allUpstreams];
            [context printInfo:@"Upstream PDS connections:"];
            for (NSString *url in upstreams) {
                [context printInfo:[NSString stringWithFormat:@"  - %@", url]];
            }
        } else {
            [context printInfo:@"Relay not running"];
        }
    } else if ([action isEqualToString:@"add"] && args.count > 1) {
        NSString *url = args[1];
        [self.upstreamManager addUpstream:url];
        [context printInfo:[NSString stringWithFormat:@"Added upstream: %@", url]];
    } else if ([action isEqualToString:@"remove"] && args.count > 1) {
        NSString *url = args[1];
        [self.upstreamManager removeUpstream:url];
        [context printInfo:[NSString stringWithFormat:@"Removed upstream: %@", url]];
    } else {
        [context printInfo:@"Usage: kaszlak relay upstream add|remove|list [url]"];
    }

    return 0;
}

@end

#pragma mark - Register

@interface PDSRelayCommandRegistrar : NSObject
@end

@implementation PDSRelayCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSCLIRelayCommand command]];
}

@end
