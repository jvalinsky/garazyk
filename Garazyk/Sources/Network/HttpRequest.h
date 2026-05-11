// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpRequest.h

 @abstract HTTP request parsing and representation.

 @discussion Parses raw HTTP request data into structured components including
 method, path, headers, and body. Supports query parameter extraction, JSON
 body parsing, and multipart form data.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @enum HttpMethod

 @abstract HTTP method identifiers.

 @constant HttpMethodGET HTTP GET method.
 @constant HttpMethodPOST HTTP POST method.
 @constant HttpMethodPUT HTTP PUT method.
 @constant HttpMethodDELETE HTTP DELETE method.
 @constant HttpMethodPATCH HTTP PATCH method.
 @constant HttpMethodOPTIONS HTTP OPTIONS method.
 @constant HttpMethodHEAD HTTP HEAD method.
 @constant HttpMethodUnknown Unknown/unsupported method.
 */
typedef NS_ENUM(NSInteger, HttpMethod) {
    HttpMethodGET,
    HttpMethodPOST,
    HttpMethodPUT,
    HttpMethodDELETE,
    HttpMethodPATCH,
    HttpMethodOPTIONS,
    HttpMethodHEAD,
    HttpMethodUnknown
};

/*!
 @class HttpRequest

 @abstract Represents a parsed HTTP request.

 @discussion Provides access to all request components including method,
 path, query parameters, headers, and body. Supports JSON and multipart parsing.
 */
@interface HttpRequest : NSObject

/*! The parsed HTTP method enum. */
@property (nonatomic, readonly) HttpMethod method;

/*! The HTTP method as a string. */
@property (nonatomic, readonly, copy) NSString *methodString;

/*! The request path (without query string). */
@property (nonatomic, readonly, copy) NSString *path;

/*! The raw query string (after ?). */
@property (nonatomic, readonly, copy) NSString *queryString;

/*! Parsed query parameters as key-value pairs. Repeated keys will have an NSArray of values. */
@property (nonatomic, readonly, nullable, copy) NSDictionary<NSString *, id> *queryParams;

- (nullable NSArray<NSString *> *)queryParamsForKey:(NSString *)key;

/*! Parsed path parameters extracted from the matched route pattern. */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *pathParameters;

/*! The HTTP version (e.g., "HTTP/1.1"). */
@property (nonatomic, readonly, copy) NSString *version;

/*! Request headers as key-value pairs. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *headers;

/*! The raw request body. */
@property (nonatomic, readonly, nullable, copy) NSData *body;

/*! The body parsed as JSON (if Content-Type is application/json). */
@property (nonatomic, readonly, nullable, copy) NSDictionary *jsonBody;

/*! Parsed multipart form data (if Content-Type is multipart/form-data). */
@property (nonatomic, readonly, nullable, copy) NSDictionary *multipartFormData;

/*! The client's IP address. */
@property (nonatomic, readonly, nullable, copy) NSString *remoteAddress;

/*! Correlation ID for tracing this request across logs. */
@property (nonatomic, readonly, copy) NSString *correlationID;

/*! Creates a request from raw HTTP data. */
+ (instancetype)requestWithData:(NSData *)data;

/*! Creates a request from raw HTTP data with client address. */
+ (instancetype)requestWithData:(NSData *)data remoteAddress:(NSString *)remoteAddress;

- (instancetype)initWithMethod:(HttpMethod)method
                     methodString:(NSString *)methodString
                           path:(NSString *)path
                    queryString:(NSString *)queryString
                     queryParams:(NSDictionary<NSString *, NSString *> *)queryParams
                         version:(NSString *)version
                         headers:(NSDictionary<NSString *, NSString *> *)headers
                            body:(NSData *)body
                    remoteAddress:(NSString *)remoteAddress;

/*! Returns the value of a header (case-insensitive lookup). */
- (NSString *)headerForKey:(NSString *)key;

/*! Returns the value of a query parameter. */
- (NSString *)queryParamForKey:(NSString *)key;

/*!
 * Mutable context for middleware to inject values.
 *
 * Middleware chains can use this to pass data to downstream handlers.
 * For example, AuthMiddleware injects "authenticatedDid" here.
 */
@property (nonatomic, strong, nullable) NSMutableDictionary *middlewareContext;

/*! Convenience: Returns the authenticated DID from middleware context. */
- (nullable NSString *)authenticatedDid;

/*! Convenience: Sets the authenticated DID in middleware context. */
- (void)setAuthenticatedDid:(NSString *)did;

@end

NS_ASSUME_NONNULL_END
