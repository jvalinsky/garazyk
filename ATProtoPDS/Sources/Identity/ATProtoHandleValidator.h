#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoHandleValidator : NSObject

/*!
 @method validateHandle:error:
 
 @abstract Validates an ATProto handle.
 
 @discussion Checks that the handle adheres to proper DNS syntax and ATProto specific rules:
 - Max length 253 chars
 - Valid DNS labels (LDH rule)
 - Not an IP address
 - proper TLD
 
 @param handle The handle string to validate.
 @param error Output error if validation fails.
 @return YES if valid, NO otherwise.
 */
+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;

/*!
 @method normalizeHandle:
 
 @abstract Normalizes a handle string.
 
 @discussion Lowercases the handle.
 
 @param handle The handle to normalize.
 @return The normalized handle.
 */
+ (NSString *)normalizeHandle:(NSString *)handle;

@end

NS_ASSUME_NONNULL_END
