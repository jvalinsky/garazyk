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

/**
 *  Actor signing key manager implementation for Linux/GNUstep compatibility.
 *  
 *  This class manages keys stored in a secure file-based keystore or 
 *  delegates to an OpenSSL-backed implementation.
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

/**
 *  Initializes a key manager for the given DID.
 *
 *  @param did The DID to manage keys for.
 *  @param keystorePath The directory to store/load keys.
 *  @return An initialized key manager.
 */
- (instancetype)initWithDid:(NSString *)did keystorePath:(NSString *)keystorePath;

@end

NS_ASSUME_NONNULL_END
