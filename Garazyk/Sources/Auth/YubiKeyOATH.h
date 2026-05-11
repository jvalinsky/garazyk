// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file YubiKeyOATH.h

 @abstract YubiKey hardware OATH/TOTP support.

 @discussion Provides interface to YubiKey hardware tokens for TOTP generation.
 Supports YubiKey 5 series with OATH-TOTP credentials. Used for hardware-based
 two-factor authentication.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum YubiKeyConnectionState

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
 @enum YubiKeyOATHError

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

 @abstract Manager for YubiKey OATH operations.

 @discussion Handles YubiKey detection, connection, and OATH credential management.
 Supports YubiKey 5 series over USB/NFC. Provides TOTP generation for hardware
 two-factor authentication.

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
