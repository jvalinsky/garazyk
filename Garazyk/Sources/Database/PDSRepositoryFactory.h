/*!
 @file PDSRepositoryFactory.h
 @abstract Factory for repository implementations.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"
#import "Core/Repositories/PDSRepoRepository.h"
#import "Core/Repositories/PDSRecordRepository.h"
#import "Core/Repositories/PDSBlockRepository.h"
#import "Core/Repositories/PDSBlobRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@class PDSServiceDatabases;

@interface PDSRepositoryFactory : NSObject

/*! 
 @method accountRepositoryWithServiceDatabases:
 @abstract Returns an account repository implementation based on configuration.
 */
+ (id<PDSAccountRepository>)accountRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

/*!
 @method sessionRepositoryWithServiceDatabases:
 @abstract Returns a session repository implementation.
 */
+ (id<PDSSessionRepository>)sessionRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

/*! Returns a repo metadata repository. */
+ (id<PDSRepoRepository>)repoRepositoryWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

/*! Returns a record repository with the given database pool. */
+ (id<PDSRecordRepository>)recordRepositoryWithDatabasePool:(PDSDatabasePool *)databasePool;

/*! Returns a block repository with the given database pool. */
+ (id<PDSBlockRepository>)blockRepositoryWithDatabasePool:(PDSDatabasePool *)databasePool;

/*! Returns a blob repository with the given database pool. */
+ (id<PDSBlobRepository>)blobRepositoryWithDatabasePool:(PDSDatabasePool *)databasePool;

@end

NS_ASSUME_NONNULL_END
