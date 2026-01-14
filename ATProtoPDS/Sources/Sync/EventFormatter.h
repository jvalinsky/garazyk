/*!
 @file EventFormatter.h

 @abstract Event encoding/decoding for Firehose protocol.

 @discussion Encodes and decodes Firehose events (commits, identity, error)
 using CBOR format for transmission over WebSocket connections.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class FirehoseCommitEvent;
@class FirehoseIdentityEvent;
@class FirehoseErrorEvent;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for event formatter. */
extern NSString * const EventFormatterErrorDomain;

/*! Error code when encoding fails. */
extern NSInteger const EventFormatterErrorCodeEncodingFailed;

/*! Error code when decoding fails. */
extern NSInteger const EventFormatterErrorCodeDecodingFailed;

/*!
 @class EventFormatter

 @abstract Encodes and decodes Firehose events.
 */
@interface EventFormatter : NSObject

/*! Encodes a commit event to CBOR data. */
- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event error:(NSError **)error;

/*! Encodes an identity event to CBOR data. */
- (nullable NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event error:(NSError **)error;

/*! Encodes an error event to CBOR data. */
- (nullable NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event error:(NSError **)error;

/*! Encodes a generic event with kind and payload. */
- (nullable NSData *)encodeEventWithKind:(NSString *)kind payload:(NSDictionary *)payload error:(NSError **)error;

/*! Decodes an event from CBOR data. */
- (nullable id)decodeEventFromData:(NSData *)data error:(NSError **)error;

/*! Encodes any object to CBOR. */
- (nullable NSData *)encodeCBORObject:(id)object error:(NSError **)error;

/*! Decodes CBOR data to an object. */
- (nullable id)decodeCBORData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
