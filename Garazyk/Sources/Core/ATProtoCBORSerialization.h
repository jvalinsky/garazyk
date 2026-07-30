// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoCBORSerialization

 @abstract CBOR serializer with content-addressed routing flag.

 @discussion §S19 lifts §3.4 from ADR-recorded to implemented: per-instance
 routing flag `_isContentAddressed` directs content-addressed callers
 (repository records, MST/CAR blocks, profile records, sync ops, anything
 with a CID) through `[ATProtoDagCBOR decodeData:]` / `[ATProtoDagCBOR
 decodeDataAsJSON:]`, while CTAP2/generic-CBOR callers (lexicon schemas and
 similar non-CID'd payloads) keep the plain `[CBORDecoder decode:]` /
 `[CBOREncoder encode:]` path.

 The flag is part of the immutable state set at construction and has no
 setter: a shared or cached instance must not have its decode strictness
 flipped by one caller out from under another.

 Identity for the strict path: `[ATProtoDagCBOR decodeDataAsJSON:error:]`
 (see `AppViewBackfillWorker.m:422`). The wrapped `[CBORDecoder decode:]`
 at `ATProtoCBORSerialization.m:39` is the only `[CBORDecoder decode:]`
 call that survives this refactor; every other production caller routes
 through `[ATProtoDagCBOR decodeData:...]` (gate check 1 of §S19).
 */
@interface ATProtoCBORSerialization : NSObject

@property (nonatomic, readonly) BOOL isContentAddressed;

/*!
 @brief Canonical initializer. The flag is immutable for the lifetime of the
 instance.

 @param contentAddressed Pass YES for repository records, MST/CAR blocks,
 profile records, sync ops, and any data that has a CID or is hashed for
 content addressing. Pass NO for lexicon schemas and other payloads that
 don't participate in content addressing.
 */
- (nullable instancetype)initWithContentAddressed:(BOOL)contentAddressed;

/*!
 @brief Encodes a JSON-compatible object to DAG-CBOR or generic CBOR.
 @discussion Routes through `[CBOREncoder encode:]` regardless of the flag;
 canonical-form alignment for content-addressed outputs is the responsibility
 of the encoder, not the wrapper.
 */
- (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error;

/*!
 @brief Decodes CBOR data into a JSON-compatible object.
 @discussion When `isContentAddressed` is YES, delegates to
 `[ATProtoDagCBOR decodeDataAsJSON:error:]` -- the strict DAG-CBOR path.
 Otherwise uses `[CBORDecoder decode:]` -- the legacy / CTAP2 path.
 */
- (id)JSONObjectWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
