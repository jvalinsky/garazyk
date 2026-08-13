// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoCAMirrorResolver.h

 @abstract Local-first CA object resolution with injectable mirror fetch (WS12 Phase 10).

 @discussion MediaCore does not link Network libraries for outbound fetch. The
 composition root injects an @c ATProtoCAMirrorFetching implementation — typically
 @c ATProtoCAMirrorHTTPSFetcher wrapping a synchronous HTTP client. Provider
 hints come from Phase 7 origin metadata; verification uses the BLAKE3 CID and
 optional Phase 9 Bao slices.
 */

#import <Foundation/Foundation.h>

@class ATProtoCAObjectStore;
@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoCAMirrorResolverErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoCAMirrorResolverErrorCode) {
    ATProtoCAMirrorResolverErrorInvalidArgument = 1,
    ATProtoCAMirrorResolverErrorNotFound = 2,
    ATProtoCAMirrorResolverErrorVerificationFailed = 3,
    ATProtoCAMirrorResolverErrorFetchFailed = 4,
    ATProtoCAMirrorResolverErrorDisabled = 5,
};

/**
 Fetches unverified candidate bytes from mirror provider base URLs.

 Implementations may live in MediaCore (@c ATProtoCAMirrorHTTPSFetcher) with an
 injected HTTP client, or as a custom adapter. Returned bytes are always
 re-verified by @c ATProtoCAMirrorResolver before they may enter the local
 object store.
 */
@protocol ATProtoCAMirrorFetching <NSObject>
/**
 Fetches a complete object candidate for @c cid from @c providers.

 @param providers Absolute HTTPS base URLs (e.g. origin @c watchBaseUrl values).
 @return Candidate object bytes, or nil on failure.
 */
- (nullable NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                                  providers:(NSArray<NSString *> *)providers
                                      error:(NSError **)error;

@optional
/**
 Fetches a Bao slice covering @c [offset, offset+length) when the mirror
 supports it. If unimplemented or nil, the resolver falls back to a full-object
 fetch then local range.
 */
- (nullable NSData *)fetchBaoSliceForCID:(ATProtoCID *)cid
                                rootHash:(NSData *)rootHash
                               providers:(NSArray<NSString *> *)providers
                                  offset:(NSUInteger)offset
                                  length:(NSUInteger)length
                                   error:(NSError **)error;
@end

/**
 Resolves CA media bytes: local store first, then optional mirror fetch + verify.
 */
@interface ATProtoCAMirrorResolver : NSObject

@property (nonatomic, strong, readonly) ATProtoCAObjectStore *objectStore;
@property (nonatomic, strong, readonly, nullable) id<ATProtoCAMirrorFetching> fetcher;
/** When NO (default), mirrors are never contacted — Phase 5 local-only behavior. */
@property (nonatomic, assign, getter=isMirrorFetchEnabled) BOOL mirrorFetchEnabled;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithObjectStore:(ATProtoCAObjectStore *)objectStore
                            fetcher:(nullable id<ATProtoCAMirrorFetching>)fetcher
    NS_DESIGNATED_INITIALIZER;

/**
 Returns object bytes for @c cid.

 Local hit never calls the fetcher. On miss with mirrors enabled, fetches,
 verifies the CID digest (BLAKE3 or SHA-256) before @c put, and returns the
 verified bytes.
 */
- (nullable NSData *)dataForCID:(ATProtoCID *)cid
                      providers:(nullable NSArray<NSString *> *)providers
                          error:(NSError **)error;

/**
 Returns a byte range. Prefer local @c get_range. On miss, may use an optional
 Bao slice fetch (Phase 9) or a full-object mirror fetch then local range.
 */
- (nullable NSData *)dataForCID:(ATProtoCID *)cid
                         offset:(NSUInteger)offset
                         length:(NSUInteger)length
                      providers:(nullable NSArray<NSString *> *)providers
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
