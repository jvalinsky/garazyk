// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class PDSSpaceLtHash;
@protocol PDSActorKeyManager;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceCommitErrorDomain;

@interface PDSSpaceCommit : NSObject

@property(nonatomic, readonly) NSInteger version;
/** The 32-byte SHA-256 digest of the LtHash state. */
@property(nonatomic, readonly, copy) NSData *commitHash;
@property(nonatomic, readonly, copy) NSData *mac;
@property(nonatomic, readonly, copy) NSData *ikm;
@property(nonatomic, readonly, copy) NSData *signature;
@property(nonatomic, readonly, copy) NSString *rev;

+ (nullable instancetype)commitForSetHash:(PDSSpaceLtHash *)setHash
                                     space:(NSString *)space
                                    author:(NSString *)author
                                       rev:(NSString *)rev
                       actorKeyManager:(id<PDSActorKeyManager>)actorKeyManager
                                    error:(NSError **)error;

/** Reconstructs a commit from a DAG-CBOR-decoded dictionary.
 *  The dictionary must contain @c ver, @c hash, @c mac, @c ikm, @c sig,
 *  and @c rev with the expected types.  Returns @c nil on malformed input. */
+ (nullable instancetype)commitFromDictionary:(NSDictionary *)dict error:(NSError **)error;

- (BOOL)verifyIntegrityForSpace:(NSString *)space author:(NSString *)author error:(NSError **)error;
- (BOOL)verifySignatureForSpace:(NSString *)space author:(NSString *)author publicKey:(NSData *)publicKey error:(NSError **)error;

/** Context bytes signed by commits: domain tag + uint16BE-length-prefixed fields. */
+ (nullable NSData *)contextForSpace:(NSString *)space
                              author:(NSString *)author
                                 rev:(NSString *)rev
                                 ikm:(NSData *)ikm
                               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
