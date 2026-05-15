// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoDataPaths.h

 @abstract Unified path configuration for all PDS data directories.

 @discussion Centralizes directory layout calculation so consumers reference
 a single source of truth instead of computing paths ad-hoc. Actor stores
 are sharded by DID method and a 2-character prefix of the method-specific
 identifier for filesystem performance at scale.

 Directory layout:
 @code
 {base}/
   plc/{2-char}/{did}           # actor stores for did:plc: DIDs
   web/{2-char}/{did}           # actor stores for did:web: DIDs
   service/                     # service database
   did_cache/                   # DID cache database
   sequencer/                   # sequencer database
   blobs/                       # blob storage
   lexicons/                    # lexicon files
   keys/                        # rotation key storage
   cache/explore/               # explore cache
 @endcode

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoDataPaths : NSObject

@property (nonatomic, copy, readonly) NSString *baseDirectory;

@property (nonatomic, copy, readonly) NSString *serviceDirectory;
@property (nonatomic, copy, readonly) NSString *didCacheDirectory;
@property (nonatomic, copy, readonly) NSString *sequencerDirectory;

@property (nonatomic, copy, readonly) NSString *blobsDirectory;
@property (nonatomic, copy, readonly) NSString *lexiconsDirectory;
@property (nonatomic, copy, readonly) NSString *keysDirectory;
@property (nonatomic, copy, readonly) NSString *exploreCacheDirectory;

+ (instancetype)pathsForBaseDirectory:(NSString *)baseDirectory;
- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory;

- (BOOL)createDirectoriesWithError:(NSError **)error;

/*!
 @brief Returns the actor store path for a DID, sharded by method and 2-char prefix.

 @discussion For @c did:plc:z72i7h... returns @c {base}/plc/z7/did:plc:z72i7h...
 For @c did:web:example.com returns @c {base}/web/ex/did:web:example.com
 */
- (NSString *)actorStorePathForDid:(NSString *)did;

- (NSString *)keyPathForDid:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
