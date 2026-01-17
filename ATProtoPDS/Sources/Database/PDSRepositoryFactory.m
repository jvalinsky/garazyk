/*!
 @file PDSRepositoryFactory.m
 @abstract Implementation of repository factory with feature flag support.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSRepositoryFactory.h"
#import "App/PDSConfiguration.h"
#import "Core/Repositories/PDSLegacyAccountRepository.h"
#import "Core/Repositories/PDSLegacySessionRepository.h"
#import "Core/Managers/PDSAccountManager.h"
#import "Database/Service/ServiceDatabases.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PDSRepositoryFactory

+ (id<PDSAccountRepository>)accountRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    
    if (config.useNewRepositoryImplementation) {
        return [[PDSAccountManager alloc] initWithServicePool:serviceDatabases.servicePool];
    } else {
        return [[PDSLegacyAccountRepository alloc] initWithServiceDatabases:serviceDatabases];
    }
}

+ (id<PDSSessionRepository>)sessionRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    // For now, always return legacy.
    return [[PDSLegacySessionRepository alloc] initWithServiceDatabases:serviceDatabases];
}

@end

NS_ASSUME_NONNULL_END
