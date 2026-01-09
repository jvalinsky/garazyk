#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TOTPService : NSObject

// Generates a random Base32 secret (20 bytes -> 32 chars)
+ (NSString *)generateSecret;

// Generates a PNG QR Code for the otpauth:// URL
+ (nullable NSData *)generateQRCodeImageForSecret:(NSString *)secret 
                                        accountName:(NSString *)accountName 
                                             issuer:(NSString *)issuer;

// Verifies a code against a secret
+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret;

@end

NS_ASSUME_NONNULL_END
