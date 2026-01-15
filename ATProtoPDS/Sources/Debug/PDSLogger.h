#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @file PDSLogger.h
 * @brief Logging infrastructure for the ATProto PDS server.
 *
 * This file provides a centralized logging system with configurable log levels,
 * file output, and stdout printing capabilities. The PDSLogger class follows
 * the singleton pattern to ensure consistent logging throughout the application.
 */

typedef NS_ENUM(NSInteger, PDSLogLevel) {
    PDSLogLevelDebug = 0,
    PDSLogLevelInfo,
    PDSLogLevelWarn,
    PDSLogLevelError
};

/**
 * @class PDSLogger
 * @brief A singleton logger class that provides structured logging capabilities
 *        for the ATProto PDS server.
 *
 * PDSLogger manages log messages with different severity levels and supports
 * output to both stdout and a log file. The logger captures source location
 * information (file and line number) for each log message.
 *
 * @note Use the provided macros (PDS_LOG_DEBUG, PDS_LOG_INFO, etc.) for
 *       convenient logging with automatic source location capture.
 *
 * @invariant The shared logger instance is guaranteed to exist once accessed.
 */
@interface PDSLogger : NSObject

/**
 * @brief Returns the shared singleton logger instance.
 *
 * @return The shared PDSLogger instance.
 */
+ (instancetype)sharedLogger;

/**
 * @brief The minimum log level to record.
 *
 * Messages with a level below this threshold will be filtered out.
 * Default is PDSLogLevelInfo.
 */
@property (nonatomic, assign) PDSLogLevel logLevel;

/**
 * @brief Optional path to a log file for persistent logging.
 *
 * If nil, logs are not written to a file. Setting this property enables
 * file-based logging at the specified path.
 */
@property (nonatomic, copy, nullable) NSString *logFilePath;

/**
 * @brief Whether to print log messages to stdout.
 *
 * When YES, all accepted log messages are printed to standard output.
 * Default is YES.
 */
@property (nonatomic, assign) BOOL printToStdout;

/**
 * @brief Logs a message with the specified level and source location.
 *
 * @param level   The severity level of the log message.
 * @param file    The source file name (typically __FILE__).
 * @param line    The source line number (typically __LINE__).
 * @param format  The format string for the log message.
 * @param ...     Variable arguments for the format string.
 */
- (void)logWithLevel:(PDSLogLevel)level
                file:(const char *)file
                line:(NSInteger)line
              format:(NSString *)format, ...;

/**
 * @brief Logs a pre-formatted message with the specified level and source location.
 *
 * @param level      The severity level of the log message.
 * @param formatted  The pre-formatted log message string.
 * @param file       The source file name.
 * @param line       The source line number.
 */
- (void)logWithLevel:(PDSLogLevel)level
            formatted:(NSString *)formatted
                file:(const char *)file
                line:(NSInteger)line;

/**
 * @brief Converts a log level to its human-readable string representation.
 *
 * @param level The log level to convert.
 * @return A string representation of the log level (e.g., "DEBUG", "INFO").
 */
- (NSString *)levelString:(PDSLogLevel)level;

/**
 * @brief Flushes any buffered log output.
 *
 * Ensures all pending log messages are written to their destinations.
 */
- (void)flush;

@end

/**
 * @def PDS_LOG_DEBUG(FORMAT, ...)
 * @brief Logs a debug-level message with automatic source location.
 *
 * @param FORMAT The format string for the log message.
 * @param ...    Variable arguments for the format string.
 *
 * @note Debug messages are filtered out when logLevel is greater than PDSLogLevelDebug.
 */
#define PDS_LOG_DEBUG(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelDebug file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/**
 * @def PDS_LOG_INFO(FORMAT, ...)
 * @brief Logs an info-level message with automatic source location.
 *
 * @param FORMAT The format string for the log message.
 * @param ...    Variable arguments for the format string.
 *
 * @note Info messages are filtered out when logLevel is greater than PDSLogLevelInfo.
 */
#define PDS_LOG_INFO(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelInfo file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/**
 * @def PDS_LOG_WARN(FORMAT, ...)
 * @brief Logs a warning-level message with automatic source location.
 *
 * @param FORMAT The format string for the log message.
 * @param ...    Variable arguments for the format string.
 *
 * @note Warning messages are filtered out when logLevel is greater than PDSLogLevelWarn.
 */
#define PDS_LOG_WARN(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelWarn file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

/**
 * @def PDS_LOG_ERROR(FORMAT, ...)
 * @brief Logs an error-level message with automatic source location.
 *
 * @param FORMAT The format string for the log message.
 * @param ...    Variable arguments for the format string.
 *
 * @note Error messages are filtered out when logLevel is greater than PDSLogLevelError.
 */
#define PDS_LOG_ERROR(FORMAT, ...) \
    [[PDSLogger sharedLogger] logWithLevel:PDSLogLevelError file:__FILE__ line:__LINE__ format:FORMAT, ##__VA_ARGS__]

NS_ASSUME_NONNULL_END
