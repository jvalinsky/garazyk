#import <Foundation/Foundation.h>
#import "PDSAdminAuth.h"
#import "Metrics/PDSMetrics.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @file PDSAdminHandler.h
 * @brief HTTP request handlers for the ATProto PDS administrative API.
 *
 * This class implements the HTTP request handlers for all PDS admin endpoints,
 * providing administrative operations for user management, invite codes,
 * blob inspection, and metrics export.
 */

typedef NS_ENUM(NSInteger, PDSHTTPMethod) {
    PDSHTTPMethodGET,
    PDSHTTPMethodPOST,
    PDSHTTPMethodPUT,
    PDSHTTPMethodDELETE
};

/**
 * @brief HTTP request method enumeration.
 *
 * Represents the supported HTTP methods for admin API requests.
 */

/**
 * @class PDSAdminHandler
 * @brief Handles HTTP requests for the PDS administrative API.
 *
 * This class implements the main request handler for all admin endpoints,
 * routing requests to appropriate handlers for users, invites, blobs,
 * metrics, and health checks. Authentication is required for all endpoints
 * except /admin/login.
 */
@interface PDSAdminHandler : NSObject

/**
 * @brief Returns the shared singleton instance for admin request handling.
 *
 * @return The shared PDSAdminHandler instance.
 */
+ (instancetype)sharedHandler;

#pragma mark - Internal Data Access (Direct Dictionaries)

- (NSDictionary *)getHealthData;
- (NSDictionary *)getStatsData;
- (NSDictionary *)getUsersData;
- (NSDictionary *)getInvitesData;
- (NSDictionary *)getBlobsData;

#pragma mark - Request Handling

/**
 * @brief Processes an admin API HTTP request.
 *
 * This method routes the request to the appropriate handler based on the
 * HTTP method and path. It handles authentication and returns an HTTP response.
 *
 * @param method The HTTP method of the request.
 * @param path The request path (e.g., "/admin/users").
 * @param headers The HTTP request headers.
 * @param body The request body data, or nil for GET requests.
 * @return The complete HTTP response string, or nil if the path is not recognized.
 */
- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body;

/**
 * @brief Processes an admin API request and returns response metadata.
 *
 * @param method The HTTP method.
 * @param path The request path.
 * @param headers HTTP headers.
 * @param body Optional body.
 * @param statusCode Output status code when a route is handled.
 * @param contentType Output content type when a route is handled.
 * @return Response body string, or nil if the path is not recognized.
 */
- (nullable NSString *)handleRequestWithMethod:(PDSHTTPMethod)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

#pragma mark - User Detail Data

/// Get user detail data including invites created by them
- (nullable NSDictionary *)getUserDetailDataForDid:(NSString *)did;

/// Get moderation reports list
- (nullable NSArray *)getModerationReportsData;

@end

NS_ASSUME_NONNULL_END
