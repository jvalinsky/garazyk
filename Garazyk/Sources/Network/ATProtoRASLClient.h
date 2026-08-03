// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoRASLClient.h

 @abstract RASL retrieval client (https://dasl.ing/rasl.html).

 @discussion Given a parsed `ATProtoRASLURL`, fetches
 `https://<hint>/.well-known/rasl/<cid>` from every hint in parallel, verifies
 the retrieved bytes hash to the requested CID, and returns the first
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

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ATProtoRASLClientErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoRASLClientErrorCode) {
    /** The URL carried no hints, so there is nothing to fetch from. */
    ATProtoRASLClientErrorNoHints = 1,
    /** Every hint failed (network error, non-200 response, or CID mismatch). */
    ATProtoRASLClientErrorAllHintsFailed = 2,
    /**
     The CID uses a hash algorithm this client cannot verify yet. Only
     SHA-256 (base DASL) CIDs are verified today; BLAKE3 (Big DASL)
     verification lands with the Phase 6 streaming verifier. Data is never
     returned unverified, so this fails closed instead of skipping the check.
     */
    ATProtoRASLClientErrorUnsupportedHashAlgorithm = 3,
    /** One hint's own attempt failed (network error, bad status, CID mismatch, or unbuildable URL). Only ever appears nested under `ATProtoRASLHintFailures` on the aggregate error. */
    ATProtoRASLClientErrorHintFailed = 4,
};

/**
 * @abstract Fetches CID-addressed content over RASL, verifying every result.
 */
@interface ATProtoRASLClient : NSObject

/** Shared client instance. */
+ (instancetype)sharedClient;

/**
 Fetches and CID-verifies the content a `rasl://` URL points to.

 @param url A parsed RASL URL.
 @param maxResponseBytes Per-hint response size cap.
 @param timeout Per-hint request timeout, in seconds.
 @param completion Called once, on an arbitrary queue, with the verified
 bytes or an error. Never invoked with non-nil data that failed CID
 verification.
 */
- (void)fetchDataForRASLURL:(ATProtoRASLURL *)url
            maxResponseBytes:(NSUInteger)maxResponseBytes
                      timeout:(NSTimeInterval)timeout
                   completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
