/*!
 @file NSDateFormatter+ATProto.h
 
 @abstract NSDateFormatter category for ATProto date formatting.
 
 @discussion Provides a shared ISO 8601 date formatter configured for
 ATProto timestamp formatting. This consolidates date formatting logic
 previously duplicated across PDSController and PDSAdminController.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @category NSDateFormatter (ATProto)
 
 @abstract ATProto-specific date formatting utilities.
 
 @discussion Provides thread-safe access to a shared ISO 8601 date formatter
 configured for ATProto's timestamp format (yyyy-MM-dd'T'HH:mm:ss.SSSZ).
 */
@interface NSDateFormatter (ATProto)

/*!
 @method atproto_iso8601Formatter
 
 @abstract Returns a shared ISO 8601 date formatter.
 
 @discussion Returns a thread-safe, lazily-initialized formatter configured
 for ATProto's timestamp format. On systems where NSISO8601DateFormatter
 is unavailable, returns a standard NSDateFormatter configured with
 the same format.
 
 @return A shared date formatter instance.
 */
+ (id)atproto_iso8601Formatter;

/*!
 @method isNSISO8601DateFormatterAvailable
 
 @abstract Returns YES if the current platform supports NSISO8601DateFormatter.
 */
+ (BOOL)isNSISO8601DateFormatterAvailable;

/*!
 @method atproto_stringFromDate:
 
 @abstract Formats a date using ISO 8601 format (yyyy-MM-dd'T'HH:mm:ss.SSSZ).
 
 @param date The date to format.
 @return An ISO 8601 formatted string.
 */
+ (NSString *)atproto_stringFromDate:(NSDate *)date;

/*!
 @method atproto_dateFromString:
 
 @abstract Parses an ISO 8601 datetime string.
 
 @discussion Robustly handles various ISO 8601 formats allowed by ATProto:
 - YYYY-MM-DDTHH:mm:ssZ
 - YYYY-MM-DDTHH:mm:ss.SSSZ
 - YYYY-MM-DDTHH:mm:ss+HH:MM
 
 @param string The string to parse.
 @return A date object, or nil if parsing failed.
 */
+ (nullable NSDate *)atproto_dateFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
