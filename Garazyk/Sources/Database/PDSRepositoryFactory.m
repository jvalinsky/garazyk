// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSRepositoryFactory.m
 @abstract Implementation of repository factory with feature flag support.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import "PDSRepositoryFactory.h"
#import "App/PDSConfiguration.h"
#import "Database/Service/ServiceDatabases.h"
#import "Core/Repositories/PDSLegacyAccountRepository.h"
#import "Core/Repositories/PDSSQLiteAccountRepository.h"
#import "Core/Repositories/PDSSQLiteSessionRepository.h"
#import "Core/Repositories/PDSSQLiteRepoRepository.h"
#import "Core/Repositories/PDSSQLiteRecordRepository.h"
#import "Core/Repositories/PDSSQLiteBlockRepository.h"
#import "Core/Repositories/PDSSQLiteBlobRepository.h"
#import "Database/Service/ServiceDatabases.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PDSRepositoryFactory

+ (id<PDSAccountRepository>)accountRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    
    if (config.useNewRepositoryImplementation) {
        return [[PDSSQLiteAccountRepository alloc] initWithServicePool:serviceDatabases.servicePool];
    } else {
        return [[PDSLegacyAccountRepository alloc] initWithServiceDatabases:serviceDatabases];
    }
}

+ (id<PDSSessionRepository>)sessionRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    return [[PDSSQLiteSessionRepository alloc] initWithServicePool:serviceDatabases.servicePool];
}

+ (id<PDSRepoRepository>)repoRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases {
    return [[PDSSQLiteRepoRepository alloc] initWithServicePool:serviceDatabases.servicePool];
}

+ (id<PDSRecordRepository>)recordRepositoryWithDatabasePool:(PDSDatabasePool *)databasePool {
    return [[PDSSQLiteRecordRepository alloc] initWithDatabasePool:databasePool];
}

+ (id<PDSBlockRepository>)blockRepositoryWithDatabasePool:(PDSDatabasePool *)databasePool {
    return [[PDSSQLiteBlockRepository alloc] initWithDatabasePool:databasePool];
}

+ (id<PDSBlobRepository>)blobRepositoryWithDatabasePool:(PDSDatabasePool *)databasePool {
    return [[PDSSQLiteBlobRepository alloc] initWithDatabasePool:databasePool];
}

@end

NS_ASSUME_NONNULL_END
