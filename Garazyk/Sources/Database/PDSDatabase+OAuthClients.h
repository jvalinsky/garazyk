// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSDatabase (OAuthClients)

- (nullable NSDictionary *)getClientWithID:(NSString *)clientID error:(NSError **)error;
- (BOOL)createClient:(NSDictionary *)client error:(NSError **)error;
- (nullable NSDictionary *)getOAuthClientWithID:(NSString *)clientID error:(NSError **)error;
- (BOOL)createOAuthClient:(NSDictionary *)client error:(NSError **)error;
- (BOOL)seedTestClient:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)getAllOAuthClientsWithError:(NSError **)error;
- (BOOL)deleteOAuthClientWithID:(NSString *)clientID error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
