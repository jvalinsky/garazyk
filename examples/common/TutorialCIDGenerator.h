/*!
 @file TutorialCIDGenerator.h

 @abstract CIDv1 generation with SHA-256 multihash for tutorial examples.

 @discussion Generates Content Identifiers (CIDs) using the proper CIDv1 format:
   <varint version><varint codec><varint multihash-code><varint digest-size><digest>

 For DAG-CBOR + SHA-256:
   - Version: 1 (0x01)
   - Codec: 0x71 (dag-cbor)
   - Multihash code: 0x12 (sha2-256)
   - Digest size: 32 (0x20)
   - Digest: 32 bytes of SHA-256 hash

 The final CID is base32-lower encoded (bafyrei... prefix).

 This is the educational version of the production CID class in
 Garazyk/Sources/Core/CID.h.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TutorialCIDGenerator : NSObject

/*!
 @method generateCIDForData:

 @abstract Generates a CIDv1 (dag-cbor + sha2-256) for the given data.

 @discussion Note: In production, the data should be DAG-CBOR encoded before
 hashing. This tutorial hashes the raw data for simplicity. The resulting CID
 will NOT match a production PDS CID for the same content.

 @param data The data to generate a CID for.
 @return The CIDv1 string (base32-lower encoded, e.g., "bafyrei...").
 */
+ (NSString *)generateCIDForData:(NSData *)data;

/*!
 @method generateCIDForJSON:

 @abstract Generates a CIDv1 for a JSON dictionary.

 @discussion The JSON is serialized with sorted keys before hashing.
 In production, DAG-CBOR encoding is used instead of JSON.

 @param json The JSON dictionary to generate a CID for.
 @return The CIDv1 string.
 */
+ (NSString *)generateCIDForJSON:(NSDictionary *)json;

@end

NS_ASSUME_NONNULL_END
