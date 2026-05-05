#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSRateLimitAdminHandler
 * @brief Handles rate limit management API endpoints with audit trail.
 *
 * Provides rate limit administration including queries, monitoring,
 * and admin overrides with full audit trail logging.
 *
 * Endpoints:
 * - POST /query - Query rate limit status for identifier (DID/IP/blob)
 * - GET /top - Get top rate-limited users/identifiers
 * - POST /clear - Clear rate limit with audit trail (admin override)
 *
 * Request Format (POST /query):
 * {
 *   "identifier": "did:plc:xxx",
 *   "type": "did"  // or "ip", "blob"
 * }
 *
 * Response Format (POST /query):
 * {
 *   "identifier": "did:plc:xxx",
 *   "type": "did",
 *   "limit": 1000,
 *   "remaining": 842,
 *   "reset_at": 1234567890
 * }
 *
 * Request Format (POST /clear):
 * {
 *   "identifier": "did:plc:xxx",
 *   "type": "did",
 *   "reason": "Spam detected and cleared"  // Required, must be non-empty
 * }
 *
 * Response Format (POST /clear):
 * {
 *   "cleared": true,
 *   "identifier": "did:plc:xxx",
 *   "type": "did",
 *   "timestamp": 1234567890
 * }
 *
 * Safety Features:
 * - Every clear action creates immutable audit trail entry
 * - Admin DID and reason logged for all clears
 * - Reason field is mandatory (cannot be empty)
 */
@interface PDSRateLimitAdminHandler : NSObject

/**
 * @brief Returns the shared singleton instance.
 *
 * @return The shared PDSRateLimitAdminHandler instance.
 */
+ (instancetype)sharedHandler;

/**
 * @brief Processes rate limit admin API requests.
 *
 * @param method HTTP method
 * @param path Request path (e.g., /query, /top, /clear)
 * @param headers HTTP headers
 * @param body Request body (JSON)
 * @param statusCode Output status code
 * @param contentType Output content type
 * @return JSON response body or error message
 */
- (nullable NSString *)handleRequestWithMethod:(NSInteger)method
                                         path:(NSString *)path
                                      headers:(NSDictionary<NSString *, NSString *> *)headers
                                         body:(nullable NSData *)body
                                   statusCode:(nullable NSInteger *)statusCode
                                  contentType:(NSString * _Nullable * _Nullable)contentType;

/**
 * @brief Clear rate limit for an identifier with audit trail.
 *
 * @param identifier The DID or IP to clear
 * @param type The type of identifier ("did" or "ip")
 * @param adminDid The DID of the admin performing the action
 * @param reason Reason for clearing (required)
 * @param error Output error
 * @return YES if successful
 */
- (BOOL)clearRateLimitForIdentifier:(NSString *)identifier
                               type:(NSString *)type
                            adminDid:(NSString *)adminDid
                             reason:(NSString *)reason
                              error:(NSError **)error;

/**
 * @brief Query rate limit status for an identifier.
 *
 * @param identifier The DID or IP to query
 * @param type The type of identifier ("did" or "ip")
 * @param error Output error
 * @return Dictionary with rate limit status or nil on error
 */
- (nullable NSDictionary *)queryRateLimitForIdentifier:(NSString *)identifier
                                                   type:(NSString *)type
                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
