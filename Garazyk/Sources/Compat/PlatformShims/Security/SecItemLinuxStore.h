/**
 * @file SecItemLinuxStore.h
 *
 * @brief Persistent SQLite-backed keychain storage for Linux SecItem implementation.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Persistent keychain store using SQLite backend.

 Provides durable storage for keychain items across process restarts.
 Uses a single-file SQLite database at ~/.pds/keychain.db with proper
 transaction handling and schema versioning.
 */
@interface SecItemLinuxStore : NSObject

/**
 Shared singleton instance of the keychain store.
 */
+ (instancetype)sharedStore;

/**
 Add an item to the keychain.

 @param service Service identifier (required)
 @param account Account identifier (required)
 @param attributes Full attribute dictionary to store
 @return YES on success, NO on error (duplicate item, DB error)
 */
- (BOOL)addItemWithService:(NSString *)service
                   account:(NSString *)account
                attributes:(NSDictionary *)attributes
                     error:(NSError * _Nullable *)error;

/**
 Retrieve an item from the keychain.

 @param service Service identifier (required)
 @param account Account identifier (required)
 @param error Error pointer for DB errors
 @return Attribute dictionary if found, nil otherwise
 */
- (nullable NSDictionary *)itemWithService:(NSString *)service
                                   account:(NSString *)account
                                     error:(NSError * _Nullable *)error;

/**
 Update an item in the keychain.

 @param service Service identifier (required)
 @param account Account identifier (required)
 @param attributesToUpdate Dictionary of attributes to update/merge
 @param error Error pointer for DB errors
 @return YES on success, NO if item not found or DB error
 */
- (BOOL)updateItemWithService:(NSString *)service
                      account:(NSString *)account
            attributesToUpdate:(NSDictionary *)attributesToUpdate
                        error:(NSError * _Nullable *)error;

/**
 Delete an item from the keychain.

 @param service Service identifier (required)
 @param account Account identifier (required)
 @param error Error pointer for DB errors
 @return YES on success, NO if item not found or DB error
 */
- (BOOL)deleteItemWithService:(NSString *)service
                      account:(NSString *)account
                        error:(NSError * _Nullable *)error;

/**
 Check if an item exists in the keychain.

 @param service Service identifier (required)
 @param account Account identifier (required)
 @return YES if item exists, NO otherwise
 */
- (BOOL)itemExistsWithService:(NSString *)service
                      account:(NSString *)account;

@end

NS_ASSUME_NONNULL_END
