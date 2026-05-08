#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSKeyEnvelope : NSObject

+ (nullable NSData *)encryptData:(NSData *)data
                         withKey:(NSData *)key;

+ (nullable NSData *)decryptData:(NSData *)data
                         withKey:(NSData *)key;

+ (BOOL)isVersionedEnvelope:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
