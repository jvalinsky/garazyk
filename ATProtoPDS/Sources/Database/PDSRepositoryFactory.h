/*!
 @file PDSRepositoryFactory.h
 @abstract Factory for repository implementations.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSAccountRepository.h"
#import "Core/Repositories/PDSBlobRepository.h"
#import "Core/Repositories/PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
