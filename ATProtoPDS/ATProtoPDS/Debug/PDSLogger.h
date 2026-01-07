#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header PDSLogger.h
 
 @abstract Structured logging for the PDS.
 
 @discussion This header defines the PDSLogger class for structured
 logging with severity levels and file/line information.
 
 @copyright Copyright (c) 2024 Jack Myers
 */

/*!
 @enum PDSLogLevel
 
 @abstract Log severity levels.
 
 @constant PDSLogLevelDebug Debug-level messages (most verbose).
 @constant PDSLogLevelInfo Informational messages.
 @constant PDSLogLevelWarn Warning messages.
 @constant PDSLogLevelError Error messages (least verbose).
 */
typedef NS_ENUM(NSInteger, PDSLogLevel) {
    PDSLogLevelDebug = 0,
    PDSLogLevelInfo,
    PDSLogLevelWarn,
    PDSLogLevelError
};

/*!
 @class PDSLogger
 
 @abstract Provides structured logging for the PDS.
 
 @discussion PDSLogger supports multiple log levels, file output,
 and stdout printing. Log messages include file name, line number,
 and timestamp. Convenience macros are provided for common log levels.
 
 @code
 PDSLogger *logger = [PDSLogger sharedLogger];
 logger.logLevel = PDSLogLevelInfo;
 logger.printToStdout = YES;
 
 // Using convenience macros
 PDS_LOG_INFO(@"Server started on port %d", port);
 PDS_LOG_ERROR(@"Failed to start: %@", error);
 
 // Direct method call
 [logger logWithLevel:PDSLogLevelDebug file:__FILE__ line:__LINE__ format:@"Debug info: %@", details];
 @endcode
 */
@interface PDSLogger : NSObject

/*!
 @method sharedLogger
 
 @abstract Returns the shared logger instance.
 
 @return The singleton PDSLogger instance.
 */
+ (instancetype)sharedLogger;

/*! Minimum log level to output. Messages below this level are ignored. */
@property (nonatomic, assign) PDSLogLevel logLevel;

/*! Path to write log file, or nil to disable file logging. */
@property (nonatomic, copy, nullable) NSString *logFilePath;

/*! If YES, also print log messages to stdout. */
@property (nonatomic, assign) BOOL printToStdout;

/*!
 @method logWithLevel:file:line:format:
 
 @abstract Logs a message with format string arguments.
 
 @param level The severity level for this message.
 @param file The source file name (use __FILE__).
 @param line The source line number (use __LINE__).
 @param format The format string for the log message.
 @param ... Variable arguments for the format string.
 */
- (void)logWithLevel:(PDSLogLevel)level
                file:(const char *)file
                line:(NSInteger)line
              format:(NSString *)format, ...;

/*!
 @method logWithLevel:formatted:file:line:
 
 @abstract Logs a pre-formatted message.
 
 @param level The severity level for this message.
 @param formatted The pre-formatted log message.
 @param file The source file name.
 @param line The source line number.
 */
- (void)logWithLevel:(PDSLogLevel)level
            formatted:(NSString *)formatted
                file:(const char *)file
                line:(NSInteger)line;

/*!
 @method levelString:
 
 @abstract Returns the string name of a log level.
 
 @param level The log level.
 @return A string like "DEBUG", "INFO", "WARN", or "ERROR".
 */
- (NSString *)levelString:(PDSLogLevel)level;

/*!
 @method flush
 
 @abstract Flushes any buffered log output to the destination.
 */
- (void)flush;

@end

/*!
 @macro PDS_LOG_DEBUG
 
 @abstract Logs a debug-level message.
 */
#define PDS_LOG_DEBUG(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelDebug file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro PDS_LOG_INFO
 
 @abstract Logs an info-level message.
 */
#define PDS_LOG_INFO(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelInfo file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro PDS_LOG_WARN
 
 @abstract Logs a warning-level message.
 */
#define PDS_LOG_WARN(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelWarn file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro PDS_LOG_ERROR
 
 @abstract Logs an error-level message.
 */
#define PDS_LOG_ERROR(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelError file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

NS_ASSUME_NONNULL_END
