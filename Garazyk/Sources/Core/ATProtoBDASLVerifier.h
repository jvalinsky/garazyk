// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoBDASLVerifier.h

 @abstract Streaming BLAKE3 verification primitives for Big DASL content.

 @discussion This class verifies a BLAKE3-addressed stream with a caller-
 supplied sidecar containing one BLAKE3 digest per 1 KiB chunk. It also exposes
 the byte-range to chunk-range mapping described by BDASL. The sidecar is
 intentionally explicit: BDASL requires hash-tree metadata for trustless
 partial verification, and this slice does not invent a wire format for that
 metadata. The verifier is therefore a reusable integrity primitive, not a
 complete HTTP client or BDASL sidecar transport.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoBDASLVerifierErrorDomain;

/** Errors returned by the bounded BDASL verifier. */
typedef NS_ENUM(NSInteger, ATProtoBDASLVerifierErrorCode) {
    ATProtoBDASLVerifierErrorInvalidCID = 1,
    ATProtoBDASLVerifierErrorInvalidSidecar = 2,
    ATProtoBDASLVerifierErrorTooMuchData = 3,
    ATProtoBDASLVerifierErrorChunkMismatch = 4,
    ATProtoBDASLVerifierErrorIncomplete = 5,
    ATProtoBDASLVerifierErrorRootMismatch = 6,
    ATProtoBDASLVerifierErrorInvalidRange = 7,
};

/** BDASL's verification chunk size. */
FOUNDATION_EXPORT const NSUInteger ATProtoBDASLChunkSize;

/**
 Verifies a BLAKE3 ATProtoCID using per-chunk digests supplied by a sidecar.
 */
@interface ATProtoBDASLVerifier : NSObject

/** The expected BLAKE3 ATProtoCID. */
@property (nonatomic, strong, readonly) ATProtoCID *cid;
/** Total payload length expected by the sidecar. */
@property (nonatomic, assign, readonly) NSUInteger totalLength;
/** Number of payload bytes accepted so far. */
@property (nonatomic, assign, readonly) NSUInteger bytesReceived;
/** Number of chunks verified so far. */
@property (nonatomic, assign, readonly) NSUInteger verifiedChunkCount;
/** YES after finalize succeeds. */
@property (nonatomic, assign, readonly, getter=isVerified) BOOL verified;

/**
 Initializes a verifier.

 @param cid A Big DASL ATProtoCID with the BLAKE3 multihash (0x1e).
 @param chunkDigests An array of 32-byte BLAKE3 digests, one per 1 KiB
 chunk. The final digest covers the final short chunk when the payload length
 is not a multiple of 1 KiB; an empty payload has one empty chunk.
 @param totalLength The exact payload length described by the sidecar.
 */
- (nullable instancetype)initWithCID:(ATProtoCID *)cid
                        chunkDigests:(NSArray<NSData *> *)chunkDigests
                         totalLength:(NSUInteger)totalLength
                               error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/** Appends any-sized input; complete 1 KiB chunks are checked immediately. */
- (BOOL)appendData:(NSData *)data error:(NSError **)error;

/** Completes verification and checks the root BLAKE3 digest in the ATProtoCID. */
- (BOOL)finalizeWithError:(NSError **)error;

/**
 Maps an inclusive HTTP byte range to the inclusive chunk indices it touches.
 Missing start/end values mean the beginning/end of the payload. An end beyond
 the payload is clamped, matching HTTP range semantics. This helper expects
 already-normalized inclusive bounds: `hasStart:NO, hasEnd:YES` means bytes
 0 through `end`, not the HTTP `bytes=-N` suffix form.
 */
+ (BOOL)chunkRangeForStart:(NSUInteger)start
                  hasStart:(BOOL)hasStart
                       end:(NSUInteger)end
                    hasEnd:(BOOL)hasEnd
               totalLength:(NSUInteger)totalLength
                firstChunk:(NSUInteger *)firstChunk
                 lastChunk:(NSUInteger *)lastChunk
                     error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
