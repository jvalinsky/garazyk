// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSCLIDefinitions.h"
#import "PDSCLIInputHelper.h"
#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <signal.h>
#import <sys/errno.h>
#import <sys/stat.h>
#import <unistd.h>
#if defined(__APPLE__)
#import <mach-o/dyld.h>
#endif

#pragma mark - Daemon Command

@interface PDSCLIDaemonCommand : PDSBaseCommand
@end

@implementation PDSCLIDaemonCommand

- (NSString *)name {
    return @"daemon";
}

- (NSString *)summary {
    return @"Background process management for the PDS";
}

- (NSString *)usage {
    return @"kaszlak daemon start|stop|restart|status [options]";
}

- (NSString *)helpText {
    return @"Manage the PDS as a background process.\n\n"
           @"Subcommands:\n"
           @"  start      Start the PDS in the background\n"
           @"  stop       Stop the background PDS process\n"
           @"  restart    Stop and then start the PDS\n"
           @"  status     Check if the PDS is running\n\n"
           @"Options:\n"
           @"  --config <path>    Config file to use (default: ./config.json)\n"
           @"  --data-dir <path>  Data directory (default: from config)";
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    if (args.count == 0) {
        [context printInfo:[self helpText]];
        return 0;
    }

    NSString *subcommand = args[0];
    NSArray *subArgs = args.count > 1 ? [args subarrayWithRange:NSMakeRange(1, args.count - 1)] : @[];
    
    // Parse config/data-dir for all subcommands
    NSString *configPath = @"config.json";
    NSString *dataDir = context.dataDir;
    
    for (NSUInteger i = 0; i < subArgs.count; i++) {
        NSString *arg = subArgs[i];
        if ([arg isEqualToString:@"--config"] && i + 1 < subArgs.count) {
            configPath = subArgs[++i];
        } else if ([arg isEqualToString:@"--data-dir"] && i + 1 < subArgs.count) {
            dataDir = subArgs[++i];
        }
    }

    if ([subcommand isEqualToString:@"start"]) {
        return [self startDaemonWithConfig:configPath dataDir:dataDir context:context];
    } else if ([subcommand isEqualToString:@"stop"]) {
        return [self stopDaemonWithDataDir:dataDir context:context];
    } else if ([subcommand isEqualToString:@"restart"]) {
        [self stopDaemonWithDataDir:dataDir context:context];
        [NSThread sleepForTimeInterval:1.5];
        return [self startDaemonWithConfig:configPath dataDir:dataDir context:context];
    } else if ([subcommand isEqualToString:@"status"]) {
        return [self statusDaemonWithDataDir:dataDir context:context];
    } else {
        [context printError:[NSString stringWithFormat:@"Unknown subcommand: %@", subcommand]];
        return 1;
    }
}

