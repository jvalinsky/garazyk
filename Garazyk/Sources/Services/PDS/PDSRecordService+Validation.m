// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService+Validation.h"
#import "Core/TID.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#include <math.h>

NSErrorDomain const PDSRecordServiceErrorDomain = @"com.atproto.pds.record-service";

const NSTimeInterval kATProtoCreatedAtMaxSkewSeconds = 24.0 * 60.0 * 60.0;
const NSInteger kPDSRecordServiceMaxJSONNestingDepth = 32;

NSError *PDSRecordServiceShapeError(NSString *message) {
    return [NSError errorWithDomain:PDSRecordServiceErrorDomain
                               code:2001
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid record JSON shape"}];
}

BOOL PDSRecordServiceValidateJSONShapeAtDepth(id value,
                                                     NSInteger depth,
                                                     NSString *context,
                                                     NSError **error) {
    if (depth > kPDSRecordServiceMaxJSONNestingDepth) {
        if (error) {
            *error = PDSRecordServiceShapeError(
                [NSString stringWithFormat:@"Maximum record nesting depth (%ld) exceeded at %@",
                                           (long)kPDSRecordServiceMaxJSONNestingDepth,
                                           context ?: @"record"]);
        }
        return NO;
    }

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)value;
        for (id key in dict) {
            NSString *keyContext = [key isKindOfClass:[NSString class]] ? key : [key description];
            NSString *childContext = context.length > 0
                ? [NSString stringWithFormat:@"%@.%@", context, keyContext ?: @"(key)"]
                : keyContext ?: @"record";
            if (!PDSRecordServiceValidateJSONShapeAtDepth(dict[key], depth + 1, childContext, error)) {
                return NO;
            }
        }
        return YES;
    }

    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)value;
        for (NSUInteger i = 0; i < array.count; i++) {
            NSString *childContext = [NSString stringWithFormat:@"%@[%lu]",
                                                                context ?: @"record",
                                                                (unsigned long)i];
            if (!PDSRecordServiceValidateJSONShapeAtDepth(array[i], depth + 1, childContext, error)) {
                return NO;
            }
        }
        return YES;
    }

    return YES;
}

BOOL PDSRecordServiceValidateRecordJSONShape(NSDictionary *record, NSError **error) {
    return PDSRecordServiceValidateJSONShapeAtDepth(record, 0, @"record", error);
}

NSString *PDSRecordServiceDIDFromATURI(NSString *uri) {
    if (![uri isKindOfClass:[NSString class]] || ![uri hasPrefix:@"at://"]) {
        return nil;
    }
    NSString *withoutScheme = [uri substringFromIndex:5];
    NSRange slash = [withoutScheme rangeOfString:@"/"];
    if (slash.location == NSNotFound || slash.location == 0) {
        return nil;
    }
    return [withoutScheme substringToIndex:slash.location];
}

NSDictionary *PDSRecordServiceJSONObjectFromRecordValue(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        return value;
    }
    if (![value respondsToSelector:@selector(dataUsingEncoding:)]) {
        return nil;
    }
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

BOOL PDSRecordServiceRecordMentionsDID(NSDictionary *record, NSString *did) {
    NSArray *facets = record[@"facets"];
    if (![facets isKindOfClass:[NSArray class]]) {
        return NO;
    }
    for (NSDictionary *facet in facets) {
        if (![facet isKindOfClass:[NSDictionary class]]) continue;
        NSArray *features = facet[@"features"];
        if (![features isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *feature in features) {
            if (![feature isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = feature[@"$type"];
            NSString *mentionDID = feature[@"did"];
            if ([type isEqualToString:@"app.bsky.richtext.facet#mention"] &&
                [mentionDID isEqualToString:did]) {
                return YES;
            }
        }
    }
    return NO;
}

NSError *PDSRecordServiceReplyNotAllowedError(void) {
    return [NSError errorWithDomain:PDSRecordServiceErrorDomain
                               code:403
                           userInfo:@{NSLocalizedDescriptionKey: @"ReplyNotAllowed: Reply not allowed by threadgate"}];
}

BOOL validateCreatedAtCoherence(NSString *collection,
                                       NSString *rkey,
                                       NSDictionary *value,
                                       PDSValidationMode mode,
                                       NSError **error) {
    if (mode == PDSValidationModeOff) {
        return YES;
    }
    if (![collection isKindOfClass:[NSString class]] || collection.length == 0) {
        return YES;
    }
    // Guardrail for AppView compatibility: app.bsky.feed.post should have a createdAt
    // timestamp that is reasonably close to the rkey TID timestamp.
    if (![collection isEqualToString:@"app.bsky.feed.post"]) {
        return YES;
    }
    id createdAtValue = value[@"createdAt"];
    if (![createdAtValue isKindOfClass:[NSString class]] || ((NSString *)createdAtValue).length == 0) {
        return YES;
    }
    TID *tid = [TID tidFromString:rkey];
    if (!tid) {
        return YES;
    }
    NSDate *createdAtDate = [NSDateFormatter atproto_dateFromString:(NSString *)createdAtValue];
    if (!createdAtDate) {
        return YES;
    }
    NSDate *rkeyDate = [NSDate dateWithTimeIntervalSince1970:((NSTimeInterval)tid.timestamp / 1000000.0)];
    NSTimeInterval skew = fabs([createdAtDate timeIntervalSinceDate:rkeyDate]);
    if (skew <= kATProtoCreatedAtMaxSkewSeconds) {
        return YES;
    }
    if (error) {
        *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                     code:400
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:
                                                     @"createdAt is too far from rkey timestamp (skew %.0fs > %.0fs)",
                                                     skew, kATProtoCreatedAtMaxSkewSeconds]}];
    }
    return NO;
}

BOOL rejectUnknownBuiltInCollection(NSString *collection,
                                           PDSValidationMode mode,
                                           NSError **error) {
    if (mode == PDSValidationModeOff) {
        return NO;
    }
    if (![collection isKindOfClass:[NSString class]] ||
        ![collection hasPrefix:@"app.bsky."]) {
        return NO;
    }
    if ([[ATProtoLexiconRegistry sharedRegistry] hasSchemaForNSID:collection]) {
        return NO;
    }
    if (error) {
        *error = [NSError errorWithDomain:PDSRecordServiceErrorDomain
                                     code:400
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Lexicon schema not found for '%@'", collection]}];
    }
    return YES;
}
