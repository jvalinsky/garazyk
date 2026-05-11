// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ATProtoValidator.h"

@implementation ATProtoValidator

+ (BOOL)validateDID:(NSString *)did error:(NSError **)error {
    if (!did) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"DID cannot be nil"}];
        return NO;
    }

    // ATProto DID regex (official from spec): ^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$
    NSString *pattern = @"^did:[a-z]+:[a-zA-Z0-9._:%-]*[a-zA-Z0-9._-]$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if ([regex numberOfMatchesInString:did options:0 range:NSMakeRange(0, did.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID format"}];
        return NO;
    }

    // Check length (max 2048 per DID spec)
    if (did.length > 2048) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"DID too long"}];
        return NO;
    }

    // did:plc identifier must be 24 lowercase base32 chars (no uppercase, no 0189)
    if ([did hasPrefix:@"did:plc:"]) {
        NSString *identifier = [did substringFromIndex:8]; // skip "did:plc:"
        if (identifier.length != 24) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:5 userInfo:@{NSLocalizedDescriptionKey: @"did:plc identifier must be exactly 24 characters"}];
            return NO;
        }
        static NSString * const plcAlphabet = @"234567abcdefghijklmnopqrstuvwxyz";
        for (NSUInteger i = 0; i < identifier.length; i++) {
            unichar c = [identifier characterAtIndex:i];
            if ([plcAlphabet rangeOfString:[NSString stringWithCharacters:&c length:1]].location == NSNotFound) {
                if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:6 userInfo:@{NSLocalizedDescriptionKey: @"did:plc identifier must be lowercase base32 (no uppercase, no 0, 1, 8, 9)"}];
                return NO;
            }
        }
    }

    return YES;
}

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error {
    if (!handle) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Handle cannot be nil"}];
        return NO;
    }

    if (handle.length > 253) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Handle too long"}];
        return NO;
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$" options:0 error:nil];

    if ([regex numberOfMatchesInString:handle options:0 range:NSMakeRange(0, handle.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Invalid handle syntax"}];
        return NO;
    }

    return YES;
}

+ (BOOL)validateCID:(NSString *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"CID cannot be nil"}];
        return NO;
    }

    if (cid.length < 8) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:14 userInfo:@{NSLocalizedDescriptionKey: @"CID too short"}];
        return NO;
    }

    // CIDv0 (Qm...) not supported in AT Protocol
    if ([cid hasPrefix:@"Qm"]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:10 userInfo:@{NSLocalizedDescriptionKey: @"CIDv0 not supported"}];
        return NO;
    }

    // CIDv1 must start with 'b' (lowercase) and use base32 lowercase only
    // Valid base32 chars: 234567abcdefghijklmnopqrstuvwxyz (no 0, 1, 8, 9, no uppercase)
    if (![cid hasPrefix:@"b"]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:10 userInfo:@{NSLocalizedDescriptionKey: @"CIDv1 must start with 'b'"}];
        return NO;
    }

    static NSString * const base32Alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
    for (NSUInteger i = 1; i < cid.length; i++) {
        unichar c = [cid characterAtIndex:i];
        if ([base32Alphabet rangeOfString:[NSString stringWithCharacters:&c length:1]].location == NSNotFound) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:10 userInfo:@{NSLocalizedDescriptionKey: @"CID contains invalid base32 characters (must be lowercase, no 0, 1, 8, 9)"}];
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateTID:(NSString *)tid error:(NSError **)error {
    if (!tid) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"TID cannot be nil"}];
        return NO;
    }

    if (tid.length != 13) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:11 userInfo:@{NSLocalizedDescriptionKey: @"TID must be 13 characters"}];
        return NO;
    }

    static NSString * const alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
    static NSString * const allowedFirstChars = @"234567ab";
    unichar first = [tid characterAtIndex:0];
    if ([allowedFirstChars rangeOfString:[NSString stringWithCharacters:&first length:1]].location == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Invalid TID format (high bit cannot be set)"}];
        return NO;
    }
    for (NSUInteger i = 0; i < tid.length; i++) {
        unichar c = [tid characterAtIndex:i];
        if ([alphabet rangeOfString:[NSString stringWithCharacters:&c length:1]].location == NSNotFound) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Invalid TID format (must be base32-sortable)"}];
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateNSID:(NSString *)nsid error:(NSError **)error {
    if (!nsid) return NO;

    if (nsid.length > 317) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:15 userInfo:@{NSLocalizedDescriptionKey: @"NSID too long"}];
        return NO;
    }

    NSArray *components = [nsid componentsSeparatedByString:@"."];
    if (components.count < 3) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:13 userInfo:@{NSLocalizedDescriptionKey: @"NSID must have at least three segments"}];
        return NO;
    }

    for (NSUInteger i = 0; i < components.count; i++) {
        NSString *comp = components[i];
        if (comp.length == 0) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:17 userInfo:@{NSLocalizedDescriptionKey: @"NSID cannot have empty segments"}];
            return NO;
        }
        if (comp.length > 63) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:18 userInfo:@{NSLocalizedDescriptionKey: @"NSID segment too long"}];
            return NO;
        }

        unichar firstChar = [comp characterAtIndex:0];
        BOOL isLetter = (firstChar >= 'a' && firstChar <= 'z') || (firstChar >= 'A' && firstChar <= 'Z');
        BOOL isDigit = (firstChar >= '0' && firstChar <= '9');
        BOOL isFirst = (i == 0);
        BOOL isLast = (i == components.count - 1);

        if ((isFirst || isLast) && !isLetter) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:19 userInfo:@{NSLocalizedDescriptionKey: @"The first and last segments of an NSID must start with a letter"}];
            return NO;
        }

        if (!isLetter && !isDigit) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:19 userInfo:@{NSLocalizedDescriptionKey: @"NSID segment must start with a letter or digit"}];
            return NO;
        }

        if (isLast && [comp containsString:@"-"]) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:19 userInfo:@{NSLocalizedDescriptionKey: @"The last segment of an NSID must not contain hyphens"}];
            return NO;
        }

        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9-]+$" options:0 error:nil];
        if ([regex numberOfMatchesInString:comp options:0 range:NSMakeRange(0, comp.length)] == 0) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:20 userInfo:@{NSLocalizedDescriptionKey: @"NSID contains invalid characters"}];
            return NO;
        }

        // Cannot end with -
        if ([comp hasSuffix:@"-"]) {

            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:19 userInfo:@{NSLocalizedDescriptionKey: @"NSID segment cannot end with hyphen"}];
            return NO;
        }
    }

    if ([nsid hasPrefix:@"."] || [nsid hasSuffix:@"."]) {
         if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:21 userInfo:@{NSLocalizedDescriptionKey: @"NSID cannot start or end with dot"}];
         return NO;
    }

    return YES;
}

