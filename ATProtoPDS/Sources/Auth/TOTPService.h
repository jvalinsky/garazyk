#import <Foundation/Foundation.h>
#import "Auth/YubiKeyOATH.h"

NS_ASSUME_NONNULL_BEGIN

@interface TOTPService : NSObject

@property (nonatomic, strong, readonly) YubiKeyOATHManager *yubiKeyManager;
@property (nonatomic, strong) NSData *secret;
@property (nonatomic, assign) uint64_t counter;

// Generates a random Base32 secret (20 bytes -> 32 chars)
+ (NSString *)generateSecret;

// Generates a PNG QR Code for the otpauth:// URL
+ (nullable NSData *)generateQRCodeImageForSecret:(NSString *)secret
                                        accountName:(NSString *)accountName
                                             issuer:(NSString *)issuer;

// Verifies a code against a secret
+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret;

// Instance methods for hardware/software TOTP integration
- (instancetype)initWithSecret:(NSData *)secret;
- (nullable NSString *)generateTOTPToken:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
