// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract PDS administrative operations used by the authenticated admin UI.
 * @discussion Calls use the configured PDS admin token and convert invalid input or non-2xx
 * upstream responses into response dictionaries with `error` and `message` fields. The PDS
 * transport may refresh its token once after a 401. Methods are synchronous and can block.
 */
@interface GZAdminUIBackendClient (PDS)

/** @abstract Refreshes the configured PDS admin token with the configured admin password. */
- (BOOL)refreshPDSAdminToken;

/**
 * @abstract Probes a known service using an explicit base URL and optional admin token.
 * @discussion Used by Ozone/config connection checks for a single named target, not fleet overview.
 */
- (NSDictionary *)testConnectionForService:(NSString *)serviceName
                                   baseURL:(NSURL *)baseURL
                                adminToken:(nullable NSString *)adminToken;

/** @abstract Searches up to 25 PDS accounts, treating a nil query as an empty search term. */
- (NSDictionary *)searchAccountsWithQuery:(nullable NSString *)query;

/** @abstract Retrieves up to 25 PDS invite codes. */
- (NSDictionary *)fetchInviteCodes;

/** @abstract Disables invites for a nonempty account DID and changes its account settings. */
- (NSDictionary *)disableInvitesForAccount:(NSString *)account;

/**
 * @abstract Retrieves PDS account information for a nonempty DID.
 */
- (NSDictionary *)fetchAccountInfoForDID:(NSString *)did;

/** @abstract Replaces an account handle for a nonempty DID and changes PDS state. */
- (NSDictionary *)updateAccountHandle:(NSString *)handle forDID:(NSString *)did;

/** @abstract Requests deletion of a nonempty DID's account and changes PDS state. */
- (NSDictionary *)deleteAccount:(NSString *)did;

/** @abstract Takes down each supplied account and returns per-account failures without rollback. */
- (NSDictionary *)bulkTakedownAccounts:(NSArray<NSString *> *)dids;

/** @abstract Deletes each supplied account and returns per-account failures without rollback. */
- (NSDictionary *)bulkDeleteAccounts:(NSArray<NSString *> *)dids;

/** @abstract Enables invites for a nonempty account DID and changes its account settings. */
- (NSDictionary *)enableInvitesForAccount:(NSString *)account;

/**
 * @abstract Retrieves PDS server statistics without changing server state.
 */
- (NSDictionary *)fetchServerStats;

/** @abstract Retrieves audit entries, forwarding an optional cursor and the requested page size. */
- (NSDictionary *)fetchAuditLogWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/** @abstract Retrieves moderation reports, forwarding an optional cursor and the requested page size. */
- (NSDictionary *)fetchReportsWithCursor:(nullable NSString *)cursor limit:(NSUInteger)limit;

/** @abstract Resolves a report with the supplied action and changes its moderation state. */
- (NSDictionary *)resolveReport:(NSString *)reportID action:(NSString *)action;

@end

NS_ASSUME_NONNULL_END
