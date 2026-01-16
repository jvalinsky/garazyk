#import "CLI/PDSCLIDefinitions.h"
#import "Admin/PDSInstallerCommand.h"
#import "Debug/PDSLogger.h"
#import <Foundation/Foundation.h>

static NSString * const kDaemonPlistName = @"com.atproto.pds.plist";
static NSString * const kAgentPlistName = @"com.atproto.pds.user.plist";
static NSString * const kDaemonPlistSource = @"Resources/LaunchDaemons/com.atproto.pds.plist";
static NSString * const kAgentPlistSource = @"Resources/LaunchAgents/com.atproto.pds.user.plist";

@implementation PDSInstallerCommand : PDSBaseCommand

- (NSString *)name {
    return @"install";
}

- (NSString *)summary {
    return @"Install/uninstall service or manage installation";
}

- (NSString *)usage {
    return @"pds install [daemon|agent|all] [--force]";
}

- (NSString *)helpText {
    return @"Install or configure the PDS service.\n\n"
           @"Subcommands:\n"
           @"  daemon    Install system-wide LaunchDaemon (requires root)\n"
           @"  agent     Install user-level LaunchAgent\n"
           @"  all       Install both daemon and agent (default)\n"
           @"  uninstall Remove service installation\n"
           @"  service   Control service (start|stop|restart|logs)\n"
           @"  status    Show service installation status\n\n"
           @"Options:\n"
           @"  --force    Overwrite existing configuration\n"
           @"  --help     Show this help\n\n"
           @"Examples:\n"
           @"  pds install agent                    # Install for current user\n"
           @"  pds install daemon --force           # Reinstall system daemon\n"
           @"  sudo pds install all                 # Install everything (root required)\n"
           @"  pds install uninstall --purge        # Remove everything";
}

- (NSArray<NSString *> *)subcommands {
    return @[@"daemon", @"agent", @"uninstall", @"service", @"service-status"];
}

- (id<PDSCLICommand>)subcommandForName:(NSString *)name {
    if ([name isEqualToString:@"uninstall"]) {
        return [PDSUninstallerCommand command];
    }
    if ([name isEqualToString:@"service"]) {
        return [PDSServiceCommand command];
    }
    if ([name isEqualToString:@"service-status"] || [name isEqualToString:@"ss"] || [name isEqualToString:@"instatus"]) {
        return [PDSServiceStatusCommand command];
    }
    return nil;
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    BOOL installDaemon = NO;
    BOOL installAgent = NO;
    BOOL force = NO;

    NSString *subcommand = nil;
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];

        if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            [context printInfo:[self helpText]];
            return;
        } else if ([arg isEqualToString:@"--force"]) {
            force = YES;
        } else if ([arg isEqualToString:@"daemon"]) {
            installDaemon = YES;
            installAgent = NO;
        } else if ([arg isEqualToString:@"agent"]) {
            installDaemon = NO;
            installAgent = YES;
        } else if ([arg isEqualToString:@"all"]) {
            installDaemon = YES;
            installAgent = YES;
        } else if ([arg hasPrefix:@"-"]) {
            [context printError:[NSString stringWithFormat:@"Unknown option: %@", arg]];
            return;
        } else if (!subcommand) {
            subcommand = arg;
        }
    }

    if (!installDaemon && !installAgent) {
        installDaemon = YES;
        installAgent = YES;
    }

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *resourcePath = [bundle resourcePath];

    if (installDaemon) {
        if (![self installDaemonWithResourcePath:resourcePath force:force context:context]) {
            return;
        }
    }

    if (installAgent) {
        if (![self installAgentWithResourcePath:resourcePath force:force context:context]) {
            return;
        }
    }

    [context printInfo:@"Installation complete. Use 'pds service status' to check service state."];
}

