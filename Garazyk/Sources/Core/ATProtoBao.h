// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoBao.h
 @abstract Wire-compatible Bao outboard / slice encode and verify (WS12 Phase 9).
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoBaoErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoBaoErrorCode) {
    ATProtoBaoErrorInvalidArgument = 1,
    ATProtoBaoErrorTruncated = 2,
    ATProtoBaoErrorHashMismatch = 3,
    ATProtoBaoErrorRange = 4,
};

/**
 Bao helpers compatible with the Rust @c bao 0.13 outboard / slice formats.
 */
@interface ATProtoBao : NSObject

/** 32-byte BLAKE3 root hash of @c data (same as @c bao hash / @c blake3::hash). */
+ (NSData *)hashForData:(NSData *)data;

/** Bao outboard encoding (8-byte LE length + parent nodes). */
+ (nullable NSData *)outboardForData:(NSData *)data error:(NSError **)error;

/**
 Extracts a combined Bao slice covering @c [offset, offset+length) from content
 plus an outboard encoding.
 */
+ (nullable NSData *)sliceFromData:(NSData *)data
                          outboard:(NSData *)outboard
                            offset:(NSUInteger)offset
                            length:(NSUInteger)length
                             error:(NSError **)error;

/**
 Verifies a Bao slice against a 32-byte BLAKE3 root and returns the verified
 content bytes for the requested range. Does not require the full object.
 */
+ (nullable NSData *)verifiedContentFromSlice:(NSData *)slice
                                 expectedHash:(NSData *)hash32
                                       offset:(NSUInteger)offset
                                       length:(NSUInteger)length
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
