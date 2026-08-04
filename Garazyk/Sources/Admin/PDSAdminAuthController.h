// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

@class JWTMinter;
@class PDSDatabase;

NS_ASSUME_NONNULL_BEGIN

/**
 * @protocol PDSAdminAuthController
 * @brief Minimal controller surface required by admin authentication.
 *
 * This protocol keeps admin authentication independent from the Runtime
 * compatibility facade. The application supplies the concrete controller at
 * composition time; authentication only needs JWT material and audit storage.
 */
@protocol PDSAdminAuthController <NSObject>

/** JWT signer and verifier used for admin tokens. */
@property (nonatomic, strong, readonly, nullable) JWTMinter *jwtMinter;

/** Opens the service database used for admin audit entries. */
- (nullable PDSDatabase *)serviceDatabaseWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
