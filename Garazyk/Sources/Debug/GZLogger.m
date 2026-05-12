// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Debug/GZLogger.h"
#import "Debug/GZLogRedactor.h"
#import "Compat/PDSTypes.h"

#if defined(__APPLE__) && __has_include(<os/log.h>)
#import <os/log.h>
#define PDS_HAS_OS_LOG 1
#endif

// Component constant definitions
NSString * const GZLogComponentDatabase = @"Database";
NSString * const GZLogComponentAuth = @"Auth";
NSString * const GZLogComponentHTTP = @"HTTP";
NSString * const GZLogComponentAdmin = @"Admin";
NSString * const GZLogComponentService = @"Service";
NSString * const GZLogComponentCore = @"Core";
NSString * const GZLogComponentBlob = @"Blob";
NSString * const GZLogComponentSync = @"Sync";
NSString * const GZLogComponentExplore = @"Explore";
NSString * const GZLogComponentCLI = @"CLI";

@interface GZLogger ()
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSDateFormatter *isoDateFormatter;
@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t logQueue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t ioQueue;
@property (nonatomic, strong) NSMutableArray<NSString *> *logBuffer;
@property (nonatomic, strong) NSTimer *flushTimer;
#if PDS_HAS_OS_LOG
@property (nonatomic, strong) NSMutableDictionary<NSString *, os_log_t> *osLogs;
#endif
// currentCorrelationID is now managed via thread-local storage to be thread-safe in concurrent environments
@end

@implementation GZLogger

+ (instancetype)sharedLogger {
    static GZLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GZLogger alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logLevel = GZLogLevelInfo; // Default to INFO for cleaner logs
        
        // Environment override during initialization
        NSString *envLevel = [[[NSProcessInfo processInfo] environment][@"GZ_LOG_LEVEL"] lowercaseString];
        if (envLevel) {
            if ([envLevel isEqualToString:@"debug"]) _logLevel = GZLogLevelDebug;
            else if ([envLevel isEqualToString:@"info"]) _logLevel = GZLogLevelInfo;
            else if ([envLevel isEqualToString:@"warn"]) _logLevel = GZLogLevelWarn;
            else if ([envLevel isEqualToString:@"error"]) _logLevel = GZLogLevelError;
        }

        _printToStdout = YES;
        _logQueue = dispatch_queue_create("com.atproto.pds.logger", DISPATCH_QUEUE_SERIAL);
        _ioQueue = dispatch_queue_create("com.atproto.pds.logger.io", DISPATCH_QUEUE_SERIAL);

        // Default production-ready settings
        _logFormat = GZLogFormatText;
        _maxLogFileSize = 10 * 1024 * 1024; // 10MB
        _maxLogFiles = 5;
        _asyncLogging = NO; // Disable by default for debugging
        _enabledComponents = nil; // All components enabled by default

#if PDS_HAS_OS_LOG
        _osLogs = [NSMutableDictionary dictionary];
#endif
        _logBuffer = [[NSMutableArray alloc] init];

        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];

        _isoDateFormatter = [[NSDateFormatter alloc] init];
        [_isoDateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        [_isoDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];

        // Setup flush timer for async logging (flush every 1 second)
        __weak typeof(self) weakSelf = self;
/*
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.flushTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                   repeats:YES
                                                                     block:^(NSTimer * _Nonnull timer) {
                [weakSelf flush];
            }];
        });
*/
    }
    return self;
}

- (void)dealloc {
}

- (void)setLogFilePath:(NSString *)logFilePath {
    dispatch_sync(self.logQueue, ^{
        [self closeLogFile];
        
        if (logFilePath) {
            NSString *directory = [logFilePath stringByDeletingLastPathComponent];
            NSFileManager *fm = [NSFileManager defaultManager];
            if (![fm fileExistsAtPath:directory]) {
                [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
            }
            
            [[NSFileManager defaultManager] createFileAtPath:logFilePath contents:nil attributes:nil];
            self->_logFileHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
            if (self->_logFileHandle) {
                [self->_logFileHandle seekToEndOfFile];
            }
        }
        _logFilePath = [logFilePath copy];
    });
}

- (void)closeLogFile {
    [_logFileHandle closeFile];
    _logFileHandle = nil;
}

- (void)logWithLevel:(GZLogLevel)level
                file:(const char *)file
                line:(NSInteger)line
              format:(NSString *)format, ... {
    if (level < self.logLevel) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *formatted = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self logWithLevel:level formatted:formatted file:file line:line];
}

