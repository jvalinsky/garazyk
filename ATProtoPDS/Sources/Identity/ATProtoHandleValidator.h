#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ATProtoHandleErrorDomain;
extern NSString * const ATProtoEmailErrorDomain;

@interface ATProtoHandleValidator : NSObject

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;

+ (NSString *)normalizeHandle:(NSString *)handle;

+ (nullable NSString *)validateAndNormalizeHandle:(NSString *)handle error:(NSError **)error;

+ (BOOL)validateEmail:(NSString *)email error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
