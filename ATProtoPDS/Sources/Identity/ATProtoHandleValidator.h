#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoHandleValidator : NSObject

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;

+ (BOOL)validateHandleSyntax:(NSString *)handle error:(NSError **)error;

+ (NSString *)normalizeHandle:(NSString *)handle;

@end

NS_ASSUME_NONNULL_END
