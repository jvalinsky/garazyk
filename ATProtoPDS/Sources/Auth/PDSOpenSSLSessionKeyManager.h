//
//  PDSOpenSSLSessionKeyManager.h
//  ATProtoPDS
//
//  Created by Jack Valinsky on 2/18/26.
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PDSKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/**
 * @class PDSOpenSSLSessionKeyManager
 * @brief OpenSSL-based implementation of PDSKeyManager for Linux compatibility.
 *
 * Use this class on platforms where Security.framework is not available (Linux).
 * It uses OpenSSL (libcrypto) for RSA key generation, signing, and export.
 */
@interface PDSOpenSSLSessionKeyManager : NSObject <PDSKeyManager>

@property (nonatomic, strong, nullable) PDSDatabase *database;

- (nullable instancetype)initWithDatabase:(PDSDatabase *)database;

@end

NS_ASSUME_NONNULL_END
