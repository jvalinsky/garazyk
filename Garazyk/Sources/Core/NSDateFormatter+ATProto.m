// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file NSDateFormatter+ATProto.m
 
 @abstract Implementation of NSDateFormatter category for ATProto date formatting.
 
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "NSDateFormatter+ATProto.h"
#import <pthread.h>

// Suppress -Warc-performSelector-leaks: the dynamic selectors used here
// (stringFromDate: and dateFromString:) are known to return autoreleased
// objects, so there is no leak risk.
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

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

#pragma mark - Thread-Local Formatter Storage

/// NSDateFormatter is NOT thread-safe on GNUstep (backed by ICU SimpleDateFormat).
/// A shared singleton causes SIGSEGV in __dynamic_cast when multiple threads
/// parse dates concurrently. We use pthread_key_t for thread-local storage
/// of per-thread formatters, which works with ARC-managed ObjC objects.

/// Destructor for pthread_key_t: releases the ObjC object when the thread exits.
static void atproto_formatter_destructor(void *ptr) {
    if (ptr) {
        id obj = (__bridge_transfer id)ptr;
        // ARC releases the object when it goes out of scope
        (void)obj;
    }
}

/// pthread_once init routine for the NSDateFormatter key.
static void atproto_init_iso8601_formatter_key(void) {
    static pthread_key_t key;
    pthread_key_create(&key, atproto_formatter_destructor);
    // Store in a global so we can retrieve it
    // (We use a different approach below instead)
}

// Use dispatch_once for key initialization (portable across macOS and GNUstep)
// and pthread_key_t for thread-local storage.

static pthread_key_t _atproto_iso8601_formatter_key;
static dispatch_once_t _atproto_iso8601_formatter_key_once;
static void atproto_init_iso8601_formatter_key_dispatch(void *ctx) {
    pthread_key_create((pthread_key_t *)ctx, atproto_formatter_destructor);
}
static pthread_key_t atproto_iso8601_formatter_key(void) {
    dispatch_once_f(&_atproto_iso8601_formatter_key_once,
                    &_atproto_iso8601_formatter_key,
                    atproto_init_iso8601_formatter_key_dispatch);
    return _atproto_iso8601_formatter_key;
}

static pthread_key_t _atproto_iso8601_internal_key;
static dispatch_once_t _atproto_iso8601_internal_key_once;
static void atproto_init_iso8601_internal_key_dispatch(void *ctx) {
    pthread_key_create((pthread_key_t *)ctx, atproto_formatter_destructor);
}
static pthread_key_t atproto_iso8601_internal_key(void) {
    dispatch_once_f(&_atproto_iso8601_internal_key_once,
                    &_atproto_iso8601_internal_key,
                    atproto_init_iso8601_internal_key_dispatch);
    return _atproto_iso8601_internal_key;
}

static pthread_key_t _atproto_iso8601_internal_nofrac_key;
static dispatch_once_t _atproto_iso8601_internal_nofrac_key_once;
static void atproto_init_iso8601_internal_nofrac_key_dispatch(void *ctx) {
    pthread_key_create((pthread_key_t *)ctx, atproto_formatter_destructor);
}
static pthread_key_t atproto_iso8601_internal_nofrac_key(void) {
    dispatch_once_f(&_atproto_iso8601_internal_nofrac_key_once,
                    &_atproto_iso8601_internal_nofrac_key,
                    atproto_init_iso8601_internal_nofrac_key_dispatch);
    return _atproto_iso8601_internal_nofrac_key;
}

@implementation NSDateFormatter (ATProto)

+ (BOOL)isNSISO8601DateFormatterAvailable {
    return NSClassFromString(@"NSISO8601DateFormatter") != nil;
}

+ (id)atproto_iso8601FormatterInternal {
    Class isoClass = NSClassFromString(@"NSISO8601DateFormatter");
    if (!isoClass) return nil;

    pthread_key_t key = atproto_iso8601_internal_key();
    id formatter = (__bridge id)pthread_getspecific(key);
    if (formatter) return formatter;

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
    pthread_setspecific(key, (__bridge_retained void *)formatter);
    return formatter;
}

+ (id)atproto_iso8601FormatterInternalNoFractionalSeconds {
    Class isoClass = NSClassFromString(@"NSISO8601DateFormatter");
    if (!isoClass) return nil;

    pthread_key_t key = atproto_iso8601_internal_nofrac_key();
    id formatter = (__bridge id)pthread_getspecific(key);
    if (formatter) return formatter;

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
    pthread_setspecific(key, (__bridge_retained void *)formatter);
    return formatter;
}

+ (NSDateFormatter *)atproto_iso8601Formatter {
    pthread_key_t key = atproto_iso8601_formatter_key();
    NSDateFormatter *formatter = (__bridge id)pthread_getspecific(key);
    if (formatter) return formatter;

    formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    pthread_setspecific(key, (__bridge_retained void *)formatter);
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
    return [[self atproto_iso8601Formatter] dateFromString:string];
}

@end
