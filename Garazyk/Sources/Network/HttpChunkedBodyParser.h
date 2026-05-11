// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class HttpChunkedBodyParser

 @abstract Parses HTTP/1.1 chunked transfer encoding per RFC 9112 Section 7.1.

 @discussion Handles incremental parsing of chunked message bodies:
 - chunk = chunk-size [ chunk-ext ] CRLF chunk-data CRLF
 - chunk-size = 1*HEXDIG
 - last-chunk = 1*("0") [ chunk-ext ] CRLF
 - trailer = *( header-field CRLF )

 Chunk extensions and trailers are ignored.
 */
@interface HttpChunkedBodyParser : NSObject

/*!
 @method init

 @abstract Initialize parser with maximum body size.

 @return An initialized parser.
 */
- (instancetype)init;

/*!
 @method initWithMaxSize:

 @abstract Initialize parser with maximum body size limit.

 @param maxSize Maximum allowed body size in bytes (0 = unlimited).

 @return An initialized parser.
 */
- (instancetype)initWithMaxSize:(NSUInteger)maxSize;

/*!
 @method appendData:error:

 @abstract Append chunk data to the parser.

 @param data Raw bytes from the HTTP body.

 @param error On return, contains error if parsing failed.

 @return The number of bytes consumed, or -1 if an error occurred.
 */
- (NSInteger)appendData:(NSData *)data error:(NSError **)error;

/*!
 @property parsedData

 @abstract Returns the complete reassembled body data.

 @discussion Only valid after parsing is complete (isComplete == YES).
 */
@property (nonatomic, readonly, nullable) NSData *parsedData;

/*!
 @property isComplete

 @abstract Returns YES when all chunks have been parsed.
 */
@property (nonatomic, readonly) BOOL isComplete;

/*!
 @property remainingExpected

 @abstract Bytes expected to complete parsing.

 @discussion Returns the number of bytes still needed to complete
 the current chunk or final chunk.
 */
@property (nonatomic, readonly) NSUInteger remainingExpected;

/*!
 @property parsedLength

 @abstract Total bytes of body data parsed so far.
 */
@property (nonatomic, readonly) NSUInteger parsedLength;

/*!
 @method reset

 @abstract Resets parser to initial state for reuse.
 */
- (void)reset;

/*!
 @method parseChunkSizeFromData:offset:size:

 @abstract Parse chunk size from raw data.

 @param data The data to parse.

 @param offset Starting offset in data.

 @param size On return, contains the parsed chunk size.

 @return Offset of first byte after chunk size line, or NSNotFound on error.
 */
+ (NSUInteger)parseChunkSizeFromData:(NSData *)data
                               offset:(NSUInteger)offset
                                size:(NSUInteger *)size;

@end

NS_ASSUME_NONNULL_END
