/*!
 @file TOTPService.h

 @abstract TOTP service for two-factor authentication management.

 @discussion Provides high-level TOTP operations including secret generation,
 QR code creation for authenticator apps, and code verification. Integrates
 with hardware tokens via YubiKey OATH.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Auth/YubiKeyOATH.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class TOTPService

 @abstract Manages TOTP-based two-factor authentication.

 @discussion Supports software authenticators via QR code enrollment and
 hardware tokens via YubiKey integration.
 */
@interface TOTPService : NSObject

/*! YubiKey OATH manager for hardware token support. */
@property (nonatomic, strong, readonly) YubiKeyOATHManager *yubiKeyManager;

/*! The shared secret for TOTP generation. */
@property (nonatomic, strong) NSData *secret;

/*! Counter for HOTP mode (if used). */
@property (nonatomic, assign) uint64_t counter;

/*! Generates a random Base32-encoded secret (20 bytes -> 32 chars). */
+ (NSString *)generateSecret;

/*! Generates a PNG QR code image for authenticator app enrollment. */
+ (nullable NSData *)generateQRCodeImageForSecret:(NSString *)secret
                                        accountName:(NSString *)accountName
                                             issuer:(NSString *)issuer;

/*! Verifies a TOTP code against a secret. */
+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret;

/*! Initializes service with a secret. */
- (instancetype)initWithSecret:(NSData *)secret;

/*! Generates a TOTP token using the service's secret. */
- (nullable NSString *)generateTOTPToken:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
