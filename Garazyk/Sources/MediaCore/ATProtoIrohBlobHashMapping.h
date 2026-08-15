// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoIrohBlobHashMapping.h

 @abstract Map Garazyk CA/VOD BLAKE3 CIDs to 32-byte iroh-blobs fetch roots (WS16
 Track A / phase-35 S2).

 @discussion Garazyk stores Big-DASL BLAKE3 CIDs (`bafkr…`) whose multihash
 carries a 32-byte digest. The iroh-blobs protocol addresses blobs by BLAKE3
 content root. Mirror verification compares that digest to the Bao content root
 of the object bytes (`ATProtoCAMirrorResolver`). Sidecar fetch must use the
 same 32-byte value the resolver expects after transfer.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ATProtoIrohBlobHashMappingErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoIrohBlobHashMappingErrorCode) {
    ATProtoIrohBlobHashMappingErrorInvalidCID = 1,
    ATProtoIrohBlobHashMappingErrorUnsupportedHash = 2,
};

@interface ATProtoIrohBlobHashMapping : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/** Extract 32-byte BLAKE3 digest from a Garazyk CA/VOD CID (iroh-blobs fetch key). */
+ (nullable NSData *)irohBlobsHashFromGarazykCAVODCID:(ATProtoCID *)cid
                                                error:(NSError **)error;

/** Bao content root for object bytes (mirror-resolver verify input). */
+ (nullable NSData *)baoRootHashForObjectData:(NSData *)data;

/** Whether CID digest matches Bao root of @c data. */
+ (BOOL)garazykCAVODCID:(ATProtoCID *)cid matchesObjectData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
