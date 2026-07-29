// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract PDS session and app-password administration operations.
 * @discussion Requests use the PDS administrative transport and block until completion. Empty
 * identifiers return `invalid_params`; other upstream failures return `error` and `message`
 * dictionaries. Revocation and password changes are immediately stateful and have no rollback.
 */
@interface UIBackendClient (Security)

/** @abstract Lists active sessions for a nonempty actor DID. */
- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did;

/** @abstract Revokes the named session for a nonempty DID. */
- (NSDictionary *)revokeSessionForDID:(NSString *)did sessionID:(NSString *)sessionID;

/** @abstract Lists app-password metadata for a nonempty actor DID. */
- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did;

/**
 * @abstract Creates an app password with a nonempty name for a nonempty actor DID.
 */
- (NSDictionary *)createAppPasswordForDID:(NSString *)did name:(NSString *)passwordName;

/** @abstract Revokes the named app password for a nonempty actor DID. */
- (NSDictionary *)deleteAppPasswordForDID:(NSString *)did passwordName:(NSString *)passwordName;

@end

NS_ASSUME_NONNULL_END
