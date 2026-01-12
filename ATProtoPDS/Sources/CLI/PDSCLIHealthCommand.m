#import "PDSCLIDefinitions.h"
#import "Debug/PDSLogger.h"

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

    NSDate *start = [NSDate date];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL connected = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *dbPath = config[@"database"][@"path"] ?: [context.dataDir stringByAppendingPathComponent:@"pds.db"];

        if ([[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
            connected = YES;
        }

        dispatch_semaphore_signal(sem);
    });

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));

    NSTimeInterval latency = [[NSDate date] timeIntervalSinceDate:start] * 1000;
    result[@"latency_ms"] = @(round(latency));

    if (!connected) {
        result[@"status"] = @"error";
        result[@"message"] = @"Database connection failed";
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
    return result;
#endif

    return result;
}

@end

#pragma mark - Health Command

@interface PDSCLIHealthCommand : PDSBaseCommand
@end

@implementation PDSCLIHealthCommand : PDSBaseCommand

- (NSString *)name {
    return @"health";
}

- (NSString *)summary {
    return @"Check PDS health status";
}

- (NSString *)usage {
    return @"pds health [options]";
}

- (NSString *)helpText {
    return @"Check the health of the PDS. Returns basic or detailed health status.\n\n"
           @"Options:\n"
           @"  --verbose    Show detailed health information\n"
           @"  --json       Output in JSON format";
}

- (NSArray<NSString *> *)aliases {
    return @[@"status"];
}

- (NSArray<NSString *> *)subcommands {
    return @[];
}

- (void)executeWithArguments:(NSArray<NSString *> *)args context:(PDSCLICommandContext *)context {
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
        printf("PDS Status: %s\n", [status UTF8String]);
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
