// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Mikrus/MikrusSourceSpec.h"

NSString * const MikrusSourceSpecErrorDomain = @"blue.microcosm.mikrus.source";

@implementation MikrusSourceSpec

- (instancetype)initPrivateWithCollection:(NSString *)collection path:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    _collection = [collection copy];
    _path = [path copy];
    return self;
}

+ (nullable instancetype)sourceSpecWithString:(NSString *)source error:(NSError **)error {
    if (![source isKindOfClass:[NSString class]] || source.length == 0) {
        if (error) *error = [self errorWithMessage:@"source is required"];
        return nil;
    }

    NSArray<NSString *> *parts = [source componentsSeparatedByString:@":"];
    if (parts.count != 2 || parts[0].length == 0 || parts[1].length == 0) {
        if (error) *error = [self errorWithMessage:@"source must be <collection>:<path>"];
        return nil;
    }

    NSString *collection = parts[0];
    NSString *path = [self normalizedPath:parts[1] error:error];
    if (![self validateCollection:collection]) {
        if (error) *error = [self errorWithMessage:@"source collection must be an NSID"];
        return nil;
    }
    if (path.length == 0) {
        return nil;
    }
    return [[self alloc] initPrivateWithCollection:collection path:path];
}

+ (BOOL)validatePath:(NSString *)path error:(NSError **)error {
    return [self normalizedPath:path error:error] != nil;
}

+ (nullable NSString *)normalizedPath:(NSString *)path error:(NSError **)error {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        if (error) *error = [self errorWithMessage:@"path is required"];
        return nil;
    }

    if ([path isEqualToString:@"."]) {
        return path;
    }

    NSString *normalized = path;
    if ([normalized hasPrefix:@"."]) {
        normalized = [normalized substringFromIndex:1];
    }
    if (normalized.length == 0) {
        if (error) *error = [self errorWithMessage:@"path is required"];
        return nil;
    }

    NSArray<NSString *> *segments = [normalized componentsSeparatedByString:@"."];
    if (segments.count == 0) {
        if (error) *error = [self errorWithMessage:@"path is required"];
        return nil;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$-"];
    NSCharacterSet *disallowed = [allowed invertedSet];
    for (NSString *segment in segments) {
        NSString *key = segment;
        if ([key hasSuffix:@"[]"]) {
            key = [key substringToIndex:key.length - 2];
        }
        if (key.length == 0 ||
            [key rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
            if (error) *error = [self errorWithMessage:@"path contains an invalid segment"];
            return nil;
        }
    }
    return normalized;
}

+ (BOOL)validateCollection:(NSString *)collection {
    NSArray<NSString *> *segments = [collection componentsSeparatedByString:@"."];
    if (segments.count < 3) return NO;

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    NSCharacterSet *disallowed = [allowed invertedSet];
    for (NSString *segment in segments) {
        if (segment.length == 0 ||
            [segment rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
            return NO;
        }
    }
    return YES;
}

+ (NSError *)errorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:MikrusSourceSpecErrorDomain
                               code:400
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid source"}];
}

@end
