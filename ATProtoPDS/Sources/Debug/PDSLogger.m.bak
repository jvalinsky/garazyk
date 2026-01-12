#import "Debug/PDSLogger.h"

@interface PDSLogger ()
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@end

@implementation PDSLogger

+ (instancetype)sharedLogger {
    static PDSLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PDSLogger alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logLevel = PDSLogLevelDebug;
        _printToStdout = YES;
        _logQueue = dispatch_queue_create("com.atproto.pds.logger", DISPATCH_QUEUE_SERIAL);
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
        _dateFormatter = formatter;
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

- (void)logWithLevel:(PDSLogLevel)level
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

- (void)logWithLevel:(PDSLogLevel)level
            formatted:(NSString *)formatted
                file:(const char *)file
                line:(NSInteger)line {
    dispatch_sync(self.logQueue, ^{
        NSString *timestamp = [self.dateFormatter stringFromDate:[NSDate date]];
        NSString *levelString = [self levelString:level];
        NSString *fileName = [NSString stringWithUTF8String:file];
        NSString *fileBaseName = [fileName lastPathComponent];
        NSString *logMessage = [NSString stringWithFormat:@"[%@] [%@] [%@:%ld] %@",
                                timestamp, levelString, fileBaseName, (long)line, formatted];
        
        if (self.printToStdout) {
            fprintf(stdout, "%s\n", [logMessage UTF8String]);
            fflush(stdout);
        }
        
        if (self.logFileHandle) {
            NSString *lineWithNewline = [logMessage stringByAppendingString:@"\n"];
            [self.logFileHandle writeData:[lineWithNewline dataUsingEncoding:NSUTF8StringEncoding]];
        }
    });
}

- (NSString *)levelString:(PDSLogLevel)level {
    switch (level) {
        case PDSLogLevelDebug: return @"DEBUG";
        case PDSLogLevelInfo:  return @"INFO";
        case PDSLogLevelWarn:  return @"WARN";
        case PDSLogLevelError: return @"ERROR";
    }
    return @"UNKNOWN";
}

- (void)flush {
    dispatch_sync(self.logQueue, ^{
        [self.logFileHandle synchronizeFile];
    });
}

@end
