// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @header GZLogger.h
 
 @abstract Structured logging for the PDS.
 
 @discussion This header defines the GZLogger class for structured
 logging with severity levels and file/line information.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

/*!

 @abstract Log severity levels.

 @constant GZLogLevelDebug Debug-level messages (most verbose).
 @constant GZLogLevelInfo Informational messages.
 @constant GZLogLevelWarn Warning messages.
 @constant GZLogLevelError Error messages (least verbose).
 */
typedef NS_ENUM(NSInteger, GZLogLevel) {
    GZLogLevelDebug = 0,
    GZLogLevelInfo,
    GZLogLevelWarn,
    GZLogLevelError
};

/*!

 @abstract Log output format options.

 @constant GZLogFormatText Human-readable text format.
 @constant GZLogFormatJSON Structured JSON format for machine parsing.
 @constant GZLogFormatBoth Output both text and JSON formats.
 */
typedef NS_ENUM(NSInteger, GZLogFormat) {
    GZLogFormatText = 0,
    GZLogFormatJSON,
    GZLogFormatBoth
};

/*! Standard component tags for categorized logging. */
extern NSString * const GZLogComponentDatabase;
extern NSString * const GZLogComponentAuth;
extern NSString * const GZLogComponentHTTP;
extern NSString * const GZLogComponentAdmin;
extern NSString * const GZLogComponentService;
extern NSString * const GZLogComponentCore;
extern NSString * const GZLogComponentBlob;
extern NSString * const GZLogComponentSync;
extern NSString * const GZLogComponentExplore;
extern NSString * const GZLogComponentCLI;

/*!
 @class GZLogger
 
 @abstract Provides structured logging for the PDS.
 
 @discussion GZLogger supports multiple log levels, file output,
 and stdout printing. Log messages include file name, line number,
 and timestamp. Convenience macros are provided for common log levels.
 
 @code
 GZLogger *logger = [GZLogger sharedLogger];
 logger.logLevel = GZLogLevelInfo;
 logger.printToStdout = YES;
 
 // Using convenience macros
 GZ_LOG_INFO(@"Server started on port %d", port);
 GZ_LOG_ERROR(@"Failed to start: %@", error);
 
  // Direct method call
  [logger logWithLevel:GZLogLevelDebug file:__FILE__ line:__LINE__ format:@"Debug info: %@", details];
  @endcode

  @abstract Declares the GZLogger public API.
  */
@interface GZLogger : NSObject

/*!
 @method sharedLogger
 
 @abstract Returns the shared logger instance.
 
 @return The singleton GZLogger instance.
 */
+ (instancetype)sharedLogger;

/*! Minimum log level to output. Messages below this level are ignored. */
@property (nonatomic, assign) GZLogLevel logLevel;

/*! Path to write log file, or nil to disable file logging. */
@property (nonatomic, copy, nullable) NSString *logFilePath;

/*! If YES, also print log messages to stdout. */
@property (nonatomic, assign) BOOL printToStdout;

/*! Log output format (text, JSON, or both). Default: GZLogFormatText. */
@property (nonatomic, assign) GZLogFormat logFormat;

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
- (void)logWithLevel:(GZLogLevel)level
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
- (void)logWithLevel:(GZLogLevel)level
            formatted:(NSString *)formatted
                file:(const char *)file
                line:(NSInteger)line;

/*!
 @method levelString:
 
 @abstract Returns the string name of a log level.
 
 @param level The log level.
 @return A string like "DEBUG", "INFO", "WARN", or "ERROR".
 */
- (NSString *)levelString:(GZLogLevel)level;

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
- (void)logWithLevel:(GZLogLevel)level
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
 @macro GZ_LOG_DEBUG
 
 @abstract Logs a debug-level message.
 */
#define GZ_LOG_DEBUG(FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelDebug file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_INFO
 
 @abstract Logs an info-level message.
 */
#define GZ_LOG_INFO(FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelInfo file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_WARN
 
 @abstract Logs a warning-level message.
 */
#define GZ_LOG_WARN(FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelWarn file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_ERROR

 @abstract Logs an error-level message.
 */
