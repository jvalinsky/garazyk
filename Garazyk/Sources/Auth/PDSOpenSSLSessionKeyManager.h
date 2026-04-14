/*!
 @file PDSOpenSSLSessionKeyManager.h

 @abstract OpenSSL-based key manager for Linux compatibility.

 @discussion
    OpenSSL-based implementation of PDSKeyManager for platforms where
    Security.framework is not available (Linux). Uses libcrypto for
    key generation, signing, and verification operations.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @class PDSOpenSSLSessionKeyManager

 @abstract OpenSSL-based implementation of PDSKeyManager for Linux compatibility.

 @discussion
    Use this class on platforms where Security.framework is not available.
    Keys are stored in the database with encrypted private key material.

    Thread Safety: This class is thread-safe. Database operations are
    serialized internally.
 */
@interface PDSOpenSSLSessionKeyManager : NSObject <PDSKeyManager>

/*! The database for key storage. */
@property (nonatomic, strong, nullable) PDSDatabase *database;

/*!
 @method initWithDatabase:

 @abstract Initializes the key manager with a database.

 @param database The database for key storage.

 @return A new PDSOpenSSLSessionKeyManager instance, or nil on failure.
 */
- (nullable instancetype)initWithDatabase:(PDSDatabase *)database;

@end

NS_ASSUME_NONNULL_END
