#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header PDSLogger.h
 
 @abstract Structured logging for the PDS.
 
 @discussion This header defines the PDSLogger class for structured
 logging with severity levels and file/line information.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
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
 @enum PDSLogFormat

 @abstract Log output format options.

 @constant PDSLogFormatText Human-readable text format.
 @constant PDSLogFormatJSON Structured JSON format for machine parsing.
 @constant PDSLogFormatBoth Output both text and JSON formats.
 */
typedef NS_ENUM(NSInteger, PDSLogFormat) {
    PDSLogFormatText = 0,
    PDSLogFormatJSON,
    PDSLogFormatBoth
};

/*! Standard component tags for categorized logging. */
extern NSString * const PDSLogComponentDatabase;
extern NSString * const PDSLogComponentAuth;
extern NSString * const PDSLogComponentHTTP;
extern NSString * const PDSLogComponentAdmin;
extern NSString * const PDSLogComponentService;
extern NSString * const PDSLogComponentCore;
extern NSString * const PDSLogComponentBlob;
extern NSString * const PDSLogComponentSync;
extern NSString * const PDSLogComponentExplore;
extern NSString * const PDSLogComponentCLI;

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

/*! Log output format (text, JSON, or both). Default: PDSLogFormatText. */
@property (nonatomic, assign) PDSLogFormat logFormat;

/*! Maximum log file size in bytes before rotation. Default: 10MB. */
@property (nonatomic, assign) NSUInteger maxLogFileSize;

/*! Maximum number of rotated log files to keep. Default: 5. */
@property (nonatomic, assign) NSUInteger maxLogFiles;

/*! If YES, use async logging with background queue. Default: YES. */
@property (nonatomic, assign) BOOL asyncLogging;

/*! Set of enabled component tags. If nil, all components are enabled. */
@property (nonatomic, copy, nullable) NSSet<NSString *> *enabledComponents;

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

/*!
 @method logWithLevel:component:file:line:format:

 @abstract Logs a message with component tag and format string arguments.

 @param level The severity level for this message.
 @param component The component tag (e.g., "Database", "Auth").
 @param file The source file name (use __FILE__).
 @param line The source line number (use __LINE__).
 @param format The format string for the log message.
 @param ... Variable arguments for the format string.
 */
- (void)logWithLevel:(PDSLogLevel)level
           component:(NSString *)component
                file:(const char *)file
                line:(NSInteger)line
              format:(NSString *)format, ... NS_FORMAT_FUNCTION(5,6);

/*!
 @method setCorrelationID:

 @abstract Sets a correlation ID for tracking related log messages.

 @param correlationID The correlation ID (e.g., request ID).
 */
- (void)setCorrelationID:(NSString *)correlationID;

/*!
 @method clearCorrelationID

 @abstract Clears the current correlation ID.
 */
- (void)clearCorrelationID;

/*!
 @method correlationID

 @abstract Returns the current correlation ID, if any.

 @return The correlation ID, or nil if none is set.
 */
- (nullable NSString *)correlationID;

/*!
 @method rotateLogIfNeeded

 @abstract Checks log file size and rotates if it exceeds maxLogFileSize.
 */
- (void)rotateLogIfNeeded;

/*!
 @method forceRotate

 @abstract Forces an immediate log rotation.
 */
- (void)forceRotate;

/*!
 @method closeLogFile

 @abstract Closes the current log file handle.
 */
- (void)closeLogFile;

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

/*!
 @macro PDS_LOG_DEBUG_C

 @abstract Logs a debug-level message with component tag.
 */
#define PDS_LOG_DEBUG_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelDebug component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro PDS_LOG_INFO_C

 @abstract Logs an info-level message with component tag.
 */
#define PDS_LOG_INFO_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelInfo component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro PDS_LOG_WARN_C

 @abstract Logs a warning-level message with component tag.
 */
#define PDS_LOG_WARN_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelWarn component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro PDS_LOG_ERROR_C

 @abstract Logs an error-level message with component tag.
 */
#define PDS_LOG_ERROR_C(COMPONENT, FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelError component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*! Shorthand macro for database error logging. */
#define PDS_LOG_DB_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for database warning logging. */
#define PDS_LOG_DB_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for database info logging. */
#define PDS_LOG_DB_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for database debug logging. */
#define PDS_LOG_DB_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth error logging. */
#define PDS_LOG_AUTH_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth warning logging. */
#define PDS_LOG_AUTH_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth info logging. */
#define PDS_LOG_AUTH_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth debug logging. */
#define PDS_LOG_AUTH_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for HTTP error logging. */
#define PDS_LOG_HTTP_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for HTTP warning logging. */
#define PDS_LOG_HTTP_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for HTTP info logging. */
#define PDS_LOG_HTTP_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for HTTP debug logging. */
#define PDS_LOG_HTTP_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin error logging. */
#define PDS_LOG_ADMIN_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin warning logging. */
#define PDS_LOG_ADMIN_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin info logging. */
#define PDS_LOG_ADMIN_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin debug logging. */
#define PDS_LOG_ADMIN_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service error logging. */
#define PDS_LOG_SERVICE_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service warning logging. */
#define PDS_LOG_SERVICE_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service info logging. */
#define PDS_LOG_SERVICE_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service debug logging. */
#define PDS_LOG_SERVICE_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync error logging. */
#define PDS_LOG_SYNC_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync warning logging. */
#define PDS_LOG_SYNC_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync info logging. */
#define PDS_LOG_SYNC_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync debug logging. */
#define PDS_LOG_SYNC_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core error logging. */
#define PDS_LOG_CORE_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core warning logging. */
#define PDS_LOG_CORE_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core info logging. */
#define PDS_LOG_CORE_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core debug logging. */
#define PDS_LOG_CORE_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob error logging. */
#define PDS_LOG_BLOB_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob warning logging. */
#define PDS_LOG_BLOB_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob info logging. */
#define PDS_LOG_BLOB_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob debug logging. */
#define PDS_LOG_BLOB_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore error logging. */
#define PDS_LOG_EXPLORE_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore warning logging. */
#define PDS_LOG_EXPLORE_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore info logging. */
#define PDS_LOG_EXPLORE_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore debug logging. */
#define PDS_LOG_EXPLORE_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI error logging. */
#define PDS_LOG_CLI_ERROR(FORMAT, ...) \
    PDS_LOG_ERROR_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI warning logging. */
#define PDS_LOG_CLI_WARN(FORMAT, ...) \
    PDS_LOG_WARN_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI info logging. */
#define PDS_LOG_CLI_INFO(FORMAT, ...) \
    PDS_LOG_INFO_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI debug logging. */
#define PDS_LOG_CLI_DEBUG(FORMAT, ...) \
    PDS_LOG_DEBUG_C(PDSLogComponentCLI, FORMAT, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
