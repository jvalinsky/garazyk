// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  ATURI.m
//  ATProtoPDS
//

#import "ATURI.h"

NSString *const ATURIErrorDomain = @"com.atproto.uri";

@implementation ATURI

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (nullable instancetype)uriWithString:(NSString *)string error:(NSError **)error {
    if (!string || ![string hasPrefix:@"at://"]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT URI prefix"}];
        return nil;
    }
    
    NSString *stripped = [string substringFromIndex:5];
    if (stripped.length == 0) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Empty AT URI authority"}];
        return nil;
    }

    if ([stripped hasSuffix:@"/"]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI must not have trailing slash"}];
        return nil;
    }

    NSArray<NSString *> *fragParts = [stripped componentsSeparatedByString:@"#"];
    if (fragParts.count > 1) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI must not contain fragment"}];
        return nil;
    }

    NSArray<NSString *> *parts = [stripped componentsSeparatedByString:@"/"];
    NSString *authority = parts[0];
    if (![self isValidAuthority:authority]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT URI authority (DID or handle)"}];
        return nil;
    }

    if (parts.count > 3) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI path has too many segments"}];
        return nil;
    }

    NSString *collection = parts.count > 1 ? parts[1] : nil;
    if (collection != nil && collection.length == 0) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI has empty path segment"}];
        return nil;
    }
    if (collection && collection.length > 0 && ![self isValidCollection:collection]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT URI collection name"}];
        return nil;
    }

    NSString *rkey = parts.count > 2 ? parts[2] : nil;
    if (rkey != nil && rkey.length == 0) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI has empty path segment"}];
        return nil;
    }
    if (rkey && rkey.length > 0 && rkey.length > 512) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI record key too long"}];
        return nil;
    }
    if (rkey && rkey.length > 0 && ![self isValidRkey:rkey]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT URI record key"}];
        return nil;
    }
    
    ATURI *uri = [[ATURI alloc] initPrivate];
    uri->_uriString = [string copy];
    uri->_did = [authority copy];
    uri->_collection = [collection copy] ?: @"";
    uri->_rkey = [rkey copy] ?: @"";
    return uri;
}

+ (BOOL)isValidAuthority:(NSString *)authority {
    if (authority.length == 0) return NO;
    if ([authority hasPrefix:@"did:"]) {
        NSArray *parts = [authority componentsSeparatedByString:@":"];
        if (parts.count < 3) return NO;
        if ([parts[1] length] == 0 || [parts[2] length] == 0) return NO;
        NSString *method = parts[1];
        for (NSUInteger i = 0; i < method.length; i++) {
            unichar c = [method characterAtIndex:i];
            if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) return NO;
        }
        NSString *identifier = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@":"];
        for (NSUInteger i = 0; i < identifier.length; i++) {
            unichar c = [identifier characterAtIndex:i];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.')) return NO;
        }
        return YES;
    }
    // Handle validation: must have at least 2 labels, TLD must start with a letter
    NSArray<NSString *> *labels = [authority componentsSeparatedByString:@"."];
    if (labels.count < 2) return NO;
    NSString *tld = [labels lastObject];
    if (tld.length == 0) return NO;
    unichar first = [tld characterAtIndex:0];
    return (first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z');
}

+ (BOOL)isValidCollection:(NSString *)collection {
    if (collection.length == 0) return NO;
    NSArray *parts = [collection componentsSeparatedByString:@"."];
    if (parts.count < 3) return NO;
    for (NSString *part in parts) {
        if (part.length == 0) return NO;
        unichar first = [part characterAtIndex:0];
        if (first == '-' || first == '_') return NO;
        for (NSUInteger i = 0; i < part.length; i++) {
            unichar c = [part characterAtIndex:i];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.')) return NO;
        }
    }
    return YES;
}

+ (BOOL)isValidRkey:(NSString *)rkey {
    if (rkey.length == 0) return NO;
    if ([rkey isEqualToString:@"."] || [rkey isEqualToString:@".."]) return NO;
    // Check for invalid characters (atproto rkey allows a specific set)
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:"];
    return [[rkey stringByTrimmingCharactersInSet:allowed] length] == 0;
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

@end

@implementation ATDID

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (nullable instancetype)didWithString:(NSString *)string error:(NSError **)error {
    if (!string || ![string hasPrefix:@"did:"]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid DID prefix"}];
        return nil;
    }
    
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@":"];
    if (parts.count < 3) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"DID must contain method and identifier"}];
        return nil;
    }
    
    ATDID *didObj = [[ATDID alloc] initPrivate];
    didObj->_didString = [string copy];
    didObj->_method = [parts[1] copy];
    didObj->_identifier = [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@":"];
    return didObj;
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

@end
