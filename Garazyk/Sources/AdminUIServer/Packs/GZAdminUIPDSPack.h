// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/GZAdminUIPack.h"

@class GZAdminUIServiceConfig;

NS_ASSUME_NONNULL_BEGIN

/** @abstract Admin UI pack for the PDS surface. */
@interface GZAdminUIPDSPack : NSObject <GZAdminUIPack>

/** @abstract Renders the PDS account-search result. */
+ (NSString *)renderAccountsPartial:(NSDictionary *)result;
/** @abstract Renders the PDS invite-code result. */
+ (NSString *)renderInvitesPartial:(NSDictionary *)result;
/** @abstract Renders one PDS account detail result. */
+ (NSString *)renderAccountDetailPartial:(NSDictionary *)result;
/** @abstract Renders blob metadata, optionally scoped to a DID. */
+ (NSString *)renderBlobsPartial:(NSDictionary *)result did:(nullable NSString *)did;
/** @abstract Renders PDS server statistics. */
+ (NSString *)renderServerStatsPartial:(NSDictionary *)result;
/** @abstract Renders a paginated PDS audit-log result. */
+ (NSString *)renderAuditLogPartial:(NSDictionary *)result;
/** @abstract Renders PDS moderation reports. */
+ (NSString *)renderPDSReportsPartial:(NSDictionary *)result;

@end

NS_ASSUME_NONNULL_END
