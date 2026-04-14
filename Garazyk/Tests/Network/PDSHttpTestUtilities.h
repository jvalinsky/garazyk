#import <Foundation/Foundation.h>
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSHttpTestUtilities : NSObject

/**
 Starts a local HTTP server for testing that delegates requests to the provided XRPC dispatcher.
 */
+ (nullable HttpServer *)startSocketServerWithDispatcher:(XrpcDispatcher *)dispatcher error:(NSError **)error;

/**
 Sends a raw HTTP GET request to the specified local port and returns the raw response data.
 */
+ (nullable NSData *)rawHTTPResponseForPath:(NSString *)path
                                       port:(uint16_t)port
                                      error:(NSError **)error;

/**
 Sends a raw HTTP GET request with additional headers to the specified local port.
 */
+ (nullable NSData *)rawHTTPResponseForPath:(NSString *)path
                                       port:(uint16_t)port
                          additionalHeaders:(nullable NSDictionary<NSString *, NSString *> *)additionalHeaders
                                      error:(NSError **)error;

/**
 Parses a raw HTTP response into a dictionary containing statusCode, headers, and body.
 */
+ (nullable NSDictionary *)parseRawHTTPResponse:(NSData *)rawData error:(NSError **)error;

/**
 Decodes a chunked HTTP body.
 Returns a dictionary with:
 - payload: The full reassembled body data
 - chunkSizes: Array of NSNumbers representing individual chunk sizes
 - consumedBytes: Total bytes consumed from the input data
 */
+ (nullable NSDictionary *)decodeChunkedBody:(NSData *)chunkedData error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
