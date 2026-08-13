// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZJelczStreamplaceBlobFetcher.h

 @abstract Composition-root HTTPS fetcher for Streamplace getVideoBlob (WS15).

 @discussion Implements @c ATProtoCAMirrorFetching by shaping
 @c place.stream.playback.getVideoBlob URLs. Lives in Video/ so MediaCore
 stays free of Streamplace-specific knowledge. Bytes are unverified — the
 mirror resolver re-checks the BLAKE3 CID before put.
 */

#import <Foundation/Foundation.h>
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const GZJelczStreamplaceBlobFetcherErrorDomain;

typedef NS_ENUM(NSInteger, GZJelczStreamplaceBlobFetcherErrorCode) {
    GZJelczStreamplaceBlobFetcherErrorInvalidArgument = 1,
    GZJelczStreamplaceBlobFetcherErrorAllProvidersFailed = 2,
    GZJelczStreamplaceBlobFetcherErrorBlobNotFound = 3,
};

/**
 Fetches MUXL/BDASL candidates via Streamplace @c getVideoBlob.

 Requires @c attributionDID (lexicon @c did= egress accounting). Tracks
 allowlisted counters for the jelcz admin Distribution tab.
 */
@interface GZJelczStreamplaceBlobFetcher : NSObject <ATProtoCAMirrorFetching>

@property (nonatomic, strong, readonly) id<ATProtoCAMirrorHTTPClient> httpClient;
/** DID passed as the getVideoBlob @c did query parameter. */
@property (nonatomic, copy) NSString *attributionDID;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, assign) NSUInteger maxResponseBytes;

@property (atomic, assign, readonly) NSUInteger successCount;
@property (atomic, assign, readonly) NSUInteger blobNotFoundCount;
@property (atomic, assign, readonly) NSUInteger failureCount;
@property (atomic, strong, readonly, nullable) NSDate *lastSuccessAt;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithHTTPClient:(id<ATProtoCAMirrorHTTPClient>)httpClient
                   attributionDID:(NSString *)attributionDID
    NS_DESIGNATED_INITIALIZER;

/**
 Builds
 @c {base}/xrpc/place.stream.playback.getVideoBlob?did=&cid=
 from a provider base URL. Strips a trailing @c .m4s from @c cid if present.
 */
+ (nullable NSURL *)getVideoBlobURLForCID:(ATProtoCID *)cid
                          attributionDID:(NSString *)attributionDID
                         providerBaseURL:(NSString *)providerBaseURL;

/**
 Like @c fetchObjectBytesForCID:providers:error: but sets an HTTP @c Range
 header (e.g. @c bytes=0-31). Used for Streamplace @c EXT-X-BYTERANGE style
 partial reads; the mirror resolver still prefers full-object fetch + verify.
 */
- (nullable NSData *)fetchObjectBytesForCID:(ATProtoCID *)cid
                                  providers:(NSArray<NSString *> *)providers
                                rangeHeader:(nullable NSString *)rangeHeader
                                      error:(NSError **)error;

/**
 Allowlisted posture dictionary for admin snapshots (no tokens/URLs with secrets).
 */
- (NSDictionary *)allowlistedStatsDictionary;

@end

NS_ASSUME_NONNULL_END