- (BOOL)installDaemonWithResourcePath:(NSString *)resourcePath force:(BOOL)force context:(PDSCLICommandContext *)context {
    NSString *sourcePlist = [resourcePath stringByAppendingPathComponent:kDaemonPlistSource];
    NSString *destPlist = @"/Library/LaunchDaemons/com.atproto.pds.plist";
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:sourcePlist]) {
        [context printError:[NSString stringWithFormat:@"Daemon plist not found: %@", sourcePlist]];
        return NO;
    }

    if ([fm fileExistsAtPath:destPlist] && !force) {
        [context printError:@"Daemon already installed. Use --force to overwrite."];
        return NO;
    }

    NSError *error = nil;
    NSData *plistData = [NSData dataWithContentsOfFile:sourcePlist options:0 error:&error];
    if (!plistData) {
        [context printError:[NSString stringWithFormat:@"Failed to read plist: %@", error.localizedDescription]];
        return NO;
    }

    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistData
                                                                           options:NSPropertyListMutableContainers
                                                                            format:NULL
                                                                             error:&error];
    if (!plist) {
        [context printError:[NSString stringWithFormat:@"Failed to parse plist: %@", error.localizedDescription]];
        return NO;
    }

    NSString *executablePath = @"/usr/local/bin/september";
    NSMutableArray *args = [plist[@"ProgramArguments"] mutableCopy];
    if (args.count > 0) {
        args[0] = executablePath;
    }
    plist[@"ProgramArguments"] = args;

    NSData *newPlistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                     format:NSPropertyListXMLFormat_v1_0
                                                                    options:0
                                                                      error:&error];
    if (!newPlistData) {
        [context printError:[NSString stringWithFormat:@"Failed to serialize plist: %@", error.localizedDescription]];
        return NO;
    }

    if ([fm fileExistsAtPath:destPlist]) {
        if (![fm removeItemAtPath:destPlist error:&error]) {
            [context printError:[NSString stringWithFormat:@"Failed to remove existing plist: %@", error.localizedDescription]];
            return NO;
        }
    }

    if (![newPlistData writeToFile:destPlist options:NSDataWritingAtomic error:&error]) {
        [context printError:[NSString stringWithFormat:@"Failed to write plist: %@", error.localizedDescription]];
        return NO;
    }

    if (![fm setAttributes:@{NSFileOwnerAccountName: @"root", NSFileGroupOwnerAccountName: @"wheel"}
              ofItemAtPath:destPlist
                     error:&error]) {
        PDS_LOG_WARN(@"Failed to set plist ownership: %@", error.localizedDescription);
    }

    [context printInfo:[NSString stringWithFormat:@"Installed LaunchDaemon to %@", destPlist]];

    NSString *loadCmd = [NSString stringWithFormat:@"launchctl load %@", destPlist];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", loadCmd];

    @try {
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus == 0) {
            [context printInfo:@"Started LaunchDaemon"];
        } else {
            PDS_LOG_WARN(@"Failed to load daemon (may already be loaded or require manual intervention)");
        }
    } @catch (NSException *e) {
        PDS_LOG_WARN(@"Could not auto-load daemon: %@", e.reason);
    }

    return YES;
}

- (BOOL)installAgentWithResourcePath:(NSString *)resourcePath force:(BOOL)force context:(PDSCLICommandContext *)context {
    NSString *sourcePlist = [resourcePath stringByAppendingPathComponent:kAgentPlistSource];
    NSString *destDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];
    NSString *destPlist = [destDir stringByAppendingPathComponent:kAgentPlistName];
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:sourcePlist]) {
        [context printError:[NSString stringWithFormat:@"Agent plist not found: %@", sourcePlist]];
        return NO;
    }

    NSError *error = nil;
    if (![fm fileExistsAtPath:destDir]) {
        if (![fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:&error]) {
            [context printError:[NSString stringWithFormat:@"Failed to create LaunchAgents directory: %@", error.localizedDescription]];
            return NO;
        }
    }

    if ([fm fileExistsAtPath:destPlist] && !force) {
        [context printError:@"Agent already installed. Use --force to overwrite."];
        return NO;
    }

    if (![fm copyItemAtPath:sourcePlist toPath:destPlist error:&error]) {
        [context printError:[NSString stringWithFormat:@"Failed to copy plist: %@", error.localizedDescription]];
        return NO;
    }

    [context printInfo:[NSString stringWithFormat:@"Installed LaunchAgent to %@", destPlist]];

    NSString *loadCmd = [NSString stringWithFormat:@"launchctl load %@", destPlist];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", loadCmd];

    @try {
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus == 0) {
            [context printInfo:@"Started LaunchAgent"];
        } else {
            PDS_LOG_WARN(@"Failed to load agent (may already be loaded or require manual intervention)");
        }
    } @catch (NSException *e) {
        PDS_LOG_WARN(@"Could not auto-load agent: %@", e.reason);
    }

    return YES;
}

