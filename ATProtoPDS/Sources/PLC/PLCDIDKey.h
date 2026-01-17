#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, PLCDIDKeyType) {
    PLCDIDKeyTypeSecp256k1 = 0,
    PLCDIDKeyTypeP256 = 1,
};

@interface PLCDIDKey : NSObject

@property (nonatomic, readonly) PLCDIDKeyType type;
@property (nonatomic, readonly) NSData *publicKeyBytes;

+ (nullable instancetype)parseFromString:(NSString *)didKey error:(NSError **)error;
+ (BOOL)isValidDidKeyString:(NSString *)didKey error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
