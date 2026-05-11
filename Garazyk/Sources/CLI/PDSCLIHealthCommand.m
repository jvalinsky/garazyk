// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

#if defined(__APPLE__)
#import <mach/mach.h>
#endif

@interface PDSHealthChecker : NSObject

+ (NSDictionary *)checkHealthWithContext:(PDSCLICommandContext *)context;

@end

@implementation PDSHealthChecker

+ (NSDictionary *)checkHealthWithContext:(PDSCLICommandContext *)context {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";
    result[@"timestamp"] = @([[NSDate date] timeIntervalSince1970] * 1000);
    result[@"version"] = @"1.0.0";

    NSMutableDictionary *checks = [NSMutableDictionary dictionary];

    NSDictionary *config = [context loadConfig];

    checks[@"database"] = [self checkDatabase:context config:config];
    checks[@"storage"] = [self checkStorage:context config:config];
    checks[@"memory"] = [self checkMemory];
    checks[@"daemon"] = [self checkDaemon:context];
    checks[@"http"] = [self checkHTTP:context config:config];

    result[@"checks"] = checks;

    BOOL allOk = YES;
    for (NSString *key in checks) {
        NSDictionary *check = checks[key];
        if ([check[@"status"] isEqualToString:@"error"]) {
            allOk = NO;
            break;
        }
    }

    result[@"status"] = allOk ? @"ok" : @"degraded";

    return result;
}

+ (NSDictionary *)checkDatabase:(PDSCLICommandContext *)context config:(NSDictionary *)config {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";

    NSString *dataDir = context.dataDir;
    
    NSArray *requiredDbs = @[
        @"service/service.db",
        @"sequencer/service.db",
        @"did_cache/service.db"
    ];
    
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *dbRelPath in requiredDbs) {
        NSString *fullPath = [dataDir stringByAppendingPathComponent:dbRelPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
            [missing addObject:dbRelPath];
        }
    }

    if (missing.count > 0) {
        result[@"status"] = @"error";
        result[@"message"] = [NSString stringWithFormat:@"Missing databases: %@", [missing componentsJoinedByString:@", "]];
    }

    return result;
}

+ (NSDictionary *)checkDaemon:(PDSCLICommandContext *)context {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";

    NSString *pidPath = [context.dataDir stringByAppendingPathComponent:@"pds.pid"];
    NSString *pidContent = [NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil];
    
    if (pidContent) {
        pid_t pid = (pid_t)[pidContent integerValue];
        if (pid > 0 && kill(pid, 0) == 0) {
            result[@"pid"] = @(pid);
        } else {
            result[@"status"] = @"warn";
            result[@"message"] = @"PID file exists but process is not running";
        }
    } else {
        result[@"status"] = @"info";
        result[@"message"] = @"No background process detected";
    }

    return result;
}

+ (NSDictionary *)checkHTTP:(PDSCLICommandContext *)context config:(NSDictionary *)config {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";

    NSInteger port = [config[@"server"][@"port"] integerValue] ?: 2583;
    NSString *urlStr = [NSString stringWithFormat:@"http://localhost:%ld/xrpc/com.atproto.server.describeServer", (long)port];
    NSURL *url = [NSURL URLWithString:urlStr];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSInteger statusCode = 0;
    __block NSError *error = nil;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *taskError) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = [(NSHTTPURLResponse *)response statusCode];
        }
        error = taskError;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];

    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) {
        [task cancel];
        result[@"status"] = @"error";
        result[@"message"] = @"Timeout connecting to PDS";
    } else if (error) {
        result[@"status"] = @"error";
        result[@"message"] = [NSString stringWithFormat:@"Connection refused: %@", error.localizedDescription];
    } else if (statusCode != 200) {
        result[@"status"] = @"warn";
        result[@"message"] = [NSString stringWithFormat:@"Server returned status %ld", (long)statusCode];
    }

    return result;
}