#define GZ_LOG_ERROR(FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelError file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_DEBUG_C

 @abstract Logs a debug-level message with component tag.
 */
#define GZ_LOG_DEBUG_C(COMPONENT, FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelDebug component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_INFO_C

 @abstract Logs an info-level message with component tag.
 */
#define GZ_LOG_INFO_C(COMPONENT, FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelInfo component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_WARN_C

 @abstract Logs a warning-level message with component tag.
 */
#define GZ_LOG_WARN_C(COMPONENT, FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelWarn component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*!
 @macro GZ_LOG_ERROR_C

 @abstract Logs an error-level message with component tag.
 */
#define GZ_LOG_ERROR_C(COMPONENT, FORMAT, ...) \
    [[GZLogger sharedLogger] logWithLevel:GZLogLevelError component:COMPONENT file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/*! Shorthand macro for database error logging. */
#define GZ_LOG_DB_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for database warning logging. */
#define GZ_LOG_DB_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for database info logging. */
#define GZ_LOG_DB_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for database debug logging. */
#define GZ_LOG_DB_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentDatabase, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth error logging. */
#define GZ_LOG_AUTH_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth warning logging. */
#define GZ_LOG_AUTH_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth info logging. */
#define GZ_LOG_AUTH_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for auth debug logging. */
#define GZ_LOG_AUTH_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentAuth, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for HTTP error logging. */
#define GZ_LOG_HTTP_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for HTTP warning logging. */
#define GZ_LOG_HTTP_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/*! Shorthand macro for HTTP info logging. */
#define GZ_LOG_HTTP_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for HTTP debug logging. */
#define GZ_LOG_HTTP_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentHTTP, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin error logging. */
#define GZ_LOG_ADMIN_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin warning logging. */
#define GZ_LOG_ADMIN_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin info logging. */
#define GZ_LOG_ADMIN_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Admin debug logging. */
#define GZ_LOG_ADMIN_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentAdmin, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service error logging. */
#define GZ_LOG_SERVICE_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service warning logging. */
#define GZ_LOG_SERVICE_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service info logging. */
#define GZ_LOG_SERVICE_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Service debug logging. */
#define GZ_LOG_SERVICE_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentService, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync error logging. */
#define GZ_LOG_SYNC_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync warning logging. */
#define GZ_LOG_SYNC_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync info logging. */
#define GZ_LOG_SYNC_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Sync debug logging. */
#define GZ_LOG_SYNC_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentSync, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core error logging. */
#define GZ_LOG_CORE_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core warning logging. */
#define GZ_LOG_CORE_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core info logging. */
#define GZ_LOG_CORE_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Core debug logging. */
#define GZ_LOG_CORE_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentCore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob error logging. */
#define GZ_LOG_BLOB_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob warning logging. */
#define GZ_LOG_BLOB_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob info logging. */
#define GZ_LOG_BLOB_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Blob debug logging. */
#define GZ_LOG_BLOB_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentBlob, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore error logging. */
#define GZ_LOG_EXPLORE_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore warning logging. */
#define GZ_LOG_EXPLORE_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore info logging. */
#define GZ_LOG_EXPLORE_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for Explore debug logging. */
#define GZ_LOG_EXPLORE_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentExplore, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI error logging. */
#define GZ_LOG_CLI_ERROR(FORMAT, ...) \
    GZ_LOG_ERROR_C(GZLogComponentCLI, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI warning logging. */
#define GZ_LOG_CLI_WARN(FORMAT, ...) \
    GZ_LOG_WARN_C(GZLogComponentCLI, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI info logging. */
#define GZ_LOG_CLI_INFO(FORMAT, ...) \
    GZ_LOG_INFO_C(GZLogComponentCLI, FORMAT, ##__VA_ARGS__)

/* Shorthand macro for CLI debug logging. */
#define GZ_LOG_CLI_DEBUG(FORMAT, ...) \
    GZ_LOG_DEBUG_C(GZLogComponentCLI, FORMAT, ##__VA_ARGS__)

NS_ASSUME_NONNULL_END
