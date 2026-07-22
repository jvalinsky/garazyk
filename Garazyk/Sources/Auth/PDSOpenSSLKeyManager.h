// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  PDSOpenSSLKeyManager.h
//  ATProtoPDS
//
//  Created by Jack Valinsky on 2/18/26.
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PDSActorKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PDSOpenSSLActorKeyPurposeAccount;
FOUNDATION_EXPORT NSString * const PDSOpenSSLActorKeyPurposeSpace;

/**
 *  Actor signing key manager implementation for Linux/GNUstep compatibility.
 *  
 *  This class manages keys stored in a secure file-based keystore or 
 *  delegates to an OpenSSL-backed implementation.
 */
/**
 * @abstract Declares the PDSOpenSSLKeyManager public API.
 */
@interface PDSOpenSSLKeyManager : NSObject <PDSActorKeyManager>

/**
 *  The DID this key manager is associated with.
 */
@property (nonatomic, copy, readonly) NSString *did;

/**
 *  Directory where keys are stored (Linux specific).
 */
@property (nonatomic, copy, readonly) NSString *keystorePath;

/** Stable storage namespace for this actor signing key. */
@property (nonatomic, copy, readonly) NSString *keyPurpose;

/**
 *  Initializes a key manager for the given DID.
 *
 *  @param did The DID to manage keys for.
 *  @param keystorePath The directory to store/load keys.
 *  @return An initialized key manager.
 */
- (instancetype)initWithDid:(NSString *)did keystorePath:(NSString *)keystorePath;

/** Initializes a manager in the account or permissioned-space key namespace. */
- (instancetype)initWithDid:(NSString *)did
                keystorePath:(NSString *)keystorePath
                     purpose:(NSString *)purpose;

@end

NS_ASSUME_NONNULL_END
