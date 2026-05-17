// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

/**
 * @abstract Declares the PDSAdminAuth public API.
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
 * @brief Validates admin authentication for a set of HTTP headers.
 *
 * This is the lower-level entrypoint used by both the admin HTTP routes and
 * XRPC admin endpoints. It extracts the bearer/admin token, verifies claims and
 * signature, and enforces logout invalidation state.
 *
 * @param headers HTTP headers to validate (case-insensitive keys).
 * @param error On return, contains an error describing why authorization failed.
 * @return YES if authorized for admin operations, NO otherwise.
 */
/**
 * @abstract Performs the authenticateHeaders operation.
 */
- (BOOL)authenticateHeaders:(NSDictionary<NSString *, NSString *> *)headers error:(NSError **)error;

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
/**
 * @abstract Exposes the admin token value.
 */
@property (nonatomic, copy, nullable) NSString *adminToken;

/**
 * @brief The data directory path used to persist token invalidation state.
 *
 * Set this at startup so that logout survives process restarts. When set,
 * the minimumTokenIssuedAt timestamp is written to a file in this directory.
 */
/**
 * @abstract Exposes the data directory value.
 */
@property (nonatomic, copy, nullable) NSString *dataDirectory;
/**
 * @brief The controller used for JWT signing and verification.
 *
 * If nil, falls back to [PDSController sharedController].
 */
@property (nonatomic, strong, nullable) id controller;

/**
 * @brief Checks if a DID has administrator privileges.
 *
 * @param did The DID to check.
 * @return YES if the DID is an administrator, NO otherwise.
 */
- (BOOL)isAdminDid:(NSString *)did;

/**
 * @brief Adds a DID to the persistent administrator list.
 *
 * @param did The DID to add.
 * @param error On return, contains an error if the operation failed.
 * @return YES if the DID was added successfully, NO otherwise.
 */
- (BOOL)addAdminDid:(NSString *)did error:(NSError **)error;

/**
 * @brief Removes a DID from the persistent administrator list.
 *
 * @param did The DID to remove.
 * @param error On return, contains an error if the operation failed.
 * @return YES if the DID was removed successfully, NO otherwise.
 */
- (BOOL)removeAdminDid:(NSString *)did error:(NSError **)error;

/**
 * @brief Returns the list of all administrator DIDs.
 *
 * @return An array of DID strings.
 */
- (NSArray<NSString *> *)listAdminDids;

@end

NS_ASSUME_NONNULL_END
