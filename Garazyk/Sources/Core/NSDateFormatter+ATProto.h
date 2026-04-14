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
 for ATProto's timestamp format. The formatter uses:
 - Format: yyyy-MM-dd'T'HH:mm:ss.SSSZ
 - Locale: en_US_POSIX
 - Timezone: UTC

 @return A shared NSDateFormatter instance.

 @code
 NSDateFormatter *formatter = [NSDateFormatter atproto_iso8601Formatter];
 NSString *timestamp = [formatter stringFromDate:[NSDate date]];
 @endcode
 */
+ (NSDateFormatter *)atproto_iso8601Formatter;

/*!
 @method atproto_stringFromDate:

 @abstract Formats a date using ISO 8601 format.

 @param date The date to format.
 @return An ISO 8601 formatted string.
 */
+ (NSString *)atproto_stringFromDate:(NSDate *)date;

/*!
 @method atproto_dateFromString:

 @abstract Parses an ISO 8601 date string.

 @param string The ISO 8601 string to parse.
 @return The parsed date, or nil if parsing fails.
 */
+ (nullable NSDate *)atproto_dateFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END