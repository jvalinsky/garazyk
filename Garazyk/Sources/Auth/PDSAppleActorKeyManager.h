// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAppleActorKeyManager.h

 @abstract Apple Security.framework implementation of actor key management.

 @discussion
    Manages per-user secp256k1 signing keys using the Apple Keychain for
    secure storage. Falls back to in-memory storage if Keychain access fails.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSActorKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSAppleActorKeyManager;

/**
 * @abstract Defines the PDSAppleActorKeyManagerDelegate protocol contract.
 */
@protocol PDSAppleActorKeyManagerDelegate <NSObject>
@optional
/**
 * @abstract Performs the appleActorKeyManager operation.
 */
- (BOOL)appleActorKeyManager:(PDSAppleActorKeyManager *)manager
             storeSigningKey:(NSData *)privateKey
                   publicKey:(NSData *)publicKey
                       error:(NSError **)error;

/**
 * @abstract Performs the appleActorKeyManagerLoadSigningKey operation.
 */
- (nullable NSData *)appleActorKeyManagerLoadSigningKey:(PDSAppleActorKeyManager *)manager
                                                 error:(NSError **)error;
@end


/*!
 @class PDSAppleActorKeyManager

 @abstract Apple Security.framework implementation of actor key management.

 @discussion
    Manages per-user signing keys stored in the Keychain. Keys are stored
    with the following attributes:
    - kSecClass: kSecClassKey
    - kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom
    - kSecAttrKeyClass: kSecAttrKeyClassPrivate
    - kSecAttrApplicationTag: DID-specific tag

    If Keychain storage fails, keys are held in memory only (non-persistent).

    Thread Safety: This class is thread-safe. Keychain operations are
    serialized internally.
 */
/**
 * @abstract Declares the PDSAppleActorKeyManager public API.
 */
@interface PDSAppleActorKeyManager : NSObject <PDSActorKeyManager>

/*! The DID this key manager is responsible for. */
@property (nonatomic, copy, readonly) NSString *did;
@property (nonatomic, weak, nullable) id<PDSAppleActorKeyManagerDelegate> delegate;

/*!
 @method initWithDid:

 @abstract Initialize with a DID.

 @param did The DID to manage keys for. Used as the Keychain tag.

 @return A new PDSAppleActorKeyManager instance.
 */
- (instancetype)initWithDid:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
