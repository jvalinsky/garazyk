// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  PDSSpaceLtHash.h
//  AT Protocol Permissioned Data LtHash commitment.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceLtHashErrorDomain;

typedef NS_ENUM(NSInteger, PDSSpaceLtHashError) {
  PDSSpaceLtHashErrorInvalidState = 1,
};

/** 2048-byte, 1024-lane LtHash state used by a permissioned repository. */
@interface PDSSpaceLtHash : NSObject

@property(nonatomic, readonly, copy) NSData *state;

- (instancetype)init;
- (nullable instancetype)initWithState:(NSData *)state error:(NSError **)error;

/** Adds the BLAKE3-XOF expansion of a `{collection}/{rkey}/{cid}` element. */
- (void)addElement:(NSString *)element;

/** Removes the BLAKE3-XOF expansion of a `{collection}/{rkey}/{cid}` element. */
- (void)removeElement:(NSString *)element;

/** SHA-256 digest of the complete 2048-byte little-endian state. */
- (NSData *)digest;

@end

NS_ASSUME_NONNULL_END
