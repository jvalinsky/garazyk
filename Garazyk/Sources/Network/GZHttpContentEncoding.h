// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZHttpContentEncoding.h

 @abstract HTTP Content-Encoding negotiation and streaming compression for
           chunked response bodies (repo exports).

 @discussion Negotiates zstd / gzip / identity from Accept-Encoding (Hubble-
 compatible preference for zstd on ties). Wraps HttpResponseBodyChunkProducer
 without changing archive media types. Compressors are single-pull-thread
 objects — one response owns one compressor.

 Set PDS_HTTP_CONTENT_ENCODING=0 to force identity (rollback / debug).
 */

#import <Foundation/Foundation.h>
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for content-encoding negotiate / compress failures. */
extern NSString * const GZHttpContentEncodingErrorDomain;

typedef NS_ENUM(NSInteger, GZHttpContentEncodingErrorCode) {
    GZHttpContentEncodingErrorUnsupported = 1,
    GZHttpContentEncodingErrorInitFailed = 2,
    GZHttpContentEncodingErrorCompressFailed = 3,
    GZHttpContentEncodingErrorFinishFailed = 4,
};

/*! Content codings this stack can apply on export responses. */
typedef NS_ENUM(NSInteger, GZHttpContentEncoding) {
    GZHttpContentEncodingIdentity = 0,
    GZHttpContentEncodingGzip = 1,
    GZHttpContentEncodingZstd = 2,
};

/*!
 @abstract Negotiates an encoding from an Accept-Encoding header value.

 @discussion Highest q among {zstd, gzip, identity} wins; ties prefer zstd.
 Unknown tokens are ignored. Empty / nil / unusable → identity. Honors
 PDS_HTTP_CONTENT_ENCODING=0 as a hard force to identity.
 */
GZHttpContentEncoding GZHttpContentEncodingFromAcceptEncoding(NSString * _Nullable acceptEncoding);

/*! Content-Encoding header value, or nil for identity. */
NSString * _Nullable GZHttpContentEncodingHeaderValue(GZHttpContentEncoding encoding);

/*!
 @abstract Wraps an identity chunk producer with streaming compression.

 @discussion Identity encoding returns `inner` unchanged. Non-identity
 producers never return a zero-length chunk until the compressed stream is
 fully finished (including trailer). Single-threaded pull only.
 */
HttpResponseBodyChunkProducer GZHttpCompressingBodyChunkProducer(
    HttpResponseBodyChunkProducer inner,
    GZHttpContentEncoding encoding);

/*!
 @abstract Negotiate, wrap, set body producer, Content-Encoding, and Vary.

 @discussion Always sets Vary to include Accept and Accept-Encoding. Sets
 Content-Encoding only for non-identity. Uses chunked transfer encoding.
 */
void GZHttpResponseSetExportBodyChunkProducer(
    ATProtoHttpResponse *response,
    HttpResponseBodyChunkProducer producer,
    NSString * _Nullable acceptEncodingHeader);

NS_ASSUME_NONNULL_END