+ (BOOL)validateDatetime:(NSString *)datetime error:(NSError **)error {
    if (!datetime) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Datetime cannot be nil"}];
        return NO;
    }

    NSString *pattern = @"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\\.[0-9]{1,20})?(Z|([+-][0-9]{2}:[0-9]{2}))$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if ([regex numberOfMatchesInString:datetime options:0 range:NSMakeRange(0, datetime.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:22 userInfo:@{NSLocalizedDescriptionKey: @"Invalid datetime format"}];
        return NO;
    }

    int y, m, d, hr, min, sec;
    sscanf([datetime UTF8String], "%d-%d-%dT%d:%d:%d", &y, &m, &d, &hr, &min, &sec);

    if (y < 0 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31 || hr < 0 || hr > 23 || min < 0 || min > 59 || sec < 0 || sec > 60) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:23 userInfo:@{NSLocalizedDescriptionKey: @"Datetime components out of range"}];
        return NO;
    }

    if ([datetime containsString:@"-00:00"]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:24 userInfo:@{NSLocalizedDescriptionKey: @"Negative zero timezone offset is prohibited"}];
        return NO;
    }

    return YES;
}

+ (BOOL)validateRkey:(NSString *)rkey error:(NSError **)error {
    if (!rkey) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:30 userInfo:@{NSLocalizedDescriptionKey: @"rkey cannot be nil"}];
        return NO;
    }

    if (rkey.length < 1 || rkey.length > 512) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:31 userInfo:@{NSLocalizedDescriptionKey: @"rkey length must be between 1 and 512 characters"}];
        return NO;
    }

    if ([rkey isEqualToString:@"."] || [rkey isEqualToString:@".."]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:32 userInfo:@{NSLocalizedDescriptionKey: @"rkey cannot be '.' or '..'"}];
        return NO;
    }

    static NSRegularExpression *rkeyRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rkeyRegex = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9._~-]+$" options:0 error:nil];
    });

    if ([rkeyRegex numberOfMatchesInString:rkey options:0 range:NSMakeRange(0, rkey.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:33 userInfo:@{NSLocalizedDescriptionKey: @"rkey contains invalid characters"}];
        return NO;
    }

    return YES;
}

@end
