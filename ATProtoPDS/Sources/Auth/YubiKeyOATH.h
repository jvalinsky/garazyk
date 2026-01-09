#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol YubiKeyOATH <NSObject>
- (nullable NSString *)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error;
- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error;
@end

@interface YubiKeyOATHManager : NSObject <YubiKeyOATH>
@end

NS_ASSUME_NONNULL_END