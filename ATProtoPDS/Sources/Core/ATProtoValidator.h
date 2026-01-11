#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoValidator : NSObject

+ (BOOL)validateDID:(NSString *)did error:(NSError **)error;
+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;
+ (BOOL)validateCID:(NSString *)cid error:(NSError **)error;
+ (BOOL)validateTID:(NSString *)tid error:(NSError **)error;
+ (BOOL)validateNSID:(NSString *)nsid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
