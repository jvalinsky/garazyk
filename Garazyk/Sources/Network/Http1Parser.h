/*!
 @file Http1Parser.h

 @abstract Parses HTTP/1.x request bytes into structured parse state and message components.

 @discussion Defines parser interfaces and contracts for HTTP/1.x line/header/body parsing. Exposes deterministic parse outcomes used by higher-level session and dispatch layers, without owning socket I/O or route execution.
 */

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, Http1ParserState) {
    Http1ParserStateReadingHeaders,
    Http1ParserStateReadingBody,
    Http1ParserStateReadingChunkedBody,
    Http1ParserStateComplete,
    Http1ParserStateError
};

@interface Http1ParserError : NSObject
@property (nonatomic, readonly) NSUInteger statusCode;
@property (nonatomic, readonly) NSString *errorCode;
@property (nonatomic, readonly) NSString *message;

- (instancetype)initWithStatusCode:(NSUInteger)statusCode
                         errorCode:(NSString *)errorCode
                           message:(NSString *)message;
@end

@interface Http1Parser : NSObject

@property (nonatomic, readonly) Http1ParserState state;
@property (nonatomic, assign) NSUInteger maxHeaderBytes;  // default 16KB
@property (nonatomic, assign) NSUInteger maxBodyBytes;    // default 50MB

// Client IP/Address to populate in the resulting HttpRequest
@property (nonatomic, copy, nullable) NSString *remoteAddress;

// Feed raw bytes. Returns YES if a complete request is available or an error occurred.
- (BOOL)feedData:(NSData *)data;

// After feedData: returns YES, exactly one of these is non-nil:
- (nullable HttpRequest *)completedRequest;
- (nullable Http1ParserError *)parseError;

// Remaining bytes after the consumed request (for pipelining)
- (NSData *)unconsumedData;

// Reset for next request on same connection
- (void)reset;

@end

NS_ASSUME_NONNULL_END