- (void)logWithLevel:(GZLogLevel)level
           component:(NSString *)component
                file:(const char *)file
                line:(NSInteger)line
              format:(NSString *)format, ... {
    if (level < self.logLevel) {
        return;
    }

    // Component filtering
    if (self.enabledComponents && ![self.enabledComponents containsObject:component]) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *formatted = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    [self logWithLevel:level formatted:formatted component:component file:file line:line];
}

- (void)logWithLevel:(GZLogLevel)level
            formatted:(NSString *)formatted
                file:(const char *)file
                line:(NSInteger)line {
    [self logWithLevel:level formatted:formatted component:nil file:file line:line];
}

- (void)logWithLevel:(GZLogLevel)level
            formatted:(NSString *)formatted
            component:(NSString *)component
                 file:(const char *)file
                 line:(NSInteger)line {
    // Redact sensitive values (tokens, secrets, passwords, cookies) before any output
    NSString *safeFormatted = [GZLogRedactor redactString:formatted];

    dispatch_async(self.logQueue, ^{
        @autoreleasepool {
        NSString *timestamp = [self.dateFormatter stringFromDate:[NSDate date]] ?: @"";
        NSString *levelString = [self levelString:level];
        NSString *fileName = [NSString stringWithUTF8String:file];
        NSString *fileBaseName = [fileName lastPathComponent];

        // Check if rotation is needed
        [self rotateLogIfNeeded];

#if PDS_HAS_OS_LOG
        [self logToOSLogWithLevel:level formatted:safeFormatted component:component];
#endif

        NSString *logMessage = nil;

        // Text format
        if (self.logFormat == GZLogFormatText || self.logFormat == GZLogFormatBoth) {
            NSMutableString *textMessage = [NSMutableString stringWithFormat:@"[%@] [%@]", timestamp, levelString];

            if (component) {
                [textMessage appendFormat:@" [%@]", component];
            }

            [textMessage appendFormat:@" [%@:%ld] %@", fileBaseName, (long)line, safeFormatted];

            NSString *corrID = self.correlationID;
            if (corrID) {
                [textMessage appendFormat:@" [%@]", corrID];
            }

            logMessage = textMessage;

            if (self.printToStdout) {
                fprintf(stdout, "%s\n", [logMessage UTF8String]);
                fflush(stdout);
            }

            if (self.asyncLogging) {
                dispatch_async(self.ioQueue, ^{
                    [self.logBuffer addObject:logMessage];
                    if (self.logBuffer.count >= 100 || level == GZLogLevelError) {
                        [self flushBufferSync];
                    }
                });
            } else {
                [self writeToFileSync:logMessage];
            }
        }

        // JSON format
        if (self.logFormat == GZLogFormatJSON || self.logFormat == GZLogFormatBoth) {
            NSMutableDictionary *jsonDict = [NSMutableDictionary dictionary];

            jsonDict[@"timestamp"] = [self.isoDateFormatter stringFromDate:[NSDate date]] ?: @"";

            jsonDict[@"level"] = levelString;

            if (component) {
                jsonDict[@"component"] = component;
            }

            jsonDict[@"message"] = safeFormatted;

            NSString *corrID = self.correlationID;
            if (corrID) {
                jsonDict[@"correlation_id"] = corrID;
            }

            // Add thread ID
            jsonDict[@"thread_id"] = [NSString stringWithFormat:@"0x%lx", (unsigned long)[NSThread currentThread].hash];

            jsonDict[@"file"] = fileBaseName;
            jsonDict[@"line"] = @(line);
            jsonDict[@"pid"] = @([[NSProcessInfo processInfo] processIdentifier]);

            NSError *error = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&error];

            if (jsonData) {
                NSString *jsonMessage = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

                if (self.printToStdout && self.logFormat == GZLogFormatJSON) {
                    fprintf(stdout, "%s\n", [jsonMessage UTF8String]);
                    fflush(stdout);
                }

                if (self.asyncLogging) {
                    dispatch_async(self.ioQueue, ^{
                        [self.logBuffer addObject:jsonMessage];
                        if (self.logBuffer.count >= 100 || level == GZLogLevelError) {
                            [self flushBufferSync];
                        }
                    });
                } else {
                    [self writeToFileSync:jsonMessage];
                }
            }
        }
    }
});
}

