/*!
 @file PDSAccountRepository.h
 @abstract Protocol for account data access.
 @discussion Decouples the service layer from concrete database storage.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Database/PDSDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PDSAccountRepository <NSObject>

/*! Finds an account by its DID. */
- (nullable PDSDatabaseAccount *)accountForDid:(NSString *)did error:(NSError **)error;

/*! Finds an account by its handle. */
- (nullable PDSDatabaseAccount *)accountForHandle:(NSString *)handle error:(NSError **)error;

/*! Finds an account by its email. */
- (nullable PDSDatabaseAccount *)accountForEmail:(NSString *)email error:(NSError **)error;

/*! Persists a new or updated account. */
- (BOOL)saveAccount:(PDSDatabaseAccount *)account error:(NSError **)error;

/*! Deletes an account (and associated data if implied). */
- (BOOL)deleteAccount:(NSString *)did error:(NSError **)error;

/*! Lists accounts with pagination. */
- (nullable NSArray<PDSDatabaseAccount *> *)listAccountsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
