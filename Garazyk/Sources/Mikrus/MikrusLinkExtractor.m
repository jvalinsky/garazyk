// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Mikrus/MikrusLinkExtractor.h"

@implementation MikrusLinkExtractor

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)linkEntriesInRecord:(NSDictionary *)record {
    if (![record isKindOfClass:[NSDictionary class]]) return @[];

    NSMutableArray<NSDictionary<NSString *, NSString *> *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    [self collectLinksFromObject:record path:@"" entries:entries seen:seen];
    return [entries copy];
}

+ (NSArray<NSString *> *)subjectsInRecord:(NSDictionary *)record path:(NSString *)path {
    if (![record isKindOfClass:[NSDictionary class]] ||
        ![path isKindOfClass:[NSString class]] ||
        path.length == 0) {
        return @[];
    }

    NSArray<NSString *> *components = [path componentsSeparatedByString:@"."];
    NSMutableArray<NSString *> *subjects = [NSMutableArray array];
    [self collectSubjectsFromObject:record
                         components:components
                              index:0
                            results:subjects];

    NSMutableArray<NSString *> *deduped = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *subject in subjects) {
        if (![seen containsObject:subject]) {
            [seen addObject:subject];
            [deduped addObject:subject];
        }
    }
    return [deduped copy];
}

+ (BOOL)isLinkSubject:(NSString *)value {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    return [value hasPrefix:@"at://"] ||
           [value hasPrefix:@"did:"] ||
           [value hasPrefix:@"http://"] ||
           [value hasPrefix:@"https://"];
}

+ (void)collectLinksFromObject:(id)object
                          path:(NSString *)path
                       entries:(NSMutableArray<NSDictionary<NSString *, NSString *> *> *)entries
                          seen:(NSMutableSet<NSString *> *)seen {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        for (NSString *key in dict) {
            if (![key isKindOfClass:[NSString class]]) continue;
            NSString *childPath = path.length > 0 ? [path stringByAppendingFormat:@".%@", key] : key;
            [self collectLinksFromObject:dict[key] path:childPath entries:entries seen:seen];
        }
        return;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        NSString *arrayPath = path.length > 0 ? [path stringByAppendingString:@"[]"] : @"[]";
        for (id item in (NSArray *)object) {
            [self collectLinksFromObject:item path:arrayPath entries:entries seen:seen];
        }
        return;
    }

    if ([object isKindOfClass:[NSString class]] && [self isLinkSubject:(NSString *)object]) {
        NSString *dedupeKey = [NSString stringWithFormat:@"%@\n%@", path ?: @"", object];
        if ([seen containsObject:dedupeKey]) return;
        [seen addObject:dedupeKey];
        [entries addObject:@{@"path": path ?: @"", @"subject": object}];
    }
}

+ (void)collectSubjectsFromObject:(id)object
                       components:(NSArray<NSString *> *)components
                            index:(NSUInteger)index
                          results:(NSMutableArray<NSString *> *)results {
    if (index >= components.count) {
        if ([object isKindOfClass:[NSString class]] && [self isLinkSubject:(NSString *)object]) {
            [results addObject:object];
        } else if ([object isKindOfClass:[NSArray class]]) {
            for (id item in (NSArray *)object) {
                [self collectSubjectsFromObject:item components:components index:index results:results];
            }
        }
        return;
    }

    if ([object isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)object) {
            [self collectSubjectsFromObject:item components:components index:index results:results];
        }
        return;
    }

    if (![object isKindOfClass:[NSDictionary class]]) return;

    NSString *component = components[index];
    BOOL expectsArray = [component hasSuffix:@"[]"];
    NSString *key = expectsArray ? [component substringToIndex:component.length - 2] : component;
    id next = ((NSDictionary *)object)[key];
    if (!next) return;

    if (expectsArray && [next isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)next) {
            [self collectSubjectsFromObject:item components:components index:index + 1 results:results];
        }
        return;
    }

    [self collectSubjectsFromObject:next components:components index:index + 1 results:results];
}

@end
