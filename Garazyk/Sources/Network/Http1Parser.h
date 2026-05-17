// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file Http1Parser.h

 @abstract Parses HTTP/1.x request bytes into structured parse state and message components.

 @discussion Defines parser interfaces and contracts for HTTP/1.x line/header/body parsing. Exposes deterministic parse outcomes used by higher-level session and dispatch layers, without owning socket I/O or route execution.
 */

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Parse states for an incremental HTTP/1.x request parser.
 */
typedef NS_ENUM(NSInteger, Http1ParserState) {
    /** Parser is reading the request line and header block. */
    Http1ParserStateReadingHeaders,
    /** Parser is reading a fixed-length message body. */
    Http1ParserStateReadingBody,
    /** Parser is reading a chunked transfer-encoded body. */
    Http1ParserStateReadingChunkedBody,
    /** Parser has completed one request. */
    Http1ParserStateComplete,
    /** Parser encountered a protocol or size-limit error. */
    Http1ParserStateError
};

/**
 * @abstract Structured HTTP parser failure suitable for response generation.
 */
@interface Http1ParserError : NSObject
/** HTTP status code to return to the client. */
@property (nonatomic, readonly) NSUInteger statusCode;
/** Stable application error code. */
@property (nonatomic, readonly) NSString *errorCode;
/** Human-readable error message. */
@property (nonatomic, readonly) NSString *message;

/**
 * @abstract Initializes a parser error.
 */
- (instancetype)initWithStatusCode:(NSUInteger)statusCode
                         errorCode:(NSString *)errorCode
                           message:(NSString *)message;
@end

/**
 * @abstract Incremental parser for one HTTP/1.x request.
 */
@interface Http1Parser : NSObject

/** Current parser state. */
@property (nonatomic, readonly) Http1ParserState state;
/** Maximum accepted header block size in bytes. Defaults to 16 KB. */
@property (nonatomic, assign) NSUInteger maxHeaderBytes;  // default 16KB
/** Maximum accepted request body size in bytes. Defaults to 50 MB. */
@property (nonatomic, assign) NSUInteger maxBodyBytes;    // default 50MB

/** Client IP address copied into the completed HttpRequest. */
@property (nonatomic, copy, nullable) NSString *remoteAddress;

/**
 * @abstract Feeds raw bytes into the parser.
 * @return YES when a complete request or parse error is available.
 */
- (BOOL)feedData:(NSData *)data;

/** Completed request after feedData: returns YES, or nil when parsing failed. */
- (nullable HttpRequest *)completedRequest;
/** Parser error after feedData: returns YES, or nil when a request completed successfully. */
- (nullable Http1ParserError *)parseError;

/** Bytes not consumed by the completed request, used for HTTP pipelining. */
- (NSData *)unconsumedData;

/** Resets parser state for the next request on the same connection. */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
