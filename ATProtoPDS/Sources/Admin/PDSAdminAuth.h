#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @file PDSAdminAuth.h
 * @brief Admin authentication for the ATProto PDS administrative interface.
 *
 * This class provides authentication services for the PDS admin API,
 * supporting basic password-based authentication with login and logout
 * functionality for administrative operations.
 */

@interface PDSAdminAuth : NSObject

/**
 * @brief Returns the shared singleton instance for admin authentication.
 *
 * @return The shared PDSAdminAuth instance.
 */
+ (instancetype)sharedAuth;

/**
 * @brief Checks if the current request is authenticated for admin operations.
 *
 * This method verifies whether the request has a valid admin session token.
 * Authentication is required for all admin endpoints except /admin/login.
 *
 * @param request The request object to check for authentication credentials.
 * @return YES if the request is authenticated, NO otherwise.
 */
- (BOOL)isAuthenticatedWithRequest:(NSObject *)request;

/**
 * @brief Authenticates an admin user with a password.
 *
 * This method validates the provided password against the configured admin
 * password and establishes an authenticated session upon success.
 *
 * @param password The password to authenticate with.
 * @param error On return, contains an error if authentication failed.
 * @return YES if authentication succeeded, NO otherwise.
 */
- (BOOL)authenticateWithPassword:(NSString *)password error:(NSError **)error;

/**
 * @brief Logs out the current admin session.
 *
 * This method clears the current authentication token and ends the
 * authenticated session.
 */
- (void)logout;

/**
 * @brief The current admin authentication token.
 *
 * This property stores the active session token after successful authentication.
 * It is set to nil after logout.
 */
@property (nonatomic, copy, nullable) NSString *adminToken;

@end

NS_ASSUME_NONNULL_END
