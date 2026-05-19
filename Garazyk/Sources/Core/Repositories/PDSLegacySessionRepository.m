// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSLegacySessionRepository.m
 @abstract Implementation of the legacy session adapter.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSLegacySessionRepository.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"

@implementation PDSLegacySessionRepository {
    PDSServiceDatabases *_serviceDatabases;
}

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    self = [super init];
    if (self) {
        _serviceDatabases = serviceDatabases;
    }
    return self;
}

- (BOOL)storeRefreshToken:(NSString *)refreshToken forAccountDid:(NSString *)did error:(NSError **)error {
    return [_serviceDatabases storeRefreshToken:refreshToken forAccount:did error:error];
}

- (nullable NSString *)accountDidForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    PDSDatabaseAccount *account = [_serviceDatabases getAccountByRefreshToken:refreshToken error:error];
    return account.did;
}

- (BOOL)revokeRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    return [_serviceDatabases deleteRefreshToken:refreshToken error:error];
}

- (BOOL)revokeAllRefreshTokensForAccountDid:(NSString *)did error:(NSError **)error {
    return [_serviceDatabases deleteRefreshTokensForAccount:did error:error];
}

- (BOOL)storeRefreshToken:(NSString *)refreshToken sessionID:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error {
    return [_serviceDatabases storeRefreshToken:refreshToken sessionID:sessionID forAccountDid:did error:error];
}

- (nullable NSDictionary *)sessionInfoForRefreshToken:(NSString *)refreshToken error:(NSError **)error {
    return [_serviceDatabases sessionInfoForRefreshToken:refreshToken error:error];
}

- (BOOL)isSessionActive:(NSString *)sessionID forAccountDid:(NSString *)did error:(NSError **)error {
    return [_serviceDatabases isSessionActive:sessionID forAccountDid:did error:error];
}

- (BOOL)revokeSession:(NSString *)sessionID error:(NSError **)error {
    return [_serviceDatabases revokeSession:sessionID error:error];
}

@end
