/*!
 @file DID.h

 @abstract Decentralized Identifier (DID) resolution and document handling.

 @discussion Implements DID resolution for ATProto identity, supporting
 did:plc and did:web methods. Provides caching with configurable TTLs,
 batch resolution, and DID document parsing for service endpoints.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for DID operations. */
extern NSErrorDomain const DIDErrorDomain;

/*!
 @enum DIDErrorCode

 @abstract Error codes for DID resolution failures.

 @constant DIDErrorInvalidIdentifier Malformed DID string.
 @constant DIDErrorResolutionFailed Resolution request failed.
 @constant DIDErrorNetworkError Network connectivity issue.
 @constant DIDErrorInvalidDocument Malformed DID document.
 */
typedef NS_ENUM(NSInteger, DIDErrorCode) {
    DIDErrorInvalidIdentifier = 1,
    DIDErrorResolutionFailed = 2,
    DIDErrorNetworkError = 3,
    DIDErrorInvalidDocument = 4
};

/*!
 @enum DIDCacheStatus

 @abstract Freshness status for cached DID documents.

 @constant DIDCacheStatusFresh Document is within stale TTL.
 @constant DIDCacheStatusStale Document is stale but usable.
 @constant DIDCacheStatusExpired Document has exceeded max TTL.
 */
typedef NS_ENUM(NSUInteger, DIDCacheStatus) {
    DIDCacheStatusFresh,
    DIDCacheStatusStale,
    DIDCacheStatusExpired,
};

/*!
 @class DIDDocument

 @abstract Parsed DID document with service endpoints.

 @discussion Represents a resolved DID document containing identity
 information, service endpoints, and verification methods.
 */
@interface DIDDocument : NSObject <NSSecureCoding>

/*! The full JSON dictionary from resolution. */
@property (readonly, nonatomic, strong) NSDictionary *jsonDictionary;

/*! The DID this document describes. */
@property (readonly, nonatomic, strong) NSString *id;

/*! Alternative identifiers (handles) for this DID. */
@property (readonly, nonatomic, strong, nullable) NSArray<NSString *> *alsoKnownAs;

/*! Service endpoints dictionary. */
@property (readonly, nonatomic, strong, nullable) NSDictionary *service;

+ (nullable instancetype)documentWithJSON:(NSDictionary *)json error:(NSError **)error;

@end

/*!
 @class DIDResolver

 @abstract Resolves DIDs to their documents via network requests.

 @discussion Supports did:plc and did:web methods with configurable
 caching. Provides both async and sync resolution APIs.
 */
@interface DIDResolver : NSObject

@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableDictionary *cacheTimestamps; /*! Exposed for testing. */
@property (nonatomic, assign) NSTimeInterval staleTTL; /*! Exposed for testing. */
@property (nonatomic, assign) NSTimeInterval maxTTL; /*! Exposed for testing. */

/*!
 @method resolveDID:completion:
 @abstract Resolve a DID to its document.
 @param did The DID to resolve.
 @param completion Completion block with document or error.
 */
- (void)resolveDID:(NSString *)did completion:(void (^)(NSDictionary *document, NSError *error))completion;

/*!
 @method resolveMultipleDIDs:completion:
 @abstract Batch resolution for multiple DIDs.
 @param dids Array of DIDs to resolve.
 @param completion Completion block with results dictionary containing both successful resolutions and errors.
 */
- (void)resolveMultipleDIDs:(NSArray<NSString *> *)dids completion:(void (^)(NSDictionary<NSString *, id> *results, NSError *error))completion;

/*!
 @method resolveDIDSync:error:
 @abstract Synchronous resolution (for testing).
 @param did The DID to resolve.
 @param error On return, contains an error if resolution failed.
 @return The resolved DID document.
 */
- (nullable DIDDocument *)resolveDIDSync:(NSString *)did error:(NSError **)error;

- (nullable NSDictionary *)resolveAtprotoDataForDID:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END