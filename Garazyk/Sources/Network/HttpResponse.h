/*!
 @file HttpResponse.h

 @abstract HTTP response building and serialization.

 @discussion Provides a builder for HTTP responses with support for status codes,
 headers, and various body formats (JSON, text, binary). Includes security
 header defaults.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSData * _Nullable (^HttpResponseBodyChunkProducer)(NSError **error);

/*!
 @enum HttpStatusCode

 @abstract Common HTTP status codes.
 */
typedef NS_ENUM(NSInteger, HttpStatusCode) {
    HttpStatusOK = 200,
    HttpStatusCreated = 201,
    HttpStatusAccepted = 202,
    HttpStatusNoContent = 204,
    HttpStatusBadRequest = 400,
    HttpStatusUnauthorized = 401,
    HttpStatusForbidden = 403,
    HttpStatusNotFound = 404,
    HttpStatusMethodNotAllowed = 405,
    HttpStatusGone = 410,
    HttpStatusLengthRequired = 411,
    HttpStatusConflict = 409,
    HttpStatusPayloadTooLarge = 413,
    HttpStatusUnsupportedMediaType = 415,
    HttpStatusTooManyRequests = 429,
    HttpStatusInternalServerError = 500,
    HttpStatusNotImplemented = 501,
    HttpStatusServiceUnavailable = 503,
    HttpStatusGatewayTimeout = 504
};


/*!
 @class HttpResponse

 @abstract Builds HTTP responses for sending to clients.

 @discussion Provides factory methods and builders for common response types.
 Automatically applies security headers.
 */
@interface HttpResponse : NSObject

/*! The HTTP status code. */
@property (nonatomic, assign) HttpStatusCode statusCode;

/*! The status message (e.g., "OK", "Not Found"). */
@property (nonatomic, copy) NSString *statusMessage;

/*! The Content-Type header value. */
@property (nonatomic, copy, nullable) NSString *contentType;

/*! The raw response body. */
@property (nonatomic, copy, nullable) NSData *body;

/*! Optional file path used for streaming large bodies. */
@property (nonatomic, copy, nullable) NSString *bodyFilePath;

/*! When YES and bodyFilePath is set, the file is removed after send completes. */
@property (nonatomic, assign) BOOL deleteBodyFileAfterSend;

/*! Optional pull-based producer for streaming response body chunks. */
@property (nonatomic, copy, nullable) HttpResponseBodyChunkProducer bodyChunkProducer;

/*! When YES, headers are emitted with Transfer-Encoding: chunked instead of Content-Length. */
@property (nonatomic, assign) BOOL chunkedTransferEncoding;

/*! The body as a JSON object (sets Content-Type to application/json). */
@property (nonatomic, copy, nullable) id jsonBody;

/*! The body as a string. */
@property (nonatomic, copy, nullable) NSString *bodyString;

/*! Response headers. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *headers;

/*! Whether to use keep-alive connection. */
@property (nonatomic, assign) BOOL keepAlive;

/*! Applies security headers to a headers dictionary. */
+ (void)applySecurityHeaders:(NSMutableDictionary *)headers;

@property (class, nonatomic, copy, readonly) NSString *xContentTypeOptions;
@property (class, nonatomic, copy, readonly) NSString *xFrameOptions;
@property (class, nonatomic, copy, readonly) NSString *contentSecurityPolicy;

/*! Creates an empty response. */
+ (instancetype)response;

/*! Creates a response with the given status code. */
+ (instancetype)responseWithStatusCode:(HttpStatusCode)statusCode;

/*! Creates a JSON response. */
+ (instancetype)jsonResponse:(id)json statusCode:(HttpStatusCode)statusCode;

/*! Creates a text response. */
+ (instancetype)textResponse:(NSString *)text statusCode:(HttpStatusCode)statusCode;

/*! Sets a response header. */
- (void)setHeader:(NSString *)value forKey:(NSString *)key;

/*! Returns the value for a given header key (case-insensitive). */
- (nullable NSString *)headerForKey:(NSString *)key;

/*! Sets the body as JSON. */
- (void)setJsonBody:(id)json;

/*! Sets the body as a string. */
- (void)setBodyString:(NSString *)body;

/*! Sets the body as raw data. */
- (void)setBodyData:(NSData *)data;

/*! Sets the body to stream from a file path. */
- (void)setBodyFileAtPath:(NSString *)path deleteAfterSend:(BOOL)deleteAfterSend;

/*! Sets a pull-based body producer and stream framing mode. */
- (void)setBodyChunkProducer:(HttpResponseBodyChunkProducer)producer
     chunkedTransferEncoding:(BOOL)chunkedTransferEncoding;

/*! Serializes only the response headers with a known body length. */
- (NSData *)serializeHeadersForBodyLength:(NSUInteger)bodyLength;

/*! Serializes the response to HTTP wire format. */
- (NSData *)serialize;

@end

NS_ASSUME_NONNULL_END
