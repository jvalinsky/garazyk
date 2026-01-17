/*!
 @file PDSAccountManager.h
 @abstract Manager for account data access.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Core/Repositories/PDSAccountRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@interface PDSAccountManager : NSObject <PDSAccountRepository>

/*! Initializes the manager with a database pool. */
- (instancetype)initWithServicePool:(PDSDatabasePool *)servicePool;

@end

NS_ASSUME_NONNULL_END
