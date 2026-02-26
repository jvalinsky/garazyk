/*!
 @file NSDateFormatter+ATProto.m

 @abstract Implementation of NSDateFormatter category for ATProto date formatting.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "NSDateFormatter+ATProto.h"

static NSString *_Nullable normalizeRFC3339ForNSDateFormatter(NSString *_Nullable input) {
    if (![input isKindOfClass:[NSString class]]) {
        return nil;
    }

    NSString *string = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (string.length == 0) {
        return nil;
    }

    NSRange tRange = [string rangeOfString:@"T"];
    if (tRange.location == NSNotFound) {
        return nil;
    }
    NSUInteger tIndex = tRange.location;

    NSString *main = string;
    NSString *tz = nil;

    if ([string hasSuffix:@"Z"]) {
        if (string.length < 2) {
            return nil;
        }
        main = [string substringToIndex:string.length - 1];
        tz = @"+0000";
    } else {
        NSRange plusRange = [string rangeOfString:@"+" options:NSBackwardsSearch];
        NSRange minusRange = [string rangeOfString:@"-" options:NSBackwardsSearch];

        NSUInteger tzIndex = NSNotFound;
        if (plusRange.location != NSNotFound && plusRange.location > tIndex) {
            tzIndex = plusRange.location;
        }
        if (minusRange.location != NSNotFound && minusRange.location > tIndex &&
            (tzIndex == NSNotFound || minusRange.location > tzIndex)) {
            tzIndex = minusRange.location;
        }

        if (tzIndex != NSNotFound) {
            main = [string substringToIndex:tzIndex];
            tz = [string substringFromIndex:tzIndex];
        } else {
            tz = @"+0000";
        }
    }

    if (tz.length < 1) {
        return nil;
    }
    unichar signChar = [tz characterAtIndex:0];
    if (signChar != '+' && signChar != '-') {
        return nil;
    }

    NSString *tzRest = tz.length > 1 ? [tz substringFromIndex:1] : @"";
    tzRest = [tzRest stringByReplacingOccurrencesOfString:@":" withString:@""];

    NSMutableString *tzDigits = [NSMutableString stringWithCapacity:4];
    for (NSUInteger i = 0; i < tzRest.length; i++) {
        unichar ch = [tzRest characterAtIndex:i];
        if (ch < '0' || ch > '9') {
            break;
        }
        [tzDigits appendFormat:@"%C", ch];
        if (tzDigits.length >= 4) {
            break;
        }
    }

    if (tzDigits.length == 2) {
        [tzDigits appendString:@"00"];
    }
    if (tzDigits.length != 4) {
        return nil;
    }

    NSString *normalizedTZ = [NSString stringWithFormat:@"%C%@", signChar, tzDigits];

    NSString *base = main;
    NSString *fractionDigits = nil;
    NSRange dotRange = [main rangeOfString:@"." options:NSBackwardsSearch];
    if (dotRange.location != NSNotFound && dotRange.location > tIndex) {
        base = [main substringToIndex:dotRange.location];
        NSString *fraction = (dotRange.location + 1 < main.length) ? [main substringFromIndex:dotRange.location + 1] : @"";

        NSMutableString *digits = [NSMutableString stringWithCapacity:3];
        for (NSUInteger i = 0; i < fraction.length; i++) {
            unichar ch = [fraction characterAtIndex:i];
            if (ch < '0' || ch > '9') {
                break;
            }
            [digits appendFormat:@"%C", ch];
            if (digits.length >= 9) {
                break;
            }
        }
        fractionDigits = digits;
    }

    NSString *ms = @"000";
    if ([fractionDigits isKindOfClass:[NSString class]] && fractionDigits.length > 0) {
        if (fractionDigits.length >= 3) {
            ms = [fractionDigits substringToIndex:3];
        } else if (fractionDigits.length == 2) {
            ms = [fractionDigits stringByAppendingString:@"0"];
        } else {
            ms = [fractionDigits stringByAppendingString:@"00"];
        }
    }

    NSString *normalizedMain = [NSString stringWithFormat:@"%@.%@", base, ms];
    return [normalizedMain stringByAppendingString:normalizedTZ];
}

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

    NSDate *date = nil;
    @try {
        date = [[self atproto_iso8601FormatterInternal] dateFromString:string];
    } @catch (NSException *exception) {
        (void)exception;
        date = nil;
    }
    if (date) return date;

    @try {
        date = [[self atproto_iso8601FormatterInternalNoFractionalSeconds] dateFromString:string];
    } @catch (NSException *exception) {
        (void)exception;
        date = nil;
    }
    if (date) return date;

    NSString *normalized = normalizeRFC3339ForNSDateFormatter(string);
    if (normalized.length == 0) {
        // Fall back to the legacy formatter for non-RFC3339 strings
        @try {
            return [[self atproto_iso8601Formatter] dateFromString:string];
        } @catch (NSException *exception) {
            (void)exception;
            return nil;
        }
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
    [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];

    @try {
        return [formatter dateFromString:normalized];
    } @catch (NSException *exception) {
        (void)exception;
        return nil;
    }
}

@end