@end

#pragma mark - Uninstaller

@implementation PDSUninstallerCommand : PDSBaseCommand

- (NSString *)name {
    return @"uninstall";
}

- (NSString *)summary {
    return @"Remove service installation";
}

- (NSString *)usage {
    return @"pds uninstall [daemon|agent|all] [--purge]";
}

- (NSString *)helpText {
    return @"Uninstall the PDS service.\n\n"
           @"Subcommands:\n"
           @"  daemon    Uninstall system-wide LaunchDaemon (requires root)\n"
           @"  agent     Uninstall user-level LaunchAgent\n"
           @"  all       Uninstall both (default)\n\n"
           @"Options:\n"
           @"  --purge   Also remove data directory and configuration\n"
           @"  --help    Show this help\n\n"
           @"Warning: --purge will delete all PDS data!";
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    BOOL uninstallDaemon = NO;
    BOOL uninstallAgent = NO;
    BOOL purge = NO;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];

        if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            [context printInfo:[self helpText]];
            return;
        } else if ([arg isEqualToString:@"--purge"]) {
            purge = YES;
        } else if ([arg isEqualToString:@"daemon"]) {
            uninstallDaemon = YES;
            uninstallAgent = NO;
        } else if ([arg isEqualToString:@"agent"]) {
            uninstallDaemon = NO;
            uninstallAgent = YES;
        } else if ([arg isEqualToString:@"all"]) {
            uninstallDaemon = YES;
            uninstallAgent = YES;
        }
    }

    if (!uninstallDaemon && !uninstallAgent) {
        uninstallDaemon = YES;
        uninstallAgent = YES;
    }

    NSFileManager *fm = [NSFileManager defaultManager];

    if (uninstallDaemon) {
        NSString *plist = @"/Library/LaunchDaemons/com.atproto.pds.plist";
        if ([fm fileExistsAtPath:plist]) {
            NSTask *stopTask = [[NSTask alloc] init];
            stopTask.launchPath = @"/bin/bash";
            stopTask.arguments = @[@"-c", @"launchctl unload /Library/LaunchDaemons/com.atproto.pds.plist 2>/dev/null || true"];

            @try {
                [stopTask launch];
                [stopTask waitUntilExit];
            } @catch (NSException *e) {
                PDS_LOG_WARN(@"Could not stop daemon: %@", e.reason);
            }

            NSError *error = nil;
            if ([fm removeItemAtPath:plist error:&error]) {
                [context printInfo:@"Uninstalled LaunchDaemon"];
            } else {
                [context printError:[NSString stringWithFormat:@"Failed to remove daemon plist: %@", error.localizedDescription]];
            }
        } else {
            [context printInfo:@"Daemon not installed"];
        }
    }

    if (uninstallAgent) {
        NSString *plist = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.atproto.pds.user.plist"];
        if ([fm fileExistsAtPath:plist]) {
            NSTask *stopTask = [[NSTask alloc] init];
            stopTask.launchPath = @"/bin/bash";
            stopTask.arguments = @[@"-c", @"launchctl unload ~/Library/LaunchAgents/com.atproto.pds.user.plist 2>/dev/null || true"];

            @try {
                [stopTask launch];
                [stopTask waitUntilExit];
            } @catch (NSException *e) {
                PDS_LOG_WARN(@"Could not stop agent: %@", e.reason);
            }

            NSError *error = nil;
            if ([fm removeItemAtPath:plist error:&error]) {
                [context printInfo:@"Uninstalled LaunchAgent"];
            } else {
                [context printError:[NSString stringWithFormat:@"Failed to remove agent plist: %@", error.localizedDescription]];
            }
        } else {
            [context printInfo:@"Agent not installed"];
        }
    }

    if (purge) {
        NSString *dataDir = context.dataDir ?: @"~/.config/september";
        dataDir = [dataDir stringByExpandingTildeInPath];

        if ([fm fileExistsAtPath:dataDir]) {
            NSError *error = nil;
            if ([fm removeItemAtPath:dataDir error:&error]) {
                [context printInfo:[NSString stringWithFormat:@"Purged data directory: %@", dataDir]];
            } else {
                [context printError:[NSString stringWithFormat:@"Failed to purge data: %@", error.localizedDescription]];
            }
        }
    }

    [context printInfo:@"Uninstallation complete."];
}

