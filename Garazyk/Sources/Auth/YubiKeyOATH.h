// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file YubiKeyOATH.h

 @abstract Software-only OATH/TOTP compatibility helper.

 @discussion The PDS does not access a user's local YubiKey over USB/NFC.
 YubiKey Authenticator can hold a TOTP secret client-side and submit a normal
 six-digit code. Phishing-resistant YubiKey login is implemented through
 WebAuthn/security-key assertions.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!

 @abstract YubiKey connection state.

 @constant YubiKeyConnectionStateDisconnected No YubiKey detected.
 @constant YubiKeyConnectionStateConnecting Connecting to YubiKey.
 @constant YubiKeyConnectionStateConnected YubiKey connected and ready.
 @constant YubiKeyConnectionStateError Connection error occurred.
 */
typedef NS_ENUM(NSInteger, YubiKeyConnectionState) {
    YubiKeyConnectionStateDisconnected = 0,
    YubiKeyConnectionStateConnecting,
    YubiKeyConnectionStateConnected,
    YubiKeyConnectionStateError
};

/*! Error domain for YubiKey OATH operations. */
extern NSString * const YubiKeyOATHErrorDomain;

/*!

 @abstract YubiKey OATH error codes.

 @constant YubiKeyOATHErrorNotImplemented Feature not implemented.
 @constant YubiKeyOATHErrorNoKeyFound No YubiKey detected.
 @constant YubiKeyOATHErrorConnectionFailed Connection to YubiKey failed.
 @constant YubiKeyOATHErrorSecretSetFailed Failed to store OATH secret.
 @constant YubiKeyOATHErrorInvalidSecret OATH secret format invalid.
 @constant YubiKeyOATHErrorVerificationFailed TOTP verification failed.
 */
typedef NS_ENUM(NSInteger, YubiKeyOATHError) {
    YubiKeyOATHErrorNotImplemented = 1000,
    YubiKeyOATHErrorNoKeyFound,
    YubiKeyOATHErrorConnectionFailed,
    YubiKeyOATHErrorSecretSetFailed,
    YubiKeyOATHErrorInvalidSecret,
    YubiKeyOATHErrorVerificationFailed
};

/*!
 @protocol YubiKeyOATH

 @abstract OATH-TOTP operations protocol.

 @discussion Defines interface for TOTP generation and secret storage.
 */
@protocol YubiKeyOATH <NSObject>

/*! Generate TOTP code for secret and counter. */
- (nullable NSString *)generateTOTPForSecret:(NSData *)secret counter:(uint64_t)counter error:(NSError **)error;

/*! Store OATH secret on YubiKey with name. */
- (BOOL)setOATHSecret:(NSData *)secret name:(NSString *)name error:(NSError **)error;

@end

/*!
 @protocol YubiKeyOATHManagerDelegate

 @abstract Delegate for YubiKey connection events.

 @discussion Receives notifications for connection state changes, key detection,
 and errors.
 */
@protocol YubiKeyOATHManagerDelegate <NSObject>

@optional

/*! Called when connection state changes. */
- (void)yubiKeyManager:(id)manager didChangeConnectionState:(YubiKeyConnectionState)state;

/*! Called when YubiKey detected with serial number. */
- (void)yubiKeyManager:(id)manager didDetectKeyWithSerial:(NSString *)serial;

/*! Called when error occurs. */
- (void)yubiKeyManager:(id)manager didFailWithError:(NSError *)error;

@end

/*!
 @class YubiKeyOATHManager

 @abstract Manager for software-only OATH compatibility operations.

 @discussion Does not perform YubiKey detection or OATH credential management
 in the server process. Provides software TOTP generation so existing callers
 keep working while real YubiKey login uses WebAuthn.

 @warning Hardware YubiKey operations are **not implemented**. The manager
          runs in software-only mode: TOTP generation falls back to the
          software TOTPGenerator, and all hardware operations (setOATHSecret,
          listCredentials, deleteCredential, resetAllCredentials) fail with
          YubiKeyOATHErrorNotImplemented. Use WebAuthn for YubiKey security-key
          authentication.

 Thread-safety: Methods are not thread-safe. Use from main thread only.
 */
@interface YubiKeyOATHManager : NSObject <YubiKeyOATH>

/*! Delegate for connection events. */
@property (nonatomic, weak, nullable) id<YubiKeyOATHManagerDelegate> delegate;

/*! Current connection state. */
@property (nonatomic, assign, readonly) YubiKeyConnectionState connectionState;

/*! Serial number of connected YubiKey. */
@property (nonatomic, copy, readonly, nullable) NSString *connectedKeySerial;

/*! Whether YubiKey hardware support is available. */
@property (nonatomic, assign, readonly) BOOL isHardwareAvailable;

/*! Start scanning for YubiKey devices. */
- (void)startScanning;

/*! Stop scanning for YubiKey devices. */
- (void)stopScanning;

/*! Refresh connection to YubiKey. */
- (void)refreshConnection;

/*! List all OATH credentials stored on YubiKey. */
- (nullable NSArray<NSDictionary *> *)listCredentialsWithError:(NSError **)error;

/*! Delete OATH credential by name. */
- (BOOL)deleteCredentialWithName:(NSString *)name error:(NSError **)error;

/*! Reset all OATH credentials (factory reset). */
- (BOOL)resetAllCredentialsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
