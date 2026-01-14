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
    HttpStatusConflict = 409,
    HttpStatusInternalServerError = 500,
    HttpStatusNotImplemented = 501,
    HttpStatusServiceUnavailable = 503
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

/*! The body as a JSON dictionary (sets Content-Type to application/json). */
@property (nonatomic, copy, nullable) NSDictionary *jsonBody;

/*! The body as a string. */
@property (nonatomic, copy, nullable) NSString *bodyString;

/*! Response headers. */
@property (nonatomic, copy) NSMutableDictionary<NSString *, NSString *> *headers;

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
+ (instancetype)jsonResponse:(NSDictionary *)json statusCode:(HttpStatusCode)statusCode;

/*! Creates a text response. */
+ (instancetype)textResponse:(NSString *)text statusCode:(HttpStatusCode)statusCode;

/*! Sets a response header. */
- (void)setHeader:(NSString *)value forKey:(NSString *)key;

/*! Sets the body as JSON. */
- (void)setJsonBody:(NSDictionary *)json;

/*! Sets the body as a string. */
- (void)setBodyString:(NSString *)body;

/*! Sets the body as raw data. */
- (void)setBodyData:(NSData *)data;

/*! Serializes the response to HTTP wire format. */
- (NSData *)serialize;

@end

NS_ASSUME_NONNULL_END
