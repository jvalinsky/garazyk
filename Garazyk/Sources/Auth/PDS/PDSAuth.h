// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract PDS-specific adapter for ATProtoAuthVerifier's AccountPolicy protocol.
 *
 * @discussion Bridges ATProtoAuthVerifier's generic account-status check to PDSDatabase
 * and the admin controller.
 */

#import <Foundation/Foundation.h>
#import "Auth/Verifier/AuthVerifierProtocols.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/**
 * @abstract PDS implementation of AccountPolicy.
 *
 * @discussion Checks account takedown status and admin privileges via PDSAdminController.
 *    The admin controller is a strong dependency injected at construction time and is
 *    required for correct operation. If nil, isAccountAllowed: fails closed (denies all)
 *    and isAdmin: returns NO.
 */
@interface PDSAccountPolicy : NSObject <AccountPolicy>

/**
 * @abstract Initialize with PDS database and admin controller.
 *
 * @param database The PDS database for account lookups.
 * @param adminController The admin controller for takedown and admin checks.
 *    Must not be nil for production operation; a nil controller causes all
 *    isAccountAllowed: calls to fail closed (deny).
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database
                adminController:(id)adminController NS_DESIGNATED_INITIALIZER;

/**
 * @abstract Initialize with PDS database only (admin controller deferred).
 *
 * @discussion This initializer exists for migration compatibility. New call sites
 *    should use initWithDatabase:adminController: to fail closed on startup rather
 *    than per-request.
 */
- (instancetype)initWithDatabase:(PDSDatabase *)database;

/**
 * @abstract Set the admin controller for admin checks.
 *
 * @discussion May be called once after initWithDatabase: for deferred wiring.
 */
- (void)setAdminController:(id)adminController;

@end

NS_ASSUME_NONNULL_END
