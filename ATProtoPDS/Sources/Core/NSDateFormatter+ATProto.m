/*!
 @file NSDateFormatter+ATProto.m

 @abstract Implementation of NSDateFormatter category for ATProto date formatting.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "NSDateFormatter+ATProto.h"

@implementation NSDateFormatter (ATProto)

+ (NSDateFormatter *)atproto_iso8601Formatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return formatter;
}

+ (NSISO8601DateFormatter *)atproto_iso8601FormatterInternal {
    static NSISO8601DateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return formatter;
}

+ (NSISO8601DateFormatter *)atproto_iso8601FormatterInternalNoFractionalSeconds {
    static NSISO8601DateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    });
    return formatter;
}

+ (NSString *)atproto_stringFromDate:(NSDate *)date {
    if (!date) {
        return nil;
    }
    return [[self atproto_iso8601FormatterInternal] stringFromDate:date];
}

+ (nullable NSDate *)atproto_dateFromString:(NSString *)string {
    if (!string || string.length == 0) {
        return nil;
    }
    // Try the precise NSISO8601DateFormatter first
    NSDate *date = [[self atproto_iso8601FormatterInternal] dateFromString:string];
    if (date) return date;
    // Fallback for timestamps without fractional seconds
    date = [[self atproto_iso8601FormatterInternalNoFractionalSeconds] dateFromString:string];
    if (date) return date;
    // Fall back to the legacy formatter for non-Z suffixed strings
    return [[self atproto_iso8601Formatter] dateFromString:string];
}

@end
