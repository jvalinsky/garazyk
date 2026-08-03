// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file CID+DASL.h

 @abstract Strict DASL CID profile.

 @discussion `CID` itself is deliberately permissive: it accepts CIDv0, five
 multibase prefixes, arbitrary multicodecs and non-canonical varint encodings,
 because the ATProto CID *syntax* interop fixtures require exactly that and
 because legacy blob references carry CIDs that predate the current rules.

 This category adds the opposite: the strict profile from
 https://dasl.ing/cid.html, where a CID is exactly 36 bytes

     0x01  0x55 | 0x71  0x12  0x20  <32-byte digest>

 with no varint tolerance, and its string form is `b` followed by 58 lowercase
 RFC 4648 base32 characters. Byte-exactness is the point: content addressing
 breaks the moment one logical CID has two valid encodings.

 Use the strict profile where content addressing depends on it — CAR block
 CIDs, repository block CIDs, DRISL links in non-record documents. Do not use
 it to validate blob references or user-supplied CID syntax; those keep the
 permissive parser.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

/** Multicodec for raw binary content. */
extern const uint8_t ATProtoDASLCodecRaw;
/** Multicodec for DRISL (dag-cbor) content. */
extern const uint8_t ATProtoDASLCodecDRISL;
/** Multihash code for SHA-256. */
extern const uint8_t ATProtoDASLMultihashSHA256;
/** Multihash code for BLAKE3, used by Big DASL. */
extern const uint8_t ATProtoDASLMultihashBLAKE3;
/** Byte length of every DASL CID. */
extern const NSUInteger ATProtoDASLCIDByteLength;
/** Character length of every DASL CID string, including the `b` prefix. */
extern const NSUInteger ATProtoDASLCIDStringLength;

/**
 Which hash functions the strict profile accepts.
 */
typedef NS_ENUM(NSInteger, ATProtoDASLCIDProfile) {
    /**
     The DASL CID spec as written: SHA-256 only. This is what ATProto peers
     interoperate on and what repository and CAR validation must use.
     */
    ATProtoDASLCIDProfileBase = 0,

    /**
     Big DASL (https://dasl.ing/bdasl.html): additionally accepts BLAKE3-256,
     whose tree structure allows incremental verification of large files.
     BLAKE3 CIDs are not interoperable with ATProto peers — never write one
     into a record or a repository block.
     */
    ATProtoDASLCIDProfileBig = 1
};

/**
 * @abstract Strict DASL parsing and validation for CID.
 */
@interface CID (DASL)

/**
 Parses a DASL CID string under the base profile.

 @param string A 59-character `b`-prefixed lowercase base32 string.
 @return The CID, or nil if it deviates from the spec in any way.
 */
+ (nullable CID *)daslCIDFromString:(NSString *)string;

/**
 Parses a DASL CID string under an explicit profile.

 @param string A 59-character `b`-prefixed lowercase base32 string.
 @param profile Which hash functions to accept.
 @return The CID, or nil if it deviates from the spec in any way.

 @discussion Rejects uppercase, `=` padding, every multibase prefix except
 `b`, and any encoding whose trailing bits are non-zero — all of these decode
 to the right bytes but re-encode to a different string, which would give one
 CID two spellings.
 */
+ (nullable CID *)daslCIDFromString:(NSString *)string
                            profile:(ATProtoDASLCIDProfile)profile;

/**
 Parses DASL CID bytes under the base profile.

 @param data Exactly 36 bytes.
 @return The CID, or nil if it deviates from the spec in any way.
 */
+ (nullable CID *)daslCIDFromBytes:(NSData *)data;

/**
 Parses DASL CID bytes under an explicit profile.

 @param data Exactly 36 bytes.
 @param profile Which hash functions to accept.
 @return The CID, or nil if it deviates from the spec in any way.

 @discussion Byte-exact. This is what rejects CIDv0, dag-pb, SHA-1, digests
 that are not 32 bytes, and the non-canonical multi-byte varint spellings of
 the version and codec (`0x81 0x00` for `0x01`) that the permissive parser
 tolerates.
 */
+ (nullable CID *)daslCIDFromBytes:(NSData *)data
                           profile:(ATProtoDASLCIDProfile)profile;

/**
 Whether this CID is expressible in the base DASL profile.
 */
@property (readonly, nonatomic, getter=isDASLConformant) BOOL daslConformant;

/**
 Whether this CID is expressible under the given profile.

 @param profile Which hash functions to accept.
 @return YES when the CID is conformant.
 */
- (BOOL)isDASLConformantForProfile:(ATProtoDASLCIDProfile)profile;

@end

NS_ASSUME_NONNULL_END
