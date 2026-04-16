/*!
 @file NSDateFormatter+ATProto.m
 
 @abstract Implementation of NSDateFormatter category for ATProto date formatting.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "NSDateFormatter+ATProto.h"

// Force static linkers to retain this category object file in Linux builds.
void NSDateFormatterLinkATProtoCategory(void) {
    static int linked = 0;
    if (linked) return;
    linked = 1;
}

// Values for NSISO8601DateFormatOptions from Foundation headers
// InternetDateTime = Year | Month | Day | Time | DashSeparatorInDate | ColonSeparatorInTime | ColonSeparatorInTimeZone
// On macOS 14: 1907
// FractionalSeconds: 2048
#define AT_NSISO8601DateFormatWithInternetDateTime 1907
#define AT_NSISO8601DateFormatWithFractionalSeconds 2048

@implementation NSDateFormatter (ATProto)

+ (BOOL)isNSISO8601DateFormatterAvailable {
    return NSClassFromString(@"NSISO8601DateFormatter") != nil;
}

+ (id)atproto_iso8601FormatterInternal {
    Class isoClass = NSClassFromString(@"NSISO8601DateFormatter");
    if (isoClass) {
        static id formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[isoClass alloc] init];
            SEL setFormatOptionsSEL = NSSelectorFromString(@"setFormatOptions:");
            if ([formatter respondsToSelector:setFormatOptionsSEL]) {
                NSUInteger options = AT_NSISO8601DateFormatWithInternetDateTime | AT_NSISO8601DateFormatWithFractionalSeconds;
                NSMethodSignature *sig = [formatter methodSignatureForSelector:setFormatOptionsSEL];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:formatter];
                [inv setSelector:setFormatOptionsSEL];
                [inv setArgument:&options atIndex:2];
                [inv invoke];
            }
        });
        return formatter;
    }
    return nil;
}

+ (id)atproto_iso8601FormatterInternalNoFractionalSeconds {
    Class isoClass = NSClassFromString(@"NSISO8601DateFormatter");
    if (isoClass) {
        static id formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[isoClass alloc] init];
            SEL setFormatOptionsSEL = NSSelectorFromString(@"setFormatOptions:");
            if ([formatter respondsToSelector:setFormatOptionsSEL]) {
                NSUInteger options = AT_NSISO8601DateFormatWithInternetDateTime;
                NSMethodSignature *sig = [formatter methodSignatureForSelector:setFormatOptionsSEL];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:formatter];
                [inv setSelector:setFormatOptionsSEL];
                [inv setArgument:&options atIndex:2];
                [inv invoke];
            }
        });
        return formatter;
    }
    return nil;
}

+ (NSDateFormatter *)atproto_iso8601Formatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return formatter;
}

+ (NSString *)atproto_stringFromDate:(NSDate *)date {
    if (!date) return nil;
    
    id isoFormatter = [self atproto_iso8601FormatterInternal];
    if (isoFormatter) {
        SEL stringFromDateSEL = NSSelectorFromString(@"stringFromDate:");
        if ([isoFormatter respondsToSelector:stringFromDateSEL]) {
            // Using performSelector: withObject: is safe for return type id
            return [isoFormatter performSelector:stringFromDateSEL withObject:date];
        }
    }
    
    return [[self atproto_iso8601Formatter] stringFromDate:date];
}

+ (nullable NSDate *)atproto_dateFromStringManual:(NSString *)string {
    if (!string || string.length == 0) return nil;

    const char *str = [string UTF8String];
    int y, m, d, hr, min, sec;
    double fsec = 0;
    char tz[64];
    int offset_hr = 0, offset_min = 0;
    char tz_sign = 'Z';

    // Try with fractional seconds (using double for precision)
    int count = sscanf(str, "%d-%d-%dT%d:%d:%lf%63s", &y, &m, &d, &hr, &min, &fsec, tz);
    if (count < 6) {
        // Try without fractional seconds
        count = sscanf(str, "%d-%d-%dT%d:%d:%d%63s", &y, &m, &d, &hr, &min, &sec, tz);
        if (count < 6) return nil;
        fsec = (double)sec;
    }

    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDateComponents *comps = [[NSDateComponents alloc] init];
    [comps setYear:y];
    [comps setMonth:m];
    [comps setDay:d];
    [comps setHour:hr];
    [comps setMinute:min];
    [comps setSecond:(int)fsec];
    [comps setNanosecond:(int)((fsec - (int)fsec) * 1000000000.0)];

    NSDate *date = [calendar dateFromComponents:comps];

    // Handle Timezone
    if (count == 7) {
        if (tz[0] == 'Z') {
            // UTC, already handled
        } else if (sscanf(tz, "%c%d:%d", &tz_sign, &offset_hr, &offset_min) == 3) {
            int offset = (offset_hr * 3600) + (offset_min * 60);
            if (tz_sign == '-') offset = -offset;
            date = [date dateByAddingTimeInterval:-offset];
        }
    }

    return date;
}

+ (nullable NSDate *)atproto_dateFromString:(NSString *)string {
    if (!string || string.length == 0) return nil;

    if ([self isNSISO8601DateFormatterAvailable]) {
        id isoFormatter = [self atproto_iso8601FormatterInternal];
        SEL dateFromStringSEL = NSSelectorFromString(@"dateFromString:");
        if ([isoFormatter respondsToSelector:dateFromStringSEL]) {
            NSDate *date = [isoFormatter performSelector:dateFromStringSEL withObject:string];
            if (date) return date;

            id isoFormatterNoFrac = [self atproto_iso8601FormatterInternalNoFractionalSeconds];
            date = [isoFormatterNoFrac performSelector:dateFromStringSEL withObject:string];
            if (date) return date;
        }
    }

    // Fallback for GNUstep or older macOS
    NSDate *date = [[self atproto_iso8601Formatter] dateFromString:string];
    if (date) return date;

    // Manual fallback for extreme robustness
    return [self atproto_dateFromStringManual:string];
}

@end
