#import "ATProtoError.h"

NSString * const ATProtoErrorDomain = @"com.atproto.pds";
NSString * const ATProtoErrorUnderlyingCauseKey = @"com.atproto.pds.underlyingCause";

@implementation ATProtoError

+ (NSError *)errorWithCode:(ATProtoErrorCode)code message:(NSString *)message {
    return [self errorWithCode:code message:message userInfo:nil];
}

+ (NSError *)errorWithCode:(ATProtoErrorCode)code message:(NSString *)message underlyingError:(nullable NSError *)underlyingError {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (underlyingError) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
        userInfo[ATProtoErrorUnderlyingCauseKey] = underlyingError; // Additional key for explicit tracking
    }
    return [self errorWithCode:code message:message userInfo:userInfo];
}

+ (NSError *)errorWithCode:(ATProtoErrorCode)code message:(NSString *)message userInfo:(nullable NSDictionary<NSErrorUserInfoKey, id> *)userInfo {
    NSMutableDictionary *combinedUserInfo = [NSMutableDictionary dictionary];
    if (userInfo) {
        [combinedUserInfo addEntriesFromDictionary:userInfo];
    }
    
    // Ensure standard localized description is set if not provided
    if (!combinedUserInfo[NSLocalizedDescriptionKey]) {
        combinedUserInfo[NSLocalizedDescriptionKey] = message;
    }
    
    return [NSError errorWithDomain:ATProtoErrorDomain code:code userInfo:combinedUserInfo];
}

+ (NSError *)invalidInputWithMessage:(NSString *)message {
    return [self errorWithCode:ATProtoErrorCodeInvalidInput message:message];
}

@end
