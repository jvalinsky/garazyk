//
//  PDSAppleActorKeyManager.h
//  ATProtoPDS
//
//  Created by Antigravity on 2026-02-19.
//

#import <Foundation/Foundation.h>
#import "PDSActorKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class PDSAppleActorKeyManager
 @abstract Apple Security.framework implementation of actor key management for per-user signing keys.
 @discussion Manages per-user signing keys stored in the Keychain (or memory fallback).
 */
@interface PDSAppleActorKeyManager : NSObject <PDSActorKeyManager>

/*! The DID this key manager is responsible for. */
@property (nonatomic, copy, readonly) NSString *did;

/*!
 Initialize with a DID.
 @param did The DID to manage keys for.
 */
- (instancetype)initWithDid:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
