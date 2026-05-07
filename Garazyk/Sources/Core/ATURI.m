//
//  ATURI.m
//  ATProtoPDS
//

#import "ATURI.h"

NSString *const ATURIErrorDomain = @"com.atproto.uri";

@implementation ATURI

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

    NSArray<NSString *> *parts = [stripped componentsSeparatedByString:@"/"];
    NSString *authority = parts[0];
    if (![self isValidAuthority:authority]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT URI authority (DID or handle)"}];
        return nil;
    }

    NSString *collection = parts.count > 1 ? parts[1] : nil;
    if (collection && collection.length > 0 && ![self isValidCollection:collection]) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid AT URI collection name"}];
        return nil;
    }

    NSString *rkey = parts.count > 2 ? parts[2] : nil;
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
        return parts.count >= 3 && [parts[1] length] > 0 && [parts[2] length] > 0;
    }
    // Handle validation (basic)
    return [authority componentsSeparatedByString:@"."].count >= 2;
}

+ (BOOL)isValidCollection:(NSString *)collection {
    if (collection.length == 0) return NO;
    NSArray *parts = [collection componentsSeparatedByString:@"."];
    if (parts.count < 3) return NO; // com.example.foo
    for (NSString *part in parts) {
        if (part.length == 0) return NO;
    }
    return YES;
}

+ (BOOL)isValidRkey:(NSString *)rkey {
    if (rkey.length == 0) return NO;
    if ([rkey isEqualToString:@"."] || [rkey isEqualToString:@".."]) return NO;
    // Check for invalid characters (atproto rkey allows a specific set)
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [[rkey stringByTrimmingCharactersInSet:allowed] length] == 0;
}

- (instancetype)initPrivate {
    self = [super init];
    return self;
}

@end

@implementation ATDID

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
