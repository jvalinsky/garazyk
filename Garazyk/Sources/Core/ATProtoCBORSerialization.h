// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ATProtoCBORSerialization
 
 @abstract CBOR (Conecis Binary Object Representation) serializer.
 
 @discussion Handles encoding and decoding of ATProto data structures to/from 
 DAG-CBOR format. Ensures canonical encoding for consistent hashing.
 */
@interface ATProtoCBORSerialization : NSObject

/*!
 @method encodeDataWithJSONObject:error:
 
 @abstract Encodes a JSON-compatible object to DAG-CBOR.
 
 @param obj The object to encode (NSDictionary, NSArray, etc.).
 @param error On return, contains an error if encoding failed.
 @return The CBOR-encoded data.
 */
+ (NSData *)encodeDataWithJSONObject:(id)obj error:(NSError **)error;

/*!
 @method JSONObjectWithData:error:
 
 @abstract Decodes DAG-CBOR data into a JSON-compatible object.
 
 @param data The CBOR data to decode.
 @param error On return, contains an error if decoding failed.
 @return The decoded object, or nil if decoding failed.
 */
+ (id)JSONObjectWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