+ (NSDictionary *)checkStorage:(PDSCLICommandContext *)context config:(NSDictionary *)config {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";

    NSString *blobsDir = config[@"storage"][@"blobs_dir"];
    if (!blobsDir) {
        blobsDir = [context.dataDir stringByAppendingPathComponent:@"blobs"];
    }

    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:blobsDir error:&error];

    if (error) {
        result[@"status"] = @"warn";
        result[@"message"] = @"Could not read storage stats";
    } else {
        unsigned long long freeSpace = [attrs[NSFileSystemFreeSize] unsignedLongLongValue];
        result[@"free_bytes"] = @(freeSpace);

        if (freeSpace < 100ULL * 1024 * 1024) {
            result[@"status"] = @"warn";
            result[@"message"] = @"Low disk space";
        }
    }

    return result;
}

+ (NSDictionary *)checkMemory {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"status"] = @"ok";

#if defined(__APPLE__)
    struct task_vm_info vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count);

    if (kr == KERN_SUCCESS) {
        unsigned long long usedBytes = vmInfo.phys_footprint;
        unsigned long long limitBytes = 1024ULL * 1024 * 1024;

        result[@"used_bytes"] = @(usedBytes);
        result[@"limit_bytes"] = @(limitBytes);
        double usageRatio = (double)usedBytes / (double)limitBytes;
        if (usedBytes > limitBytes * 0.9) {
            result[@"status"] = @"warn";
            result[@"message"] = @"High memory usage";
        }
    }
#else
    result[@"status"] = @"info";
    result[@"message"] = @"Memory footprint details unavailable on this platform";
#endif

    return result;
}

@end

#pragma mark - Health Command

@interface PDSCLIHealthCommand : PDSBaseCommand
@end

@implementation PDSCLIHealthCommand : PDSBaseCommand

- (NSString *)name {
    return @"status";
}

- (NSString *)summary {
    return @"Check kaszlak status";
}

- (NSString *)usage {
    return @"kaszlak status [options]";
}

- (NSString *)helpText {
    return @"Check kaszlak status. Returns basic or detailed health output.\n\n"
           @"Options:\n"
           @"  --verbose    Show detailed health information\n"
           @"  --json       Output in JSON format";
}

- (NSArray<NSString *> *)aliases {
    return @[@"health"];
}

- (NSArray<NSString *> *)subcommands {
    return @[];
}

- (int)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
    BOOL verbose = NO;

    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            verbose = YES;
        } else if ([arg isEqualToString:@"--json"] || [arg isEqualToString:@"-j"]) {
            context.jsonOutput = YES;
        }
    }

    NSDictionary *health = [PDSHealthChecker checkHealthWithContext:context];

    if (context.jsonOutput) {
        [context printJSON:health];
    } else {
        NSString *status = health[@"status"];
        printf("kaszlak status: %s\n", [status UTF8String]);
        printf("Version: %s\n", [health[@"version"] UTF8String]);

        if (verbose) {
            printf("\nDetailed Checks:\n");
            NSDictionary *checks = health[@"checks"];
            for (NSString *key in checks) {
                NSDictionary *check = checks[key];
                NSString *checkStatus = check[@"status"];
                printf("  %-12s %s", [key UTF8String], [checkStatus UTF8String]);

                if (check[@"latency_ms"]) {
                    printf(" (%.0fms)", [check[@"latency_ms"] doubleValue]);
                }
                printf("\n");

                if (check[@"message"]) {
                    printf("             %s\n", [check[@"message"] UTF8String]);
                }
            }
        }
    }
    return 0;
}

@end

#pragma mark - Register

@interface PDSHealthCommandRegistrar : NSObject
@end

@implementation PDSHealthCommandRegistrar

+ (void)load {
    [[PDSCLIDispatcher sharedDispatcher] addCommand:[PDSCLIHealthCommand command]];
}

@end
