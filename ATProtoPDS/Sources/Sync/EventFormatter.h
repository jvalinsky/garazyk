/*!
 @file EventFormatter.h

 @abstract Event encoding/decoding for Firehose protocol.

 @discussion Encodes and decodes Firehose events (commits, identity, error)
 using CBOR format for transmission over WebSocket connections.
 Supports the XRPC streaming event protocol with EventHeader + message body format.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class FirehoseCommitEvent;
@class FirehoseIdentityEvent;
@class FirehoseAccountEvent;
@class FirehoseInfoEvent;
@class FirehoseErrorEvent;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for event formatter. */
extern NSString * const EventFormatterErrorDomain;

/*! Error code when encoding fails. */
extern NSInteger const EventFormatterErrorCodeEncodingFailed;

/*! Error code when decoding fails. */
extern NSInteger const EventFormatterErrorCodeDecodingFailed;

/*! XRPC stream operation kinds. */
typedef NS_ENUM(NSInteger, XRPCStreamOpKind) {
    XRPCStreamOpKindErrorFrame = -1,
    XRPCStreamOpKindMessage = 1
};

/*!
 @class EventFormatter

 @abstract Encodes and decodes Firehose events using XRPC streaming protocol.

 @discussion Events are encoded with an EventHeader followed by the message body:
 1. EventHeader (CBOR): { "op": <int>, "t": <string> }
 2. Message body (CBOR): Event-specific data

 Supported message types:
 - "#commit": Repository commit event
 - "#identity": Identity update event
 - "#account": Account status event
 - "#info": Informational message
 */
@interface EventFormatter : NSObject

/*! Encodes a commit event with proper XRPC streaming header. */
- (nullable NSData *)encodeCommitEvent:(FirehoseCommitEvent *)event
                                 error:(NSError **)error;

/*! Encodes an identity event with proper XRPC streaming header. */
- (nullable NSData *)encodeIdentityEvent:(FirehoseIdentityEvent *)event
                                    error:(NSError **)error;

/*! Encodes an account event with proper XRPC streaming header. */
- (nullable NSData *)encodeAccountEvent:(FirehoseAccountEvent *)event
                                   error:(NSError **)error;

/*! Encodes an info event with proper XRPC streaming header. */
- (nullable NSData *)encodeInfoEvent:(FirehoseInfoEvent *)event
                               error:(NSError **)error;

/*! Encodes an error frame with proper XRPC streaming header. */
- (nullable NSData *)encodeErrorEvent:(FirehoseErrorEvent *)event
                                error:(NSError **)error;

/*! Decodes an event from CBOR data, returning header and body separately. */
- (nullable NSDictionary *)decodeEventFromData:(NSData *)data
                                           op:(nullable NSInteger *)op
                                      msgType:(NSString * _Nullable * _Nullable)msgType
                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
