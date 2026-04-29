/*!
 @file TutorialIdentityService.h

 @abstract DID resolution and handle verification for tutorial examples.

 @discussion Implements identity resolution with:
 - DID document retrieval (did:web and did:plc)
 - Handle verification via DNS TXT and HTTPS well-known
 - Identity caching with TTL
 - Thread-safe via serial dispatch queue

 This is the educational version of the production identity service in
 Garazyk/Sources/Identity/ (DIDResolver, HandleResolver, IdentityService).

 Key concepts:
 - DIDs are persistent identifiers (did:web, did:plc)
 - Handles are human-readable (alice.example.com)
 - Handle verification: DNS TXT record or HTTPS /.well-known/atproto-did
 - DID documents contain signing keys and service endpoints
 - Caching reduces network lookups

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TutorialIdentityErrorDomain;

@interface TutorialDIDDocument : NSObject

@property (nonatomic, copy) NSString *did;
@property (nonatomic, copy, nullable) NSString *handle;
@property (nonatomic, strong) NSArray<NSDictionary *> *verificationMethods;
@property (nonatomic, strong) NSArray<NSDictionary *> *services;
@property (nonatomic, assign) NSTimeInterval cachedAt;

@end

@interface TutorialIdentityService : NSObject

/*! Cache TTL in seconds (default: 300 = 5 minutes). */
@property (nonatomic, assign) NSTimeInterval cacheTTL;

/*!
 @method initWithCacheDirectory:

 @abstract Creates an identity service with a cache directory.

 @param cacheDir The directory for persistent cache storage.
 @return A new identity service instance.
 */
- (instancetype)initWithCacheDirectory:(NSString *)cacheDir;

/*!
 @method resolveDID:error:

 @abstract Resolves a DID to its document.

 @param did The DID to resolve (e.g., "did:web:localhost:2583").
 @param error On failure, contains error details.
 @return The DID document, or nil on failure.
 */
- (nullable TutorialDIDDocument *)resolveDID:(NSString *)did
                                        error:(NSError **)error;

/*!
 @method resolveHandle:error:

 @abstract Resolves a handle to a DID.

 @discussion Looks up the handle via DNS TXT record (_atproto.handle)
 or HTTPS well-known (https://handle/.well-known/atproto-did).

 @param handle The handle to resolve (e.g., "alice.example.com").
 @param error On failure, contains error details.
 @return The DID, or nil on failure.
 */
- (nullable NSString *)resolveHandle:(NSString *)handle
                               error:(NSError **)error;

/*!
 @method verifyHandle:forDID:error:

 @abstract Verifies that a handle is valid for a DID.

 @discussion Resolves the handle to a DID and checks that
 the DID document also claims the handle.

 @param handle The handle to verify.
 @param did The expected DID.
 @param error On failure, contains error details.
 @return YES if the handle is valid for the DID.
 */
- (BOOL)verifyHandle:(NSString *)handle
              forDID:(NSString *)did
               error:(NSError **)error;

/*!
 @method clearCache

 @abstract Clears the identity cache.
 */
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