#if PDS_HAS_OS_LOG
- (void)logToOSLogWithLevel:(GZLogLevel)level
                  formatted:(NSString *)formatted
                  component:(NSString *)component {
    static os_log_t defaultLog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultLog = os_log_create("com.atproto.pds", "Default");
    });
    
    os_log_t log = defaultLog;
    if (component) {
        log = self.osLogs[component];
        if (!log) {
            log = os_log_create("com.atproto.pds", [component UTF8String]);
            self.osLogs[component] = log;
        }
    }
    
    os_log_type_t type = OS_LOG_TYPE_DEFAULT;
    switch (level) {
        case GZLogLevelDebug: type = OS_LOG_TYPE_DEBUG; break;
        case GZLogLevelInfo:  type = OS_LOG_TYPE_INFO; break;
        case GZLogLevelWarn:  type = OS_LOG_TYPE_DEFAULT; break;
        case GZLogLevelError: type = OS_LOG_TYPE_ERROR; break;
    }
    
    os_log_with_type(log, type, "%{public}@", formatted);
}
#endif

- (NSString *)levelString:(GZLogLevel)level {
    switch (level) {
        case GZLogLevelDebug: return @"DEBUG";
        case GZLogLevelInfo:  return @"INFO";
        case GZLogLevelWarn:  return @"WARN";
        case GZLogLevelError: return @"ERROR";
    }
    return @"UNKNOWN";
}

- (void)flush {
    if (self.asyncLogging) {
        dispatch_sync(self.ioQueue, ^{
            [self flushBufferSync];
        });
    }
    dispatch_sync(self.logQueue, ^{
        [self.logFileHandle synchronizeFile];
    });
}

- (void)flushBufferSync {
    if (self.logBuffer.count == 0) {
        return;
    }

    NSArray<NSString *> *messages = [self.logBuffer copy];
    [self.logBuffer removeAllObjects];

    for (NSString *message in messages) {
        [self writeToFileSync:message];
    }
}

- (void)writeToFileSync:(NSString *)message {
    if (self.logFileHandle) {
        NSString *lineWithNewline = [message stringByAppendingString:@"\n"];
        [self.logFileHandle writeData:[lineWithNewline dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

- (void)setCorrelationID:(NSString *)correlationID {
    if (correlationID) {
        [[NSThread currentThread] threadDictionary][@"GZLoggerCorrelationID"] = correlationID;
    } else {
        [[NSThread currentThread] threadDictionary] [@"GZLoggerCorrelationID"] = nil;
    }
}

- (void)clearCorrelationID {
    [[NSThread currentThread] threadDictionary][@"GZLoggerCorrelationID"] = nil;
}

- (NSString *)correlationID {
    return [[NSThread currentThread] threadDictionary][@"GZLoggerCorrelationID"];
}

- (void)rotateLogIfNeeded {
    if (!self.logFilePath) {
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:self.logFilePath error:nil];
    unsigned long long fileSize = [attrs fileSize];

    if (fileSize >= self.maxLogFileSize) {
        [self forceRotate];
    }
}

- (void)forceRotate {
    // Flush pending logs
    [self flush];

    // Close current file
    [self closeLogFile];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *basePath = self.logFilePath;

    // Delete oldest log
    NSString *oldestLog = [NSString stringWithFormat:@"%@.%lu", basePath, (unsigned long)self.maxLogFiles];
    [fm removeItemAtPath:oldestLog error:nil];

    // Rotate existing logs
    for (NSInteger i = self.maxLogFiles - 1; i >= 1; i--) {
        NSString *oldPath = (i == 1) ? basePath : [NSString stringWithFormat:@"%@.%ld", basePath, (long)(i - 1)];
        NSString *newPath = [NSString stringWithFormat:@"%@.%ld", basePath, (long)i];

        if ([fm fileExistsAtPath:oldPath]) {
            [fm moveItemAtPath:oldPath toPath:newPath error:nil];
        }
    }

    // Create new log file
    [[NSFileManager defaultManager] createFileAtPath:basePath contents:nil attributes:nil];
    self->_logFileHandle = [NSFileHandle fileHandleForWritingAtPath:basePath];
    if (self->_logFileHandle) {
        [self->_logFileHandle seekToEndOfFile];
    }

    // Log rotation event via simple NSLog to avoid recursion
    NSLog(@"[INFO] [Core] Log rotated (max size: %lu bytes, keeping %lu files)",
          (unsigned long)self.maxLogFileSize, (unsigned long)self.maxLogFiles);
}

@end
