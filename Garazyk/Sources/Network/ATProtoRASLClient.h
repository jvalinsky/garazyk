// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRASLClient.h

 @abstract RASL retrieval client (https://dasl.ing/rasl.html).

 @discussion Given a parsed `ATProtoRASLURL`, fetches
 `https://<hint>/.well-known/rasl/<cid>` from every hint in parallel, verifies
 the retrieved bytes hash to the requested ATProtoCID, and returns the first
 verified success — matching the spec's "run them all in parallel and abort
 with the first success response." True network-level cancellation of the
 losing requests is not available: the underlying `ATProtoSafeHTTPClient`
 does not expose a cancel handle, so "abort" here means later results are
 ignored once a winner is chosen, not that in-flight sockets are torn down.

 Every fetch goes through `ATProtoSafeHTTPClient`, which supplies pinned-
 egress SSRF protection and per-hop redirect revalidation (ADR 0016) — this
 class does no address resolution or validation of its own.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoRASLURL;
@class ATProtoSafeHTTPClientOptions;

NS_ASSUME_NONNULL_BEGIN

/** The synchronous HTTP surface required by RASL and BDASL retrieval. */
@protocol ATProtoRASLHTTPFetching <NSObject>
- (nullable NSData *)sendSynchronousRequest:(NSURLRequest *)request
                                    options:(nullable ATProtoSafeHTTPClientOptions *)options
                                    response:(NSHTTPURLResponse * _Nullable * _Nullable)response
                                      error:(NSError * _Nullable * _Nullable)error;
@end

extern NSErrorDomain const ATProtoRASLClientErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoRASLClientErrorCode) {
    /** The URL carried no hints, so there is nothing to fetch from. */
    ATProtoRASLClientErrorNoHints = 1,
    /** Every hint failed (network error, non-200 response, or ATProtoCID mismatch). */
    ATProtoRASLClientErrorAllHintsFailed = 2,
    /**
     The plain RASL fetch method uses a hash algorithm this method cannot
     verify. It supports SHA-256 (base DASL); BLAKE3 retrieval must use the
     BDASL sidecar/range method below. Data is never returned unverified.
     */
    ATProtoRASLClientErrorUnsupportedHashAlgorithm = 3,
    /** One hint's own attempt failed (network error, bad status, ATProtoCID mismatch, or unbuildable URL). Only ever appears nested under `ATProtoRASLHintFailures` on the aggregate error. */
    ATProtoRASLClientErrorHintFailed = 4,
    /** The caller-supplied BDASL sidecar is invalid or cannot be used. */
    ATProtoRASLClientErrorInvalidBDASLSidecar = 5,
    /** Every requested BDASL range failed transport or chunk verification. */
    ATProtoRASLClientErrorBDASLRangeFailed = 6,
};

/**
 * @abstract Fetches ATProtoCID-addressed content over RASL, verifying every result.
 */
@interface ATProtoRASLClient : NSObject

/** Shared client instance. */
+ (instancetype)sharedClient;

/** Creates a client with an injectable synchronous HTTP boundary. */
- (instancetype)initWithHTTPClient:(id<ATProtoRASLHTTPFetching>)httpClient NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
 Fetches and ATProtoCID-verifies the content a `rasl://` URL points to.

 @param url A parsed RASL URL.
 @param maxResponseBytes Per-hint response size cap.
 @param timeout Per-hint request timeout, in seconds.
 @param completion Called once, on an arbitrary queue, with the verified
 bytes or an error. Never invoked with non-nil data that failed ATProtoCID
 verification.
 */
- (void)fetchDataForRASLURL:(ATProtoRASLURL *)url
            maxResponseBytes:(NSUInteger)maxResponseBytes
                      timeout:(NSTimeInterval)timeout
                   completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion;

/**
 Fetches every 1 KiB BDASL chunk with an exact single-byte HTTP range,
 verifies each response against the caller-supplied sidecar, and verifies the
 assembled payload against the URL's BLAKE3 CID before returning it.

 The sidecar is not fetched from the server. A response must be HTTP 206 and
 have exactly the requested body length. Response metadata is not used to
 choose ranges or verification inputs.
 */
- (void)fetchBDASLDataForRASLURL:(ATProtoRASLURL *)url
                    chunkDigests:(NSArray<NSData *> *)chunkDigests
                     totalLength:(NSUInteger)totalLength
                 maxResponseBytes:(NSUInteger)maxResponseBytes
                           timeout:(NSTimeInterval)timeout
                        completion:(void (^)(NSData * _Nullable data,
                                             NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
