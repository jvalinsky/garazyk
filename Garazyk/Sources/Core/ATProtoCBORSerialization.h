// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoCBORSerialization

 @abstract CBOR serializer with content-addressed routing flag.

 @discussion §S19 lifts §3.4 from ADR-recorded to implemented: per-instance
 routing flag `_isContentAddressed` directs content-addressed callers
 (repository records, ATProtoMST/CAR blocks, profile records, sync ops, anything
 with a ATProtoCID) through `[ATProtoDagCBOR decodeData:]` / `[ATProtoDagCBOR
 decodeDataAsJSON:]`, while CTAP2/generic-CBOR callers (lexicon schemas and
 similar non-ATProtoCID'd payloads) keep the plain `[ATProtoCBORDecoder decode:]` /
 `[ATProtoCBOREncoder encode:]` path.

 The flag is part of the immutable state set at construction and has no
 setter: a shared or cached instance must not have its decode strictness
 flipped by one caller out from under another.

 Identity for the strict path: `[ATProtoDagCBOR decodeDataAsJSON:error:]`
 (see `GZAppViewBackfillWorker.m:422`). The wrapped `[ATProtoCBORDecoder decode:]`
 at `ATProtoCBORSerialization.m:39` is the only `[ATProtoCBORDecoder decode:]`
 call that survives this refactor; every other production caller routes
 through `[ATProtoDagCBOR decodeData:...]` (gate check 1 of §S19).
 */
@interface ATProtoCBORSerialization : NSObject

@property (nonatomic, readonly) BOOL isContentAddressed;

/*!
 @brief Canonical initializer. The flag is immutable for the lifetime of the
 instance.

 @param contentAddressed Pass YES for repository records, ATProtoMST/CAR blocks,
 profile records, sync ops, and any data that has a ATProtoCID or is hashed for
 content addressing. Pass NO for lexicon schemas and other payloads that
 don't participate in content addressing.
 */
- (nullable instancetype)initWithContentAddressed:(BOOL)contentAddressed;

/*!
 @brief Encodes a JSON-compatible object to DAG-CBOR or generic CBOR.
 @discussion Routes through `[ATProtoCBOREncoder encode:]` regardless of the flag;
 canonical-form alignment for content-addressed outputs is the responsibility
 of the encoder, not the wrapper.
 */
- (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error;

/*!
 @brief Decodes CBOR data into a JSON-compatible object.
 @discussion When `isContentAddressed` is YES, delegates to
 `[ATProtoDagCBOR decodeDataAsJSON:error:]` -- the strict DAG-CBOR path.
 Otherwise uses `[ATProtoCBORDecoder decode:]` -- the legacy / CTAP2 path.
 */
- (id)JSONObjectWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