- (int)startDaemonWithConfig:(NSString *)configPath dataDir:(NSString *)dataDir context:(PDSCLICommandContext *)context {
    NSString *pidPath = [dataDir stringByAppendingPathComponent:@"pds.pid"];
    NSString *logPath = [dataDir stringByAppendingPathComponent:@"pds-daemon.log"];
    
    // 1. Check if already running
    pid_t existingPid = [self readPidFromFile:pidPath];
    if (existingPid > 0 && kill(existingPid, 0) == 0) {
        [context printInfo:[NSString stringWithFormat:@"PDS is already running (PID: %d)", existingPid]];
        return 0;
    }

    // 2. Get own executable path
    char execPath[1024];
    uint32_t size = sizeof(execPath);
#if defined(__APPLE__)
    if (_NSGetExecutablePath(execPath, &size) != 0) {
        [context printError:@"Failed to get executable path"];
        return 1;
    }
#else
    ssize_t len = readlink("/proc/self/exe", execPath, sizeof(execPath) - 1);
    if (len != -1) {
        execPath[len] = '\0';
    } else {
        [context printError:@"Failed to get executable path"];
        return 1;
    }
#endif

    printf("Starting kaszlak daemon...\n");
    printf("  Log file: %s\n", [logPath UTF8String]);

    // 3. Fork
    pid_t pid = fork();
    if (pid < 0) {
        [context printError:@"Fork failed"];
        return 1;
    }

    if (pid == 0) { // Child
        // Create new session
        setsid();
        
        // Redirect stdout/stderr to log file
        int fd = open([logPath UTF8String], O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd != -1) {
            dup2(fd, STDOUT_FILENO);
            dup2(fd, STDERR_FILENO);
            close(fd);
        }
        
        // Close stdin
        int nullFd = open("/dev/null", O_RDONLY);
        if (nullFd != -1) {
            dup2(nullFd, STDIN_FILENO);
            close(nullFd);
        }

        // Arguments for execv
        // kaszlak serve --config <path> --data-dir <path>
        const char *argv[] = {
            execPath,
            "serve",
            "--config", [configPath UTF8String],
            "--data-dir", [dataDir UTF8String],
            NULL
        };
        
        execv(execPath, (char *const *)argv);
        exit(1); // Should never reach here
    }

    // Parent
    // 4. Write PID file
    NSString *pidStr = [NSString stringWithFormat:@"%d", pid];
    [pidStr writeToFile:pidPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // 5. Verify it's alive after a short delay
    [NSThread sleepForTimeInterval:0.5];
    if (kill(pid, 0) == 0) {
        [context printInfo:[NSString stringWithFormat:@"kaszlak started in background (PID: %d)", pid]];
        return 0;
    } else {
        [context printError:@"Process failed to start. Check pds-daemon.log for details."];
        return 1;
    }
}

- (int)stopDaemonWithDataDir:(NSString *)dataDir context:(PDSCLICommandContext *)context {
    NSString *pidPath = [dataDir stringByAppendingPathComponent:@"pds.pid"];
    pid_t pid = [self readPidFromFile:pidPath];
    
    if (pid <= 0 || kill(pid, 0) != 0) {
        [context printInfo:@"kaszlak is not running."];
        [[NSFileManager defaultManager] removeItemAtPath:pidPath error:nil];
        return 0;
    }

    printf("Stopping kaszlak (PID: %d)...\n", pid);
    
    // SIGTERM
    kill(pid, SIGTERM);
    
    // Wait up to 10 seconds
    for (int i = 0; i < 20; i++) {
        [NSThread sleepForTimeInterval:0.5];
        if (kill(pid, 0) != 0) {
            printf("✅ Process stopped.\n");
            [[NSFileManager defaultManager] removeItemAtPath:pidPath error:nil];
            return 0;
        }
    }
    
    // SIGKILL as last resort
    printf("⚠️  Process did not exit gracefully, sending SIGKILL.\n");
    kill(pid, SIGKILL);
    [[NSFileManager defaultManager] removeItemAtPath:pidPath error:nil];
    
    return 0;
}

- (int)statusDaemonWithDataDir:(NSString *)dataDir context:(PDSCLICommandContext *)context {
    NSString *pidPath = [dataDir stringByAppendingPathComponent:@"pds.pid"];
    NSString *logPath = [dataDir stringByAppendingPathComponent:@"pds-daemon.log"];
    pid_t pid = [self readPidFromFile:pidPath];
    BOOL running = (pid > 0 && kill(pid, 0) == 0);
    
    if (context.jsonOutput) {
        [context printJSON:@{
            @"running": @(running),
            @"pid": running ? @(pid) : @(0),
            @"pid_file": pidPath,
            @"log_file": logPath
        }];
    } else {
        if (running) {
            printf("kaszlak status: RUNNING\n");
            printf("  PID:      %d\n", pid);
        } else {
            printf("kaszlak status: STOPPED\n");
        }
        printf("  PID file: %s\n", [pidPath UTF8String]);
        printf("  Log file: %s\n", [logPath UTF8String]);
    }
    
    return running ? 0 : 3;
}

- (pid_t)readPidFromFile:(NSString *)path {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) return 0;
    return (pid_t)[content integerValue];
}

@end

#pragma mark - Register

@interface PDSDaemonCommandRegistrar : NSObject
@end

@implementation PDSDaemonCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[[PDSCLIDaemonCommand alloc] init]];
}

@end
