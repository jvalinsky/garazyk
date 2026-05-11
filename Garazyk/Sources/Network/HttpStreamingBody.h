// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @class HttpStreamingBody

 @abstract Handles HTTP request body streaming, either buffering in memory or writing to a file.

 @discussion For small bodies (under threshold), data is buffered in memory for fast access.
 For large bodies, data is streamed directly to a temporary file to avoid memory pressure.
 */
@interface HttpStreamingBody : NSObject

/*!
 @property data

 @abstract Returns the body data if buffered in memory, nil if streamed to file.
 */
@property (nonatomic, readonly, nullable) NSData *data;

/*!
 @property filePath

 @abstract Returns the file path if streamed to file, nil if buffered in memory.
 */
@property (nonatomic, readonly, nullable) NSString *filePath;

/*!
 @property length

 @abstract Total bytes received so far.
 */
@property (nonatomic, readonly) NSUInteger length;

/*!
 @property isComplete

 @abstract YES when all body data has been received.
 */
@property (nonatomic, readonly) BOOL isComplete;

/*!
 @method initWithThreshold:

 @abstract Initialize with memory threshold for buffering.

 @param memoryThreshold Maximum bytes to buffer in memory before streaming to file.
                        Pass 0 to always stream to file, or UINT64_MAX to always buffer.

 @return An initialized streaming body handler.
 */
- (instancetype)initWithMemoryThreshold:(NSUInteger)memoryThreshold;

/*!
 @method appendData:error:

 @abstract Append data to the body.

 @param data The data chunk to append.

 @param error On return, contains error if streaming failed.

 @return YES if data was accepted, NO on error.
 */
- (BOOL)appendData:(NSData *)data error:(NSError **)error;

/*!
 @method finalizeWithError:

 @abstract Finalize the body after all data is received.

 @param error On return, contains error if finalization failed.

 @return YES if successful, NO on error.
 */
- (BOOL)finalizeWithError:(NSError **)error;

/*!
 @method createInputStream

 @abstract Create an input stream to read the body data.

 @return An input stream positioned at the start of the body data,
         or nil if the body is incomplete or an error occurred.
 */
- (nullable NSInputStream *)createInputStream;

/*!
 @method reset

 @abstract Reset the handler for reuse, cleaning up any temporary files.
 */
- (void)reset;

@end

NS_ASSUME_NONNULL_END
