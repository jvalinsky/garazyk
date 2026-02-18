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

@end
