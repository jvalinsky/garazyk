// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * A utility client for making HTTP requests to email providers.
 * Handles authentication, retry logic, and error mapping.
 */
/**
 * @abstract Declares the PDSEmailHTTPClient public API.
 */
@interface PDSEmailHTTPClient : NSObject

/// The base URL for the email provider API.
/**
 * @abstract Exposes the base url value.
 */
@property (nonatomic, strong, readonly) NSURL *baseURL;

/// The API key for authentication.
@property (nonatomic, strong, readonly) NSString *apiKey;

/// The timeout interval for requests (default: 30s).
@property (nonatomic, assign) NSTimeInterval timeoutInterval;

/// The maximum number of retries for failed requests (default: 3).
@property (nonatomic, assign) NSUInteger maxRetries;

/**
 * Initializes the client with a base URL and API key.
 *
 * @param baseURL The base URL for the email provider API.
 * @param apiKey The API key for authentication.
 */
- (instancetype)initWithBaseURL:(NSURL *)baseURL apiKey:(NSString *)apiKey;

/**
 * Sends a POST request to the specified path with the given body.
 * This method is synchronous and blocks until the request completes or fails.
 *
 * @param path The path component to append to the base URL.
 * @param body The JSON-serializable dictionary to send as the request body.
 * @param error A pointer to an NSError object that will be set if an error occurs.
 * @return The parsed JSON response as a dictionary, or nil if an error occurred.
 */
- (nullable NSDictionary *)postPath:(NSString *)path
                               body:(NSDictionary *)body
                              error:(NSError * _Nullable *)error;

@end

NS_ASSUME_NONNULL_END
