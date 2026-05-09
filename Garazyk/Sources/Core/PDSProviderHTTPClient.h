/*!
 @file PDSProviderHTTPClient.h

 @abstract Shared HTTP client for outbound provider API calls.

 @discussion
    Generalizes the email-specific HTTP client into a reusable component
    for any provider that needs to make outbound HTTP API calls (Resend,
    Twilio, Turnstile siteverify, etc.). Handles authentication, retry
    logic with exponential backoff, and error mapping.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for provider HTTP client errors. */
extern NSString *const PDSProviderHTTPClientErrorDomain;

/*!
 @enum PDSProviderHTTPClientErrorCode

 @abstract Error codes for provider HTTP client operations.
 */
typedef NS_ENUM(NSInteger, PDSProviderHTTPClientErrorCode) {
    PDSProviderHTTPClientErrorSerializationFailed = 1,
    PDSProviderHTTPClientErrorRequestFailed = 2,
    PDSProviderHTTPClientErrorHTTPError = 3,
    PDSProviderHTTPClientErrorMaxRetriesExceeded = 4,
};

/*!
 @class PDSProviderHTTPClient

 @abstract HTTP client for outbound provider API calls.

 @discussion
    Provides POST and GET methods with Bearer token authentication,
    automatic retry with exponential backoff for server errors and
    rate limits, and JSON response parsing. Thread-safe: each call
    blocks until completion (synchronous).
 */
@interface PDSProviderHTTPClient : NSObject

/*! The base URL for the provider API. */
@property (nonatomic, strong, readonly) NSURL *baseURL;

/*! The authorization header value (e.g. "Bearer <api_key>"). */
@property (nonatomic, copy, readonly) NSString *authHeader;

/*! Timeout interval for requests (default: 30s). */
@property (nonatomic, assign) NSTimeInterval timeoutInterval;

/*! Maximum number of retries for failed requests (default: 3). */
@property (nonatomic, assign) NSUInteger maxRetries;

/*!
 @method initWithBaseURL:authHeader:
 @abstract Designated initializer.
 @param baseURL The base URL for the provider API.
 @param authHeader The authorization header value (e.g. "Bearer <api_key>").
 */
- (instancetype)initWithBaseURL:(NSURL *)baseURL
                      authHeader:(NSString *)authHeader NS_DESIGNATED_INITIALIZER;

/*!
 @method initWithBaseURL:apiKey:
 @abstract Convenience initializer using Bearer token authentication.
 @param baseURL The base URL for the provider API.
 @param apiKey The API key (will be formatted as "Bearer <apiKey>").
 */
- (instancetype)initWithBaseURL:(NSURL *)baseURL
                         apiKey:(NSString *)apiKey;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/*!
 @method postPath:body:error:
 @abstract Sends a POST request with a JSON body.
 @param path The path component to append to the base URL.
 @param body The JSON-serializable dictionary to send as the request body.
 @param error On failure, set to a client or HTTP error.
 @return The parsed JSON response as a dictionary, or nil on error.
 */
- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                              error:(NSError **)error;

/*!
 @method postPath:body:headers:error:
 @abstract Sends a POST request with custom headers.
 @param path The path component to append to the base URL.
 @param body The JSON-serializable dictionary to send as the request body.
 @param extraHeaders Additional HTTP headers to include.
 @param error On failure, set to a client or HTTP error.
 @return The parsed JSON response as a dictionary, or nil on error.
 */
- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                            headers:(nullable NSDictionary<NSString *, NSString *> *)extraHeaders
                              error:(NSError **)error;

/*!
 @method getPath:params:error:
 @abstract Sends a GET request with query parameters.
 @param path The path component to append to the base URL.
 @param params Query parameters to include in the URL.
 @param error On failure, set to a client or HTTP error.
 @return The parsed JSON response as a dictionary, or nil on error.
 */
- (nullable NSDictionary *)getPath:(NSString *)path
                            params:(nullable NSDictionary *)params
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
