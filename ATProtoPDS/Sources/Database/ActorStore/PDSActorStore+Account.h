/*!
 @file PDSActorStore+Account.h

 @abstract PDSActorStore category for account-related database operations.

 @discussion Extends PDSActorStore with methods for managing account records
 in the actor's SQLite database. This includes account creation, updates,
 and credential management.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Database/ActorStore/ActorStore.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @category PDSActorStore (Account)

 @abstract Account management methods for PDSActorStore.

 @discussion This category extends PDSActorStore with account-specific database
 operations. Account records store user identity information including:

 - DID and handle
 - Email address
 - Password credentials (hashed)
 - 2FA settings
 - JWT tokens

 All methods in this category should be called within a transaction
 using transactWithBlock:error:.

 @see PDSActorStore
 @see PDSDatabaseAccount
 */
@interface PDSActorStore (Account)

@end

NS_ASSUME_NONNULL_END
