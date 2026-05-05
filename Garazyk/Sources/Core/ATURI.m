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
    NSArray<NSString *> *parts = [stripped componentsSeparatedByString:@"/"];
    if (parts.count < 3) {
        if (error) *error = [NSError errorWithDomain:ATURIErrorDomain code:400 userInfo:@{NSLocalizedDescriptionKey: @"AT URI must contain did, collection, and rkey"}];
        return nil;
    }
    
    ATURI *uri = [[ATURI alloc] initPrivate];
    uri->_uriString = [string copy];
    uri->_did = [parts[0] copy];
    uri->_collection = [parts[1] copy];
    uri->_rkey = [parts[2] copy];
    return uri;
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
