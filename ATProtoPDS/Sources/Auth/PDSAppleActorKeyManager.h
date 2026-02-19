//
//  PDSAppleActorKeyManager.h
//  ATProtoPDS
//
//  Created by Antigravity on 2026-02-19.
//

#import <Foundation/Foundation.h>
#import "PDSKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSAppleActorKeyManager
 @abstract Apple Security.framework implementation of PDSKeyManagerProtocol for Actor keys.
 @discussion Manages per-user signing keys stored in the Keychain (or memory fallback).
 Replaces the direct Security.framework usage in ActorStore.
 */
@interface PDSAppleActorKeyManager : NSObject <PDSKeyManager>

/*! The DID this key manager is responsible for. */
@property (nonatomic, copy, readonly) NSString *did;

/*!
 Initialize with a DID.
 @param did The DID to manage keys for.
 */
- (instancetype)initWithDid:(NSString *)did;

/*!
 Import a raw private key (32 bytes).
 */
- (BOOL)importKey:(NSData *)keyData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
