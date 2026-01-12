#ifndef SecKey_h
#define SecKey_h

#import "Security.h"

@class NSData;

NS_ASSUME_NONNULL_BEGIN

@interface SecKeyWrapper : NSObject

+ (nullable NSData *)publicKeyFromData:(NSData *)keyData error:(NSError **)error;
+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error;
+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* SecKey_h */
