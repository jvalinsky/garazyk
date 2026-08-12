// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoEventFormatter.h

 @abstract Event encoding/decoding for ATProtoFirehose protocol.

 @discussion Encodes and decodes ATProtoFirehose events (commits, identity, error)
 using CBOR format for transmission over WebSocket connections.
 Supports the XRPC streaming event protocol with EventHeader + message body format.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class ATProtoFirehoseCommitEvent;
@class ATProtoFirehoseSyncEvent;
@class ATProtoFirehoseIdentityEvent;
@class ATProtoFirehoseAccountEvent;
@class ATProtoFirehoseInfoEvent;
@class ATProtoFirehoseErrorEvent;

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for event formatter. */
extern NSString * const EventFormatterErrorDomain;

/*! Error code when encoding fails. */
extern NSInteger const EventFormatterErrorCodeEncodingFailed;

/*! Error code when decoding fails. */
extern NSInteger const EventFormatterErrorCodeDecodingFailed;

/*! XRPC stream operation kinds. */
/**
 * @abstract Defines XRPCStreamOpKind values exposed by this API.
 */
typedef NS_ENUM(NSInteger, XRPCStreamOpKind) {
    XRPCStreamOpKindErrorFrame = -1,
    XRPCStreamOpKindMessage = 1
};

/*!
 @class ATProtoEventFormatter

 @abstract Encodes and decodes ATProtoFirehose events using XRPC streaming protocol.

 @discussion Events are encoded with an EventHeader followed by the message body:
 1. EventHeader (CBOR): { "op": <int>, "t": <string> }
 2. Message body (CBOR): Event-specific data

 Supported message types:
 - "#commit": Repository commit event
 - "#sync": Repository sync event
 - "#identity": Identity update event
 - "#account": Account status event
 - "#info": Informational message
 */
/**
 * @abstract Declares the ATProtoEventFormatter public API.
 */
@interface ATProtoEventFormatter : NSObject

/*! Encodes a commit event with proper XRPC streaming header. */
- (nullable NSData *)encodeCommitEvent:(ATProtoFirehoseCommitEvent *)event
                                 error:(NSError **)error;

/*! Encodes a sync event with proper XRPC streaming header. */
- (nullable NSData *)encodeSyncEvent:(ATProtoFirehoseSyncEvent *)event
                                error:(NSError **)error;

/*! Encodes an identity event with proper XRPC streaming header. */
- (nullable NSData *)encodeIdentityEvent:(ATProtoFirehoseIdentityEvent *)event
                                    error:(NSError **)error;

/*! Encodes an account event with proper XRPC streaming header. */
- (nullable NSData *)encodeAccountEvent:(ATProtoFirehoseAccountEvent *)event
                                   error:(NSError **)error;

/*! Encodes an info event with proper XRPC streaming header. */
- (nullable NSData *)encodeInfoEvent:(ATProtoFirehoseInfoEvent *)event
                               error:(NSError **)error;

/*! Encodes an error frame with proper XRPC streaming header. */
- (nullable NSData *)encodeErrorEvent:(ATProtoFirehoseErrorEvent *)event
                                error:(NSError **)error;

/*! Encodes a stream event with a given type and payload dictionary. */
- (nullable NSData *)encodeStreamEventWithType:(NSString *)msgType
                                       payload:(NSDictionary *)payload
                                         error:(NSError **)error;

/*! Decodes an event from CBOR data, returning header and body separately. */
- (nullable NSDictionary *)decodeEventFromData:(NSData *)data
                                           op:(nullable NSInteger *)op
                                      msgType:(NSString * _Nullable * _Nullable)msgType
                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
