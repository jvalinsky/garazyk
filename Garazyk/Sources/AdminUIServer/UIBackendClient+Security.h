// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "AdminUIServer/UIBackendClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface UIBackendClient (Security)

- (NSDictionary *)fetchActiveSessionsForDID:(NSString *)did;

- (NSDictionary *)revokeSessionForDID:(NSString *)did sessionID:(NSString *)sessionID;

- (NSDictionary *)fetchAppPasswordsForDID:(NSString *)did;

/**
 * @abstract Create app password for did.
 * @param did Actor DID for the request.
 * @param passwordName Application password name.
 * @return The response dictionary, or nil when the request fails.
 */
- (NSDictionary *)createAppPasswordForDID:(NSString *)did name:(NSString *)passwordName;

- (NSDictionary *)deleteAppPasswordForDID:(NSString *)did passwordName:(NSString *)passwordName;

@end

NS_ASSUME_NONNULL_END