@end

#pragma mark - Service Command

@implementation PDSServiceCommand : PDSBaseCommand

- (NSString *)name {
    return @"service";
}

- (NSString *)summary {
    return @"Control service (start|stop|restart|logs)";
}

- (NSString *)usage {
    return @"pds service <start|stop|restart|logs> [--follow]";
}

- (NSString *)helpText {
    return @"Control the PDS service.\n\n"
           @"Subcommands:\n"
           @"  start     Start the service\n"
           @"  stop      Stop the service\n"
           @"  restart   Restart the service\n"
           @"  logs      Show service logs\n\n"
           @"Options:\n"
           @"  --follow  Follow log output (tail -f mode)\n"
           @"  --help    Show this help";
}

- (NSArray<NSString *> *)aliases {
    return @[@"svc"];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSString *action = nil;
    BOOL follow = NO;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];

        if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
            [context printInfo:[self helpText]];
            return;
        } else if ([arg isEqualToString:@"--follow"] || [arg isEqualToString:@"-f"]) {
            follow = YES;
        } else if (!action) {
            action = arg;
        }
    }

    if (!action) {
        [context printError:@"Missing service action (start|stop|restart|logs)"];
        return;
    }

    NSString *serviceLabel = @"com.atproto.pds.user";
    NSString *daemonLabel = @"com.atproto.pds";
    NSString *logPath = nil;

    if ([action isEqualToString:@"logs"]) {
        logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/september/agent.log"];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:logPath]) {
            logPath = @"/var/db/september/log/daemon.log";
        }

        if ([fm fileExistsAtPath:logPath]) {
            NSError *error = nil;
            NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&error];
            if (content) {
                printf("%s", [content UTF8String]);
            } else {
                [context printError:[NSString stringWithFormat:@"Failed to read logs: %@", error.localizedDescription]];
            }
        } else {
            [context printInfo:@"No log file found"];
        }
        return;
    }

    NSString *labelToUse = [self getLoadedServiceLabel:context];
    if (!labelToUse) {
        labelToUse = serviceLabel;
    }

    NSString *launchctlCmd = nil;
    if ([action isEqualToString:@"start"]) {
        launchctlCmd = [NSString stringWithFormat:@"launchctl start %@", labelToUse];
    } else if ([action isEqualToString:@"stop"]) {
        launchctlCmd = [NSString stringWithFormat:@"launchctl stop %@", labelToUse];
    } else if ([action isEqualToString:@"restart"]) {
        launchctlCmd = [NSString stringWithFormat:@"launchctl stop %@; launchctl start %@", labelToUse, labelToUse];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown action: %@", action]];
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", launchctlCmd];

    @try {
        [task launch];
        [task waitUntilExit];

        if (task.terminationStatus == 0) {
            [context printInfo:[NSString stringWithFormat:@"Service %@ed", action]];
        } else {
            [context printError:[NSString stringWithFormat:@"Failed to %@ service (may not be loaded)", action]];
        }
    } @catch (NSException *e) {
        [context printError:[NSString stringWithFormat:@"Failed to %@ service: %@", action, e.reason]];
    }
}

