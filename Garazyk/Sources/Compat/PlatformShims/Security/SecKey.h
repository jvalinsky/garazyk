/**
 * @file SecKey.h
 *
 * @brief SecKey operations compatibility wrapper.
 *
 * Provides cross-platform wrapper for public key operations.
 * On macOS, uses Security framework. On Linux, uses OpenSSL/libsecp256k1.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifndef SecKey_h
#define SecKey_h

#import <Foundation/Foundation.h>

#ifdef __APPLE__
#import <Security/Security.h>
#else

// Import CF types
#import "../CoreFoundation/CFBase.h"

// Basic types
typedef struct SecKey *SecKeyRef;

// Constants (Algorithm Strings)
extern const CFStringRef _Nonnull kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256;
extern const CFStringRef _Nonnull kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
extern const CFStringRef _Nonnull kSecKeyAlgorithmECDSASignatureDigestX962SHA256;

extern const CFStringRef _Nonnull kSecAttrKeyType;
extern const CFStringRef _Nonnull kSecAttrKeyTypeRSA;
extern const CFStringRef _Nonnull kSecAttrKeyTypeECSECPrimeRandom;
extern const CFStringRef _Nonnull kSecAttrKeyClass;
extern const CFStringRef _Nonnull kSecAttrKeyClassPublic;
extern const CFStringRef _Nonnull kSecAttrKeyClassPrivate;
extern const CFStringRef _Nonnull kSecAttrKeySizeInBits;

// Functions
SecKeyRef _Nullable SecKeyCreateRandomKey(CFDictionaryRef _Nonnull attributes, CFErrorRef _Nullable * _Nullable error);
SecKeyRef _Nullable SecKeyCopyPublicKey(SecKeyRef _Nonnull privateKey);
CFDataRef _Nullable SecKeyCopyExternalRepresentation(SecKeyRef _Nonnull key, CFErrorRef _Nullable * _Nullable error);
SecKeyRef _Nullable SecKeyCreateWithData(CFDataRef _Nonnull keyData, CFDictionaryRef _Nonnull attributes, CFErrorRef _Nullable * _Nullable error);
CFDataRef _Nullable SecKeyCreateSignature(SecKeyRef _Nonnull key, CFStringRef _Nonnull algorithm, CFDataRef _Nonnull dataToSign, CFErrorRef _Nullable * _Nullable error);
Boolean SecKeyVerifySignature(SecKeyRef _Nonnull key, CFStringRef _Nonnull algorithm, CFDataRef _Nonnull signedData, CFDataRef _Nonnull signature, CFErrorRef _Nullable * _Nullable error);

#endif /* __APPLE__ */

NS_ASSUME_NONNULL_BEGIN

/*!
 @class SecKeyWrapper
 
 @abstract Cross-platform public key operations.
 
 @discussion Provides unified interface for public key operations
 across macOS (Security framework) and Linux (OpenSSL).
 */
@interface SecKeyWrapper : NSObject

/*! Extract public key from key data. */
+ (nullable NSData *)publicKeyFromData:(NSData *)keyData error:(NSError **)error;

/*! Encrypt data with public key. */
+ (nullable NSData *)encryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error;

/*! Decrypt data with private key. */
+ (nullable NSData *)decryptData:(NSData *)data withKey:(NSData *)key error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* SecKey_h */
