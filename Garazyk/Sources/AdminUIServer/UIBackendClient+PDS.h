// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (PDS)



/**
 * Obtain a fresh admin JWT from the PDS /admin/login endpoint.
 *
 * Uses the pdsAdminPassword from the configuration. On success, stores
 * the returned token in configuration.pdsAdminToken and returns YES.
 * Returns NO if no password is configured or the login request fails.
 */
- (BOOL)refreshPDSAdminToken;

- (NSDictionary *)fetchServiceOverview;

- (NSDictionary *)testConnectionForService:(NSString *)serviceName;

/**
 * @abstract Test connection for service.
 * @param serviceName Backend service name.
 * @param baseURL Backend service base URL.
 * @param adminToken Admin authorization token.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)testConnectionForService:(NSString *)serviceName
                                   baseURL:(NSURL *)baseURL
                                adminToken:(nullable NSString *)adminToken;

- (NSDictionary *)searchAccountsWithQuery:(nullable NSString *)query;

/**
 * @abstract Fetch invite codes.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchInviteCodes;

- (NSDictionary *)disableInvitesForAccount:(NSString *)account;

/**
 * @abstract Fetch account info for did.
 * @param did Actor DID for the request.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchAccountInfoForDID:(NSString *)did;

- (NSDictionary *)updateAccountHandle:(NSString *)handle forDID:(NSString *)did;

- (NSDictionary *)deleteAccount:(NSString *)did;

- (NSDictionary *)bulkTakedownAccounts:(NSArray<NSString *> *)dids;

- (NSDictionary *)bulkDeleteAccounts:(NSArray<NSString *> *)dids;

- (NSDictionary *)enableInvitesForAccount:(NSString *)account;

/**
 * @abstract Fetch server stats.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)fetchServerStats;

- (NSDictionary *)fetchAuditLogWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

- (NSDictionary *)fetchReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

- (NSDictionary *)resolveReport:(NSString *)reportID action:(NSString *)action;

@end

NS_ASSUME_NONNULL_END