- (NSString *)getLoadedServiceLabel:(PDSCLICommandContext *)context {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", @"launchctl list | grep -E 'com\\.atproto\\.pds' | head -1 | awk '{print $3}'"];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];

        NSFileHandle *readHandle = [pipe fileHandleForReading];
        NSData *data = [readHandle readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (output.length > 0) {
            return output;
        }
    } @catch (NSException *e) {
        PDS_LOG_WARN(@"Could not query launchctl: %@", e.reason);
    }

    return nil;
}

@end

#pragma mark - Status Command

@implementation PDSServiceStatusCommand : PDSBaseCommand

- (NSString *)name {
    return @"service-status";
}

- (NSString *)summary {
    return @"Show service installation and running status";
}

- (NSString *)usage {
    return @"pds service-status";
}

- (NSString *)helpText {
    return @"Show the installation and running status of the PDS service.";
}

- (NSArray<NSString *> *)aliases {
    return @[@"ss", @"instatus"];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *agentPlist = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents/com.atproto.pds.user.plist"];
    status[@"agentInstalled"] = @([fm fileExistsAtPath:agentPlist]);

    NSString *daemonPlist = @"/Library/LaunchDaemons/com.atproto.pds.plist";
    status[@"daemonInstalled"] = @([fm fileExistsAtPath:daemonPlist]);

    status[@"agentLoaded"] = @([self isServiceLoaded:@"com.atproto.pds.user"]);
    status[@"daemonLoaded"] = @([self isServiceLoaded:@"com.atproto.pds"]);

    status[@"dataDirectory"] = context.dataDir ?: @"~/.config/september";
    status[@"configPath"] = context.configPath ?: @"./config.json";

    if ([fm fileExistsAtPath:[status[@"dataDirectory"] stringByExpandingTildeInPath]]) {
        status[@"dataExists"] = @YES;
    } else {
        status[@"dataExists"] = @NO;
    }

    if (context.jsonOutput) {
        [context printJSON:status];
    } else {
        printf("PDS Service Status\n");
        printf("==================\n\n");
        printf("Agent (LaunchAgent):  %s\n", [status[@"agentInstalled"] boolValue] ? "Installed" : "Not installed");
        if ([status[@"agentInstalled"] boolValue]) {
            printf("  - Loaded:          %s\n", [status[@"agentLoaded"] boolValue] ? "Running" : "Stopped");
        }
        printf("Daemon (LaunchDaemon): %s\n", [status[@"daemonInstalled"] boolValue] ? "Installed" : "Not installed");
        if ([status[@"daemonInstalled"] boolValue]) {
            printf("  - Loaded:           %s\n", [status[@"daemonLoaded"] boolValue] ? "Running" : "Stopped");
        }
        printf("\n");
        printf("Data directory: %s\n", [[status[@"dataDirectory"] stringByExpandingTildeInPath] UTF8String]);
        printf("Config file:    %s\n", [[status[@"configPath"] stringByExpandingTildeInPath] UTF8String]);
        printf("Data present:   %s\n", [status[@"dataExists"] boolValue] ? "Yes" : "No");
    }
}

- (BOOL)isServiceLoaded:(NSString *)label {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", [NSString stringWithFormat:@"launchctl list | grep -q '%@'", label]];

    @try {
        [task launch];
        [task waitUntilExit];
        return task.terminationStatus == 0;
    } @catch (NSException *e) {
        return NO;
    }
}

@end

#pragma mark - Register

@interface PDSInstallerCommandRegistrar : NSObject
@end

@implementation PDSInstallerCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSInstallerCommand command]];
}

@end